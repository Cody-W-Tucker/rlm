defmodule Rlm.Engine.RecoveryConstraintsTest do
  use ExUnit.Case, async: true

  alias Rlm.Engine.Prompt.RecoveryConstraints

  test "recovery mode mentions assess_evidence for convergence" do
    constraints =
      RecoveryConstraints.build(%{
        recovery_mode: true,
        async_disabled: false,
        broad_subqueries_disabled: false
      })

    assert constraints =~ "Recovery mode is active"
    assert constraints =~ "`assess_evidence()`"
    assert constraints =~ "next best move"
  end
end
