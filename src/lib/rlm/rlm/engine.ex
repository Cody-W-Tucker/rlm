defmodule Rlm.RLM.Engine do
  @moduledoc "Paper-style RLM loop around a persistent Python REPL."

  alias Rlm.RLM.Settings
  alias Rlm.Runtime.PythonRepl

  def run(prompt, context_bundle, %Settings{} = settings, provider_module, opts \\ []) do
    tracker = start_tracker()

    with {:ok, repl} <- PythonRepl.start(settings, opts),
         :ok <-
           PythonRepl.set_handler(repl, llm_query_handler(provider_module, settings, tracker)),
         :ok <- PythonRepl.set_context(repl, context_bundle.text),
         :ok <- PythonRepl.reset_final(repl) do
      result = iterate(prompt, context_bundle, settings, provider_module, repl, tracker, opts)
      PythonRepl.stop(repl)
      Agent.stop(tracker)
      result
    else
      {:error, message} ->
        Agent.stop(tracker)
        {:ok, error_result(prompt, message, tracker)}
    end
  end

  defp iterate(prompt, context_bundle, settings, provider_module, repl, tracker, opts) do
    history = [
      %{role: "user", content: build_context_metadata(context_bundle, settings, prompt)}
    ]

    execute_iterations(prompt, settings, provider_module, repl, tracker, opts, history, [], 1)
  end

  defp execute_iterations(
         prompt,
         settings,
         _provider_module,
         _repl,
         tracker,
         _opts,
         _history,
         records,
         iteration
       )
       when iteration > settings.max_iterations do
    {:ok,
     finalize_result(
       prompt,
       "[Maximum iterations reached without calling FINAL]",
       :max_iterations,
       false,
       settings.max_iterations,
       records,
       tracker
     )}
  end

  defp execute_iterations(
         prompt,
         settings,
         provider_module,
         repl,
         tracker,
         opts,
         history,
         records,
         iteration
       ) do
    total_sub_queries = tracker_get(tracker, :total_sub_queries)
    system_prompt = build_system_prompt(settings, iteration, total_sub_queries)

    emit(opts[:on_event], %{type: :iteration_start, iteration: iteration, prompt: prompt})

    with {:ok, root_response} <- provider_module.generate_code(history, system_prompt, settings),
         :ok <- add_tokens(tracker, root_response),
         {:ok, code} <- extract_code(root_response.text),
         {:ok, exec_result} <- PythonRepl.execute(repl, code) do
      emit(opts[:on_event], %{type: :generated_code, iteration: iteration, code: code})
      update_best_answer(tracker, exec_result)
      emit_iteration_output(opts[:on_event], iteration, exec_result)

      record = %{
        iteration: iteration,
        code: code,
        raw_response: root_response.text,
        stdout: exec_result.stdout,
        stderr: exec_result.stderr,
        has_final: exec_result.has_final,
        final_value: exec_result.final_value
      }

      next_records = records ++ [record]

      if exec_result.has_final and is_binary(exec_result.final_value) do
        {:ok,
         finalize_result(
           prompt,
           exec_result.final_value,
           :completed,
           true,
           iteration,
           next_records,
           tracker
         )}
      else
        next_history =
          history ++
            [
              %{role: "assistant", content: root_response.text},
              %{
                role: "user",
                content: build_iteration_feedback(exec_result, settings, iteration, tracker)
              }
            ]

        execute_iterations(
          prompt,
          settings,
          provider_module,
          repl,
          tracker,
          opts,
          next_history,
          next_records,
          iteration + 1
        )
      end
    else
      {:error, message} -> {:ok, error_result(prompt, message, tracker, iteration, records)}
    end
  end

  defp llm_query_handler(provider_module, settings, tracker) do
    fn sub_context, instruction ->
      with {:ok, _count} <- reserve_sub_query(tracker, settings.max_sub_queries),
           {:ok, response} <-
             provider_module.complete_subquery(sub_context, instruction, settings),
           :ok <- add_tokens(tracker, response) do
        {:ok, %{text: response.text}}
      else
        {:error, message} -> {:error, message}
      end
    end
  end

  defp reserve_sub_query(tracker, max_sub_queries) do
    Agent.get_and_update(tracker, fn state ->
      if state.total_sub_queries >= max_sub_queries do
        {{:error,
          "Maximum sub-query limit (#{max_sub_queries}) reached. Call FINAL() with your best answer now."},
         state}
      else
        next_state = %{state | total_sub_queries: state.total_sub_queries + 1}
        {{:ok, next_state.total_sub_queries}, next_state}
      end
    end)
  end

  defp start_tracker do
    {:ok, tracker} =
      Agent.start_link(fn ->
        %{
          total_sub_queries: 0,
          input_tokens: 0,
          output_tokens: 0,
          best_answer_so_far: nil,
          best_answer_reason: nil
        }
      end)

    tracker
  end

  defp add_tokens(tracker, response) do
    Agent.update(tracker, fn state ->
      %{
        state
        | input_tokens: state.input_tokens + (response[:input_tokens] || 0),
          output_tokens: state.output_tokens + (response[:output_tokens] || 0)
      }
    end)
  end

  defp tracker_get(tracker, key), do: Agent.get(tracker, &Map.fetch!(&1, key))

  defp update_best_answer(tracker, exec_result) do
    cond do
      exec_result.has_final and is_binary(exec_result.final_value) and
          String.trim(exec_result.final_value) != "" ->
        put_best_answer(tracker, exec_result.final_value, :final_value)

      String.trim(exec_result.stdout) != "" ->
        put_best_answer(tracker, exec_result.stdout, :stdout)

      true ->
        :ok
    end
  end

  defp put_best_answer(tracker, answer, reason) do
    trimmed = String.trim(answer)

    Agent.update(tracker, fn state ->
      %{state | best_answer_so_far: trimmed, best_answer_reason: reason}
    end)
  end

  defp build_context_metadata(context_bundle, settings, prompt) do
    context = context_bundle.text
    lines = String.split(context, "\n")
    source_count = length(context_bundle.entries)

    source_types =
      context_bundle.entries
      |> Enum.frequencies_by(& &1.type)
      |> Enum.map_join(", ", fn {type, count} -> "#{count} #{type}" end)

    source_preview =
      context_bundle.entries
      |> Enum.take(8)
      |> Enum.map_join("\n", &"  - #{&1.label}")

    source_preview =
      if source_count > 8 do
        source_preview <> "\n  - ... (#{source_count - 8} more sources)"
      else
        source_preview
      end

    source_types_display = if source_types == "", do: "none", else: source_types

    strategy_hint =
      cond do
        context_bundle.bytes <= 20_000 and source_count <= 20 ->
          "This looks small-to-medium. Prefer direct reasoning over the whole context or one small number of sub-queries."

        context_bundle.bytes <= 80_000 ->
          "This looks medium-sized. Use the fewest chunks that could work, and prefer sequential chunking over parallel fan-out."

        true ->
          "This looks large. Structure the work carefully, keep chunk counts low, and maintain a best-so-far answer."
      end

    [
      "Context Header:",
      "  - Query: #{prompt}",
      "  - Size: #{String.length(context)} characters, #{length(lines)} lines, #{source_count} source(s)",
      "  - Source types: #{source_types_display}",
      "  - Strategy hint: #{strategy_hint}",
      "",
      "Source preview:",
      if(source_preview == "", do: "  - (inline or empty context)", else: source_preview),
      "",
      "First #{settings.metadata_preview_lines} lines:",
      Enum.take(lines, settings.metadata_preview_lines) |> Enum.join("\n"),
      "",
      "Last #{settings.metadata_preview_lines} lines:",
      Enum.take(lines, -settings.metadata_preview_lines) |> Enum.join("\n")
    ]
    |> Enum.join("\n")
  end

  defp build_system_prompt(settings, iteration, sub_queries_used) do
    remaining_iterations = settings.max_iterations - iteration + 1
    remaining_sub_queries = settings.max_sub_queries - sub_queries_used

    sub_model_note =
      if settings.sub_model,
        do: "Sub-queries use #{settings.sub_model}.",
        else: "Sub-queries use the root model."

    """
    You are a Recursive Language Model (RLM) agent. You process arbitrarily large contexts by writing Python code in a persistent REPL.

    Budget:
    - #{remaining_iterations} iteration(s) remaining out of #{settings.max_iterations}
    - #{remaining_sub_queries} sub-query call(s) remaining out of #{settings.max_sub_queries}
    - #{sub_model_note}

    Available in the REPL:
    1. `context`: the full input text as a Python string.
    2. `llm_query(sub_context, instruction)`: ask a sub-query over a chunk.
    3. `async_llm_query(sub_context, instruction)`: async wrapper for parallel chunk work.
    4. `FINAL(answer)` and `FINAL_VAR(value)`: finish with the final answer.

    Rules:
    - Respond with ONLY a Python code block.
    - Use print() for intermediate output.
    - Treat iterations, sub-queries, tokens, and latency as a strict budget.
    - Every `llm_query()` call is expensive. Minimize calls and prefer direct reasoning when the context header says the input is small or medium.
    - Do not chunk by default. Start with direct synthesis or a single targeted sub-query unless the context is clearly too large.
    - If you chunk, use the fewest chunks that could work and keep the code simple.
    - Do not use parallel fan-out unless the context is clearly very large and the expected gain is worth the budget.
    - If async or a sub-query strategy fails once, do not retry the same strategy. Fall back to simpler sequential reasoning.
    - Keep a best-so-far answer in a variable and finalize early when it is good enough.
    - Filter and slice context with Python before calling llm_query().
    - Store intermediate results in variables because the REPL is persistent.
    - Call FINAL() as soon as you have a useful answer; do not spend budget polishing unnecessarily.
    """
  end

  defp build_iteration_feedback(exec_result, settings, iteration, tracker) do
    parts = []

    parts =
      if exec_result.stdout != "",
        do:
          parts ++ ["Output:\n#{truncate_output(exec_result.stdout, settings.truncate_length)}"],
        else: parts

    parts =
      if exec_result.stderr != "",
        do: parts ++ ["Stderr:\n#{String.slice(exec_result.stderr, 0, 5_000)}"],
        else: parts

    parts =
      if parts == [],
        do: ["(No output produced. The code ran without printing anything.)"],
        else: parts

    (parts ++
       [
         "Iteration #{iteration}/#{settings.max_iterations}. Sub-queries used: #{tracker_get(tracker, :total_sub_queries)}/#{settings.max_sub_queries}.",
         "Continue processing or call FINAL() when you have the answer."
       ])
    |> Enum.join("\n\n")
  end

  defp truncate_output(text, truncate_length) do
    if String.length(text) <= truncate_length do
      if text == "", do: "[EMPTY OUTPUT]", else: text
    else
      "[TRUNCATED: Last #{truncate_length} chars shown].. " <>
        String.slice(text, -truncate_length, truncate_length)
    end
  end

  defp extract_code(text) do
    case Regex.run(~r/```(?:python|repl)?\s*\n([\s\S]*?)```/, text, capture: :all_but_first) do
      [code] ->
        {:ok, String.trim(code)}

      _ ->
        trimmed = String.trim(text)

        if trimmed != "" and String.contains?(trimmed, ["print(", "FINAL(", "llm_query(", "for "]) do
          {:ok, trimmed}
        else
          {:error, "Could not extract Python code from provider response."}
        end
    end
  end

  defp finalize_result(prompt, answer, status, completed?, iterations, records, tracker) do
    %{
      prompt: prompt,
      answer: answer,
      status: status,
      completed?: completed?,
      iterations: iterations,
      total_sub_queries: tracker_get(tracker, :total_sub_queries),
      input_tokens: tracker_get(tracker, :input_tokens),
      output_tokens: tracker_get(tracker, :output_tokens),
      depth: 0,
      best_answer_reason: tracker_get(tracker, :best_answer_reason),
      iteration_records: records
    }
  end

  defp error_result(prompt, message, tracker, iterations \\ 0, records \\ []) do
    answer = render_failure_answer(tracker_get(tracker, :best_answer_so_far), message)

    finalize_result(
      prompt,
      answer,
      :provider_error,
      false,
      iterations,
      records,
      tracker
    )
  end

  defp render_failure_answer(nil, message) do
    "The run could not finish because #{error_diagnosis(message)}"
  end

  defp render_failure_answer(best_answer, message) do
    best_answer <>
      "\n\nNote: this is the best partial answer available because #{error_diagnosis(message)}"
  end

  defp error_diagnosis(message) do
    cond do
      String.contains?(message, "timed out") ->
        "the provider timed out. Retry with a narrower question or a longer timeout."

      String.contains?(message, "Maximum sub-query limit") ->
        "the run exhausted its sub-query budget. Retry with a narrower question or a higher sub-query limit."

      String.contains?(message, "shutting down") or String.contains?(message, "Task supervisor") ->
        "the runtime became unavailable during execution. Retry the command; if it persists, inspect the runtime startup path."

      String.contains?(message, "Could not extract Python code") ->
        "the provider returned a response the runtime could not execute. Retry the command or adjust the model/provider configuration."

      true ->
        "the provider or runtime failed before the run could complete. Retry the command; if it persists, inspect the provider and runtime configuration."
    end
  end

  defp emit_iteration_output(on_event, iteration, exec_result) do
    if exec_result.stdout != "" do
      emit(on_event, %{
        type: :iteration_output,
        iteration: iteration,
        stream: :stdout,
        text: exec_result.stdout
      })
    end

    if exec_result.stderr != "" do
      emit(on_event, %{
        type: :iteration_output,
        iteration: iteration,
        stream: :stderr,
        text: exec_result.stderr
      })
    end
  end

  defp emit(nil, _event), do: :ok
  defp emit(fun, event), do: fun.(event)
end
