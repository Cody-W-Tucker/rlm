defmodule Rlm.Engine.CoreRuntimeTest do
  use ExUnit.Case, async: false

  alias Rlm.Engine
  alias Rlm.TestHelpers

  test "executes code in the Python runtime and returns a final answer" do
    settings = TestHelpers.settings(%{max_iterations: 4, max_sub_queries: 3})
    bundle = %{entries: [], text: "abcdef", bytes: 6}

    assert {:ok, result} = Engine.run("summarize", bundle, settings, Rlm.Providers.Mock)
    assert result.completed?
    assert result.answer =~ "Observed context"
    assert result.answer =~ "abcdef"
    assert result.total_sub_queries == 0
    assert length(result.iteration_records) == 1
  end

  test "returns bounded result when max iterations are reached" do
    settings = TestHelpers.settings(%{max_iterations: 2})
    bundle = %{entries: [], text: "abcdef", bytes: 6}

    assert {:ok, result} = Engine.run("loop forever", bundle, settings, Rlm.TestLoopProvider)
    assert result.status == :max_iterations
    refute result.completed?
  end

  test "does not promote raw evidence logs to the best partial answer" do
    settings = TestHelpers.settings(%{max_iterations: 1})
    bundle = %{entries: [], text: "abcdef", bytes: 6}

    assert {:ok, result} =
             Engine.run("loop forever", bundle, settings, Rlm.TestEvidenceLoopProvider)

    assert result.status == :max_iterations
    refute result.completed?
    assert result.answer == "The run reached its iteration limit before it could produce a reliable answer."
    assert result.best_answer_reason == nil
    assert hd(result.iteration_records).stdout =~ "=== KEY EXAMPLE 1 ==="
  end

  test "strips malformed fenced responses before execution" do
    settings = TestHelpers.settings(%{max_iterations: 1})
    bundle = %{entries: [], text: "abcdef", bytes: 6}

    assert {:ok, result} =
             Engine.run("summarize", bundle, settings, Rlm.TestMalformedFenceProvider)

    assert result.completed?
    assert result.answer == "should not execute"
    assert length(result.iteration_records) == 1
  end

  test "still accepts unfenced plain python responses" do
    settings = TestHelpers.settings(%{max_iterations: 1})
    bundle = %{entries: [], text: "abcdef", bytes: 6}

    assert {:ok, result} = Engine.run("summarize", bundle, settings, Rlm.TestPlainPythonProvider)

    assert result.completed?
    assert result.answer == "plain python works"
    assert hd(result.iteration_records).status == :ok
  end

  test "executes multiple fenced python blocks sequentially in one iteration" do
    settings = TestHelpers.settings(%{max_iterations: 1})
    bundle = %{entries: [], text: "abcdef", bytes: 6}

    assert {:ok, result} = Engine.run("summarize", bundle, settings, Rlm.TestMultiFenceProvider)

    assert result.completed?
    assert result.answer == "alpha beta"
    assert length(result.iteration_records) == 1

    record = hd(result.iteration_records)
    assert record.stdout == "alpha\nalpha beta\n"
    assert record.code =~ "value = \"alpha\""
    assert record.code =~ "FINAL(value)"
  end

  test "salvages an unclosed final fenced block after earlier blocks" do
    settings = TestHelpers.settings(%{max_iterations: 1})
    bundle = %{entries: [], text: "abcdef", bytes: 6}

    assert {:ok, result} =
             Engine.run("summarize", bundle, settings, Rlm.TestMultiFenceUnclosedTailProvider)

    assert result.completed?
    assert result.answer == "alpha beta"
    assert length(result.iteration_records) == 1
  end

  test "salvages prose followed by plain python" do
    settings = TestHelpers.settings(%{max_iterations: 1})
    bundle = %{entries: [], text: "abcdef", bytes: 6}

    assert {:ok, result} =
             Engine.run("summarize", bundle, settings, Rlm.TestProseThenPythonProvider)

    assert result.completed?
    assert result.answer == "salvaged from prose"
    assert result.failure_history == []
  end

  test "salvages repeated interleaved python fences before execution" do
    settings = TestHelpers.settings(%{max_iterations: 1})
    bundle = %{entries: [], text: "abcdef", bytes: 6}

    assert {:ok, result} =
             Engine.run("summarize", bundle, settings, Rlm.TestInterleavedFenceProvider)

    assert result.completed?
    assert result.answer == "alpha beta"
    assert length(result.iteration_records) == 1
  end
end
