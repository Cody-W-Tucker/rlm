defmodule Rlm.Engine.RunState do
  @moduledoc "Mutable run state for counters, recovery flags, and best-so-far answers."

  def start_link do
    Agent.start_link(fn ->
      %{
        total_sub_queries: 0,
        input_tokens: 0,
        output_tokens: 0,
        best_answer_so_far: nil,
        best_answer_reason: nil,
        last_successful_subquery: nil,
        recovery_attempted?: false,
        recovery_flags: %{
          recovery_mode: false,
          async_disabled: false,
          broad_subqueries_disabled: false
        },
        failure_history: []
      }
    end)
  end

  def stop(state), do: Agent.stop(state)

  def snapshot(state), do: Agent.get(state, & &1)

  def reserve_sub_query(state, max_sub_queries) do
    Agent.get_and_update(state, fn current ->
      if current.total_sub_queries >= max_sub_queries do
        {{:error,
          "Maximum sub-query limit (#{max_sub_queries}) reached. Call FINAL() with your best answer now."},
         current}
      else
        next = %{current | total_sub_queries: current.total_sub_queries + 1}
        {{:ok, next.total_sub_queries}, next}
      end
    end)
  end

  def add_tokens(state, response) do
    Agent.update(state, fn current ->
      %{
        current
        | input_tokens: current.input_tokens + (response[:input_tokens] || 0),
          output_tokens: current.output_tokens + (response[:output_tokens] || 0)
      }
    end)
  end

  def remember_subquery_success(state, instruction) do
    Agent.update(state, fn current ->
      %{current | last_successful_subquery: instruction}
    end)
  end

  def remember_best_answer_from_exec(state, exec_result) do
    cond do
      exec_result.has_final and is_binary(exec_result.final_value) and
          String.trim(exec_result.final_value) != "" ->
        remember_best_answer(state, exec_result.final_value, :final_value)

      String.trim(exec_result.stdout) != "" ->
        remember_best_answer(state, exec_result.stdout, :stdout)

      true ->
        :ok
    end
  end

  def remember_best_answer(state, answer, reason) when is_binary(answer) do
    trimmed = String.trim(answer)

    if trimmed == "" do
      :ok
    else
      Agent.update(state, fn current ->
        %{current | best_answer_so_far: trimmed, best_answer_reason: reason}
      end)
    end
  end

  def note_failure(state, failure) do
    Agent.update(state, fn current ->
      failure_record = %{
        class: failure.class,
        source: failure.source,
        recoverable: failure.recoverable,
        message: failure.message
      }

      %{current | failure_history: current.failure_history ++ [failure_record]}
    end)
  end

  def apply_recovery(state, recovery_flags) do
    Agent.update(state, fn current ->
      %{
        current
        | recovery_attempted?: true,
          recovery_flags: Map.merge(current.recovery_flags, recovery_flags)
      }
    end)
  end
end
