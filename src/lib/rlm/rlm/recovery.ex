defmodule Rlm.RLM.Recovery do
  @moduledoc "Recovery policy that constrains the next move after a classified failure."

  alias Rlm.RLM.Failure

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
      recovery_instruction(failure),
      best_answer_instruction(run_state)
    ]
    |> Enum.join("\n")
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
