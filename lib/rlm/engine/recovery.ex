defmodule Rlm.Engine.Recovery do
  @moduledoc "Recovery policy that constrains the next move after a classified failure."

  alias Rlm.Engine.Failure

  def allowed?(%Failure{} = failure, run_state, settings, iteration) do
    failure.recoverable and not run_state.recovery_attempted? and
      iteration < settings.max_iterations
  end

  def flags_for(%Failure{class: class}) do
    base = %{recovery_mode: true}

    case class do
      :async_failed -> Map.merge(base, %{async_disabled: true, broad_subqueries_disabled: true})
      :provider_timeout -> Map.merge(base, %{broad_subqueries_disabled: true})
      :subquery_budget_exhausted -> Map.merge(base, %{broad_subqueries_disabled: true})
      :subquery_failed -> Map.merge(base, %{broad_subqueries_disabled: true})
      _ -> base
    end
  end

  def feedback(%Failure{} = failure, run_state) do
    [
      "Recovery mode: the previous iteration failed with #{failure.class}.",
      "Failure detail: #{failure.message}",
      failing_block_feedback(failure),
      runtime_suggestion(failure),
      recovery_instruction(failure),
      best_answer_instruction(run_state)
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.join("\n")
  end

  defp failing_block_feedback(%Failure{message: message}) do
    index = capture(~r/Failure occurred in block (\d+) of (\d+)\./, message, 1)
    total = capture(~r/Failure occurred in block (\d+) of (\d+)\./, message, 2)
    code = capture(~r/Failing block code:\n([\s\S]*)$/, message, 1)

    if index && total && code do
      "The failure happened in block #{index}/#{total}. Fix or avoid only this block:\n#{code}"
    else
      nil
    end
  end

  defp runtime_suggestion(%Failure{message: message}) do
    case Regex.run(~r/Did you mean: '([^']+)'\?/, message, capture: :all_but_first) do
      [suggestion] ->
        "Python suggested this likely fix: use `#{suggestion}` if that matches your intended variable name."

      _ ->
        nil
    end
  end

  defp capture(regex, text, group) do
    case Regex.run(regex, text, capture: :all_but_first) do
      captures when is_list(captures) and length(captures) >= group ->
        Enum.at(captures, group - 1)

      _ ->
        nil
    end
  end

  defp recovery_instruction(%Failure{class: :provider_timeout}) do
    "Do not retry the same broad sub-query strategy. Use direct reasoning or one narrow sub-query and finalize early."
  end

  defp recovery_instruction(%Failure{class: :async_failed}) do
    "Do not use async again in this run. Use direct reasoning or one narrow sequential sub-query."
  end

  defp recovery_instruction(%Failure{class: :subquery_budget_exhausted}) do
    "Do not issue more sub-queries. Finalize from the best available evidence now."
  end

  defp recovery_instruction(_failure) do
    "Use a simpler strategy than the previous iteration and avoid repeating the same failure pattern."
  end

  defp best_answer_instruction(%{best_answer_so_far: nil}) do
    "If you can answer directly from the context already in memory, do that now."
  end

  defp best_answer_instruction(_run_state) do
    "A best-so-far answer exists. Reuse it, add only high-value evidence, and finalize."
  end
end
