defmodule Rlm.Engine.Recovery.Strategy do
  @moduledoc false

  alias Rlm.Engine.Failure

  def flags_for(%Failure{class: class}) do
    base = %{recovery_mode: true}

    case class do
      :async_failed -> Map.merge(base, %{async_disabled: true, broad_subqueries_disabled: true})
      :provider_timeout -> Map.merge(base, %{broad_subqueries_disabled: true})
      :total_timeout -> Map.merge(base, %{broad_subqueries_disabled: true})
      :first_byte_timeout -> Map.merge(base, %{broad_subqueries_disabled: true})
      :subquery_budget_exhausted -> Map.merge(base, %{broad_subqueries_disabled: true})
      :subquery_failed -> Map.merge(base, %{broad_subqueries_disabled: true})
      _ -> base
    end
  end

  def recovery_instruction(%Failure{class: :provider_timeout}) do
    "Do not retry the same broad sub-query strategy. Use direct reasoning or one narrow sub-query and finalize early."
  end

  def recovery_instruction(%Failure{class: :total_timeout}) do
    "The total request deadline was already exhausted. Do not repeat the same broad strategy; finalize from the best partial answer or do one narrow direct step."
  end

  def recovery_instruction(%Failure{class: :first_byte_timeout}) do
    "The provider never started responding. Do not blindly retry the same broad request; simplify it sharply or switch to direct reasoning and finalize early."
  end

  def recovery_instruction(%Failure{class: :async_failed}) do
    "Do not use async again in this run. Use direct reasoning or one narrow sequential sub-query."
  end

  def recovery_instruction(%Failure{class: :subquery_budget_exhausted}) do
    "Do not issue more sub-queries. Finalize from the best available evidence now."
  end

  def recovery_instruction(%Failure{class: :ungrounded_final_answer}) do
    "Do not keep expanding the search. Inspect the specific missing files you cited or remove those unsupported claims, then finalize from the verified evidence set."
  end

  def recovery_instruction(%Failure{class: :insufficient_grounding}) do
    "Do not finalize from scouting alone or repeated search. First call `assess_evidence()` with your current hits, reads, and working hypothesis so you know whether to read more, run a contradiction pass, or finalize. Then promote the strongest candidates to `read_file()` or `read_jsonl()` until you have either at least 3 relevant files or at least 3 targeted line windows backed by at least one hit-followup read before finalizing."
  end

  def recovery_instruction(_failure) do
    "Use a simpler strategy than the previous iteration and avoid repeating the same failure pattern."
  end
end
