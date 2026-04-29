defmodule Rlm.Engine.Iteration do
  @moduledoc false

  alias Rlm.Engine.Execution.BlockRunner
  alias Rlm.Engine.Failure
  alias Rlm.Engine.Finalizer
  alias Rlm.Engine.Grounding.Policy, as: GroundingPolicy
  alias Rlm.Engine.Policy
  alias Rlm.Engine.Recovery
  alias Rlm.Engine.Response.Extractor
  alias Rlm.Engine.RunState
  alias Rlm.Engine.RuntimeOutcome
  alias Rlm.Providers.RequestManager

  def run(prompt, context_bundle, settings, provider_module, repl, run_state, opts) do
    history = [
      %{role: "user", content: Policy.context_metadata(context_bundle, settings, prompt)}
    ]

    execute_iterations(
      prompt,
      context_bundle,
      settings,
      provider_module,
      repl,
      run_state,
      opts,
      history,
      [],
      1
    )
  end

  def llm_query_handler(provider_module, settings, run_state) do
    fn sub_context, instruction ->
      with {:ok, _count} <- RunState.reserve_sub_query(run_state, settings.max_sub_queries),
           {:ok, response} <-
             provider_module.complete_subquery(sub_context, instruction, settings) do
        RunState.add_tokens(run_state, response)
        RunState.remember_subquery_success(run_state, instruction, response.text)
        {:ok, %{text: response.text}}
      else
        {:error, %RequestManager.Error{} = error} ->
          RunState.remember_partial_subquery(run_state, instruction, error.partial_text)
          {:error, RequestManager.format_error_for_runtime(error)}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  defp execute_iterations(
         prompt,
         context_bundle,
         settings,
         _provider_module,
         _repl,
         run_state,
         _opts,
         _history,
         records,
         iteration
       )
       when iteration > settings.max_iterations do
    {:ok,
     Finalizer.finalize_incomplete_result(
       prompt,
       context_bundle,
       :max_iterations,
       settings.max_iterations,
       records,
       run_state
     )}
  end

  defp execute_iterations(
         prompt,
         context_bundle,
         settings,
         provider_module,
         repl,
         run_state,
         opts,
         history,
         records,
         iteration
       ) do
    snapshot = RunState.snapshot(run_state)
    system_prompt = Policy.system_prompt(settings, iteration, snapshot)

    emit(opts[:on_event], %{type: :iteration_start, iteration: iteration, prompt: prompt})

    case provider_module.generate_code(history, system_prompt, settings) do
      {:ok, root_response} ->
        RunState.add_tokens(run_state, root_response)

        handle_generated_iteration(
          prompt,
          context_bundle,
          settings,
          provider_module,
          repl,
          run_state,
          opts,
          history,
          records,
          iteration,
          root_response
        )

      {:error, reason} ->
        handle_failure(
          prompt,
          context_bundle,
          Failure.from_stage(:provider, reason),
          settings,
          provider_module,
          repl,
          run_state,
          opts,
          history,
          records,
          iteration
        )
    end
  end

  defp handle_generated_iteration(
         prompt,
         context_bundle,
         settings,
         provider_module,
         repl,
         run_state,
         opts,
         history,
         records,
         iteration,
         root_response
       ) do
    case Extractor.extract_code_blocks(root_response.text) do
      {:ok, code_blocks} ->
        code = Enum.join(code_blocks, "\n\n")
        emit(opts[:on_event], %{type: :generated_code, iteration: iteration, code: code})

        case BlockRunner.execute_code_blocks(repl, code_blocks) do
          {:ok, exec_result} ->
            if not exec_result.has_final do
              RunState.remember_best_answer_from_exec(run_state, exec_result)
            end

            Finalizer.emit_iteration_output(opts[:on_event], iteration, exec_result)

            record = %{
              iteration: iteration,
              code: code,
              raw_response: root_response.text,
              stdout: exec_result.stdout,
              stderr: exec_result.stderr,
              has_final: exec_result.has_final,
              final_value: exec_result.final_value,
              status: exec_result.status,
              error_kind: exec_result.error_kind,
              recovery_kind: exec_result.recovery_kind,
              details: exec_result.details
            }

            next_records = records ++ [record]

            case classify_exec_result(context_bundle, exec_result, next_records) do
              {:finalized, final_answer} ->
                RunState.remember_best_answer(run_state, final_answer, :final_value)

                {:ok,
                 Finalizer.finalize_result(
                   prompt,
                   context_bundle,
                   final_answer,
                   :completed,
                   true,
                   iteration,
                   next_records,
                   run_state
                 )}

              {:recoverable_failure, failure} ->
                recovery_history = history ++ [%{role: "assistant", content: root_response.text}]

                handle_failure(
                  prompt,
                  context_bundle,
                  failure,
                  settings,
                  provider_module,
                  repl,
                  run_state,
                  opts,
                  recovery_history,
                  next_records,
                  iteration
                )

              {:unrecoverable_failure, failure} ->
                recovery_history = history ++ [%{role: "assistant", content: root_response.text}]

                handle_failure(
                  prompt,
                  context_bundle,
                  failure,
                  settings,
                  provider_module,
                  repl,
                  run_state,
                  opts,
                  recovery_history,
                  next_records,
                  iteration
                )

              :continue ->
                next_history =
                  history ++
                    [
                      %{role: "assistant", content: root_response.text},
                      %{
                        role: "user",
                        content:
                          Policy.iteration_feedback(
                            exec_result,
                            settings,
                            iteration,
                            RunState.snapshot(run_state),
                            context_bundle
                          )
                      }
                    ]

                execute_iterations(
                  prompt,
                  context_bundle,
                  settings,
                  provider_module,
                  repl,
                  run_state,
                  opts,
                  next_history,
                  next_records,
                  iteration + 1
                )
            end

          {:error, reason} ->
            handle_failure(
              prompt,
              context_bundle,
              Failure.from_stage(:runtime, reason),
              settings,
              provider_module,
              repl,
              run_state,
              opts,
              history,
              records,
              iteration
            )
        end

      {:error, reason} ->
        handle_failure(
          prompt,
          context_bundle,
          Failure.from_stage(:response_format, reason),
          settings,
          provider_module,
          repl,
          run_state,
          opts,
          history,
          records,
          iteration
        )
    end
  end

  defp handle_failure(
         prompt,
         context_bundle,
         failure,
         settings,
         provider_module,
         repl,
         run_state,
         opts,
         history,
         records,
         iteration
       ) do
    RunState.note_failure(run_state, failure)
    snapshot = RunState.snapshot(run_state)

    if Recovery.allowed?(failure, snapshot, settings, iteration) do
      RunState.apply_recovery(run_state, Recovery.flags_for(failure))

      next_history =
        history ++
          [%{role: "user", content: Recovery.feedback(failure, RunState.snapshot(run_state))}]

      execute_iterations(
        prompt,
        context_bundle,
        settings,
        provider_module,
        repl,
        run_state,
        opts,
        next_history,
        records,
        iteration + 1
      )
    else
      {:ok, Finalizer.error_result(prompt, context_bundle, failure, run_state, iteration, records)}
    end
  end

  defp classify_exec_result(context_bundle, exec_result, iteration_records) do
    cond do
      exec_result.has_final and is_binary(exec_result.final_value) and
          String.trim(exec_result.final_value) != "" ->
        final_answer = String.trim(exec_result.final_value)

        case GroundingPolicy.validate_final_answer(
               context_bundle,
               final_answer,
               exec_result.details || %{},
               iteration_records
             ) do
          :ok -> {:finalized, final_answer}
          {:error, reason} -> {:recoverable_failure, Failure.from_stage(:grounding, reason)}
        end

      true ->
        RuntimeOutcome.classify(exec_result)
    end
  end

  defp emit(nil, _event), do: :ok
  defp emit(fun, event), do: fun.(event)
end
