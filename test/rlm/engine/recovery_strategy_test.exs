defmodule Rlm.Engine.RecoveryStrategyTest do
  use ExUnit.Case, async: true

  alias Rlm.Engine.Failure
  alias Rlm.Engine.Recovery.Strategy

  test "applies stricter recovery flags to total and first-byte timeouts" do
    total_timeout = %Failure{class: :total_timeout}
    first_byte_timeout = %Failure{class: :first_byte_timeout}

    assert Strategy.flags_for(total_timeout) == %{
             recovery_mode: true,
             broad_subqueries_disabled: true
           }

    assert Strategy.flags_for(first_byte_timeout) == %{
             recovery_mode: true,
             broad_subqueries_disabled: true
           }
  end

  test "returns timeout-specific recovery instructions" do
    assert Strategy.recovery_instruction(%Failure{class: :total_timeout}) =~
             "finalize from the best partial answer"

    assert Strategy.recovery_instruction(%Failure{class: :first_byte_timeout}) =~
             "never started responding"
  end

  test "insufficient grounding recovery points the model to assess_evidence" do
    instruction = Strategy.recovery_instruction(%Failure{class: :insufficient_grounding})

    assert instruction =~ "`assess_evidence()`"
    assert instruction =~ "current hits, reads, and working hypothesis"
    assert instruction =~ "read more, run a contradiction pass, or finalize"
  end
end
