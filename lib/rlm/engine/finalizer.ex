defmodule Rlm.Engine.Finalizer do
  @moduledoc false

  alias Rlm.Engine.Failure
  alias Rlm.Engine.Grounding.Grade, as: GroundingGrade
  alias Rlm.Engine.RunState

  def finalize_result(prompt, context_bundle, answer, status, completed?, iterations, records, run_state) do
    snapshot = RunState.snapshot(run_state)
    grounding = GroundingGrade.assess(context_bundle, records)

    %{
      prompt: prompt,
      answer: answer,
      status: status,
      completed?: completed?,
      iterations: iterations,
      total_sub_queries: snapshot.total_sub_queries,
      input_tokens: snapshot.input_tokens,
      output_tokens: snapshot.output_tokens,
      depth: 0,
      best_answer_reason: snapshot.best_answer_reason,
      recovery_flags: snapshot.recovery_flags,
      failure_history: snapshot.failure_history,
      last_successful_subquery: snapshot.last_successful_subquery,
      last_successful_subquery_result: snapshot.last_successful_subquery_result,
      grounding: grounding,
      iteration_records: records
    }
  end

  def finalize_incomplete_result(prompt, context_bundle, status, iterations, records, run_state) do
    snapshot = RunState.snapshot(run_state)

    answer =
      case snapshot.best_answer_so_far do
        nil ->
          "The run reached its iteration limit before it could produce a reliable answer."

        best ->
          best <>
            "\n\nNote: this is the best partial answer available because the run reached its iteration limit."
      end

    finalize_result(prompt, context_bundle, answer, status, false, iterations, records, run_state)
  end

  def error_result(prompt, context_bundle, failure, run_state, iterations \\ 0, records \\ []) do
    answer = render_failure_answer(RunState.snapshot(run_state).best_answer_so_far, failure)

    finalize_result(
      prompt,
      context_bundle,
      answer,
      Failure.status(failure),
      false,
      iterations,
      records,
      run_state
    )
  end

  def emit_iteration_output(on_event, iteration, exec_result) do
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

  defp render_failure_answer(nil, failure) do
    "The run could not finish because #{Failure.diagnosis(failure)}"
  end

  defp render_failure_answer(best_answer, failure) do
    best_answer <>
      "\n\nNote: this is the best partial answer available because #{Failure.diagnosis(failure)}"
  end

  defp emit(nil, _event), do: :ok
  defp emit(fun, event), do: fun.(event)
end
