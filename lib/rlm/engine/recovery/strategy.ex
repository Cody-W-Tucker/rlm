defmodule Rlm.Engine.Recovery.Strategy do
  @moduledoc false

  alias Rlm.Engine.Failure

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

  def recovery_instruction(%Failure{class: :provider_timeout}) do
    "Do not retry the same broad sub-query strategy. Use direct reasoning or one narrow sub-query and finalize early."
  end

  def recovery_instruction(%Failure{class: :async_failed}) do
    "Do not use async again in this run. Use direct reasoning or one narrow sequential sub-query."
  end

  def recovery_instruction(%Failure{class: :subquery_budget_exhausted}) do
    "Do not issue more sub-queries. Finalize from the best available evidence now."
  end

  def recovery_instruction(_failure) do
    "Use a simpler strategy than the previous iteration and avoid repeating the same failure pattern."
  end
end
