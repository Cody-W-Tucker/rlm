defmodule Rlm.Engine.FixtureRecoveryTest do
  use ExUnit.Case, async: false

  alias Rlm.Context.Loader
  alias Rlm.Engine
  alias Rlm.EngineTestSupport
  alias Rlm.TestHelpers

  defp put_fixture_response(text) do
    Application.put_env(:rlm, :test_fixture_response, text)

    on_exit(fn ->
      Application.delete_env(:rlm, :test_fixture_response)
      Application.delete_env(:rlm, :test_fixture_recovery_response)
      Application.delete_env(:rlm, :test_fixture_subquery_handler)
    end)
  end

  defp put_fixture_recovery_response(text) do
    Application.put_env(:rlm, :test_fixture_recovery_response, text)
  end

  test "executes staged multi-block fixture responses seen in the wild" do
    tmp = TestHelpers.temp_dir("rlm-engine-fixture-staged")
    on_exit(fn -> File.rm_rf!(tmp) end)
    EngineTestSupport.build_fixture_corpus(tmp)

    put_fixture_response(EngineTestSupport.fixture_response("wild_staged_plan.txt", [{"__ROOT__", tmp}]))

    Application.put_env(:rlm, :test_fixture_subquery_handler, fn sub_context,
                                                                 _instruction,
                                                                 _settings ->
      title =
        cond do
          String.contains?(sub_context, "Aimlessness") -> "aimlessness summary"
          String.contains?(sub_context, "Sexual Urges") -> "sexual urges summary"
          String.contains?(sub_context, "Belief Construction") -> "belief summary"
          true -> "fixture summary"
        end

      {:ok, %{text: title, input_tokens: 0, output_tokens: 0}}
    end)

    settings = TestHelpers.settings(%{max_iterations: 1, max_sub_queries: 5})
    assert {:ok, bundle} = Loader.load({:path, tmp}, settings)

    assert {:ok, result} = Engine.run("summarize", bundle, settings, Rlm.TestFixtureProvider)

    assert result.completed?
    assert result.failure_history == []
    assert length(result.iteration_records) == 1
    assert result.total_sub_queries == 3
    assert result.answer =~ "aimlessness summary"
    assert result.answer =~ "sexual urges summary"
    assert result.answer =~ "belief summary"

    stdout = hd(result.iteration_records).stdout
    assert stdout =~ "=== Sampling files to understand corpus shape ==="
    assert stdout =~ "=== Searching for philosophical and identity concepts ==="
    assert stdout =~ "=== Loaded key files ==="
  end

  test "salvages malformed interleaved fixture responses from the wild" do
    tmp = TestHelpers.temp_dir("rlm-engine-fixture-malformed")
    on_exit(fn -> File.rm_rf!(tmp) end)
    EngineTestSupport.build_fixture_corpus(tmp)

    put_fixture_response(
      EngineTestSupport.fixture_response("malformed_interleaved_unclosed_tail.txt", [{"__ROOT__", tmp}])
    )

    settings = TestHelpers.settings(%{max_iterations: 1})
    assert {:ok, bundle} = Loader.load({:path, tmp}, settings)

    assert {:ok, result} = Engine.run("summarize", bundle, settings, Rlm.TestFixtureProvider)

    assert result.completed?
    assert result.failure_history == []
    assert length(result.iteration_records) == 1
    assert result.answer == "fixture recovered from malformed response"

    stdout = hd(result.iteration_records).stdout
    assert stdout =~ "=== Reading key file ==="
    assert stdout =~ "=== Searching related concepts ==="
  end

  test "recovery feedback includes failing block and python suggestion for later-block typos" do
    tmp = TestHelpers.temp_dir("rlm-engine-typo-recovery")
    on_exit(fn -> File.rm_rf!(tmp) end)
    EngineTestSupport.build_fixture_corpus(tmp)

    settings = TestHelpers.settings(%{max_iterations: 3})
    assert {:ok, bundle} = Loader.load({:path, tmp}, settings)

    assert {:ok, result} =
             Engine.run("summarize", bundle, settings, Rlm.TestMultiBlockTypoRecoveryProvider)

    assert result.completed?
    assert result.answer == "recovered after typo"
    assert length(result.failure_history) == 1

    failure = hd(result.failure_history)
    assert failure.class == :python_exec_error
    assert failure.message =~ "Failure occurred in block 2 of 2"
    assert failure.message =~ "print(contemporary_haits)"

    recovery_prompt = Enum.at(result.iteration_records, 0)
    assert recovery_prompt.stderr =~ "Did you mean: 'contemporary_hits'?"
  end

  test "fixture regression covers typo-driven multiblock runtime failure from the wild" do
    tmp = TestHelpers.temp_dir("rlm-engine-typo-fixture")
    on_exit(fn -> File.rm_rf!(tmp) end)
    EngineTestSupport.build_fixture_corpus(tmp)

    put_fixture_response(
      EngineTestSupport.fixture_response("typo_multiblock_runtime_error.txt", [{"__ROOT__", tmp}])
    )

    put_fixture_recovery_response("""
    ```python
    print("=== Recovery pass ===")
    contemporary_hits = grep_files("identity|meaning|Belief|belief|introspection", limit=10)
    targets = []
    for hit in contemporary_hits:
        if hit.path not in targets:
            targets.append(hit.path)
        if len(targets) == 3:
            break
    for target in targets:
        print(read_file(target, limit=5))
    print(contemporary_hits)
    FINAL("recovered from fixture typo")
    ```
    """)

    settings = TestHelpers.settings(%{max_iterations: 3})
    assert {:ok, bundle} = Loader.load({:path, tmp}, settings)

    assert {:ok, result} =
             Engine.run("summarize", bundle, settings, Rlm.TestRecoveryFixtureProvider)

    assert result.completed?
    assert result.answer == "recovered from fixture typo"
    assert length(result.failure_history) == 1

    failure = hd(result.failure_history)
    assert failure.message =~ "Failure occurred in block 6 of 6"
    assert failure.message =~ "print(contemporary_haits)"
    assert failure.message =~ "Did you mean: 'contemporary_hits'?"

    first_record = hd(result.iteration_records)
    assert first_record.stdout =~ "=== Sampling files to understand corpus shape ==="
    assert first_record.stdout =~ "=== Searching for philosophical concepts ==="
  end

  test "uses successful silent sub-query text as the best partial answer" do
    settings = TestHelpers.settings(%{max_iterations: 1, max_sub_queries: 2})
    bundle = %{entries: [], text: "abcdef", bytes: 6}

    assert {:ok, result} =
             Engine.run("summarize", bundle, settings, Rlm.TestSilentSubqueryProvider)

    assert result.status == :max_iterations
    refute result.completed?
    assert result.answer =~ "silent subquery answer"
    assert result.best_answer_reason == :subquery_success
    assert result.last_successful_subquery_result == "silent subquery answer"
  end

  test "recovers when final answer cites unread file paths" do
    tmp = TestHelpers.temp_dir("rlm-engine-grounding")
    on_exit(fn -> File.rm_rf!(tmp) end)

    EngineTestSupport.build_fixture_corpus(tmp)
    settings = TestHelpers.settings(%{max_iterations: 3})

    assert {:ok, bundle} = Loader.load({:path, tmp}, settings)

    assert {:ok, result} =
             Engine.run("summarize", bundle, settings, Rlm.TestUngroundedCitationRecoveryProvider)

    assert result.completed?
    assert result.answer =~ "Recovered with inspected evidence"
    assert length(result.failure_history) == 1

    failure = hd(result.failure_history)
    assert failure.class == :ungrounded_final_answer
    assert failure.message =~ "without inspecting them in this run"
    assert failure.message =~ "Aimlessness.md"
  end

  test "blocks scout-only finalization on multi-file file-backed runs" do
    tmp = TestHelpers.temp_dir("rlm-engine-grounding-grade")
    on_exit(fn -> File.rm_rf!(tmp) end)

    EngineTestSupport.build_fixture_corpus(tmp)
    settings = TestHelpers.settings(%{max_iterations: 3})

    assert {:ok, bundle} = Loader.load({:path, tmp}, settings)

    assert {:ok, result} =
             Engine.run(
               "summarize",
               bundle,
               settings,
               Rlm.TestInsufficientGroundingRecoveryProvider
             )

    assert result.completed?
    assert result.answer =~ "Recovered with 3-file read-backed grounding"
    assert result.grounding.grade == "A"
    assert length(result.failure_history) == 1

    failure = hd(result.failure_history)
    assert failure.class == :insufficient_grounding
    assert failure.message =~ "at least 3 relevant files"
  end
end
