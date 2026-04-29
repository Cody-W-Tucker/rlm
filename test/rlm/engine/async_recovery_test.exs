defmodule Rlm.Engine.AsyncRecoveryTest do
  use ExUnit.Case, async: false

  alias Rlm.Engine
  alias Rlm.TestHelpers

  test "iteration feedback steers silent sub-query results toward finalization" do
    settings = TestHelpers.settings(%{max_iterations: 2, max_sub_queries: 2})
    bundle = %{entries: [], text: "abcdef", bytes: 6}

    assert {:ok, result} =
             Engine.run("summarize", bundle, settings, Rlm.TestSilentSubqueryRecoveryProvider)

    assert result.completed?
    assert result.answer == "silent subquery answer"
    assert result.total_sub_queries == 1
  end

  test "handles async_llm_query when model code forgets to await it" do
    settings = TestHelpers.settings(%{max_iterations: 2, max_sub_queries: 3})
    bundle = %{entries: [], text: "abcdef", bytes: 6}

    assert {:ok, result} = Engine.run("summarize", bundle, settings, Rlm.TestAsyncProvider)
    assert result.completed?
    assert result.answer == "async summary"
    assert hd(result.iteration_records).stdout =~ "async summary"
    assert result.total_sub_queries == 1
  end

  test "uses async wrapper fallback for top-level await" do
    settings = TestHelpers.settings(%{max_iterations: 1, max_sub_queries: 2})
    bundle = %{entries: [], text: "abcdef", bytes: 6}

    assert {:ok, result} =
             Engine.run("summarize", bundle, settings, Rlm.TestTopLevelAwaitProvider)

    assert result.completed?
    assert result.answer == "awaited async summary"

    record = hd(result.iteration_records)
    assert record.status == :recovered
    assert record.recovery_kind == :async_wrapper
    assert record.error_kind == nil
    assert record.details["compile_stage"] == "async_wrapper"
  end

  test "runs async_llm_query calls in parallel with asyncio gather" do
    settings = TestHelpers.settings(%{max_iterations: 2, max_sub_queries: 4})
    bundle = %{entries: [], text: "abcdef", bytes: 6}
    started_at = System.monotonic_time(:millisecond)

    assert {:ok, result} =
             Engine.run("summarize", bundle, settings, Rlm.TestParallelAsyncProvider)

    elapsed = System.monotonic_time(:millisecond) - started_at

    assert result.completed?
    assert result.answer == "left summary | right summary"
    assert result.total_sub_queries == 2
    assert elapsed < 450
  end

  test "recovers an unterminated triple-quoted FINAL body" do
    settings = TestHelpers.settings(%{max_iterations: 1})
    bundle = %{entries: [], text: "abcdef", bytes: 6}

    assert {:ok, result} =
             Engine.run("summarize", bundle, settings, Rlm.TestUnterminatedFinalProvider)

    assert result.completed?

    assert result.answer ==
             "Recovered final answer from malformed output\n\n- kept the markdown body"

    record = hd(result.iteration_records)
    assert record.has_final
    assert record.final_value == result.answer
    assert record.stderr == ""
    assert record.status == :recovered
    assert record.error_kind == :syntax_unterminated_triple_quote
    assert record.recovery_kind == :salvaged_unterminated_final
    assert record.details["compile_stage"] == "direct"
  end

  test "returns the best partial answer instead of a raw internal error" do
    settings = TestHelpers.settings(%{max_iterations: 3, max_sub_queries: 3})
    bundle = %{entries: [], text: "abcdef", bytes: 6}

    assert {:ok, result} = Engine.run("summarize", bundle, settings, Rlm.PartialThenErrorProvider)
    refute result.completed?
    assert result.status == :provider_timeout
    assert result.answer =~ "Recovered summary from partial work"
    assert result.answer =~ "best partial answer available"
    assert result.answer =~ "provider timed out"
    assert result.best_answer_reason == :stdout
    assert Enum.any?(result.failure_history, &(&1.class == :provider_timeout))
  end

  test "routes sub-query failures to stderr instead of normal response text" do
    settings = TestHelpers.settings(%{max_iterations: 1, max_sub_queries: 3})
    bundle = %{entries: [], text: "abcdef", bytes: 6}

    assert {:ok, result} =
             Engine.run("summarize", bundle, settings, Rlm.TestSubqueryErrorProvider)

    assert result.status == :provider_timeout
    refute result.completed?

    record = hd(result.iteration_records)
    assert record.stdout == ""
    assert record.stderr =~ "SubqueryError"
    assert record.stderr =~ "%Req.TransportError{reason: :timeout}"
    refute record.stderr =~ "Unexpected sub-query result"
  end

  test "uses one recovery iteration with stricter policy after a sub-query timeout" do
    settings = TestHelpers.settings(%{max_iterations: 2, max_sub_queries: 3})
    bundle = %{entries: [], text: "abcdef", bytes: 6}

    assert {:ok, result} = Engine.run("summarize", bundle, settings, Rlm.TestRecoveringProvider)
    assert result.completed?
    assert result.answer == "Recovered via a simpler direct answer"
    assert result.recovery_flags.recovery_mode
    assert result.recovery_flags.broad_subqueries_disabled
    assert Enum.any?(result.failure_history, &(&1.class == :provider_timeout))
    assert result.iterations == 2
  end
end
