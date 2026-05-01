defmodule Rlm.Engine.FileAccessTest do
  use ExUnit.Case, async: false

  alias Rlm.Context.Loader
  alias Rlm.Engine
  alias Rlm.EngineTestSupport
  alias Rlm.TestHelpers

  test "exposes lazy file access tools in the repl" do
    tmp = TestHelpers.temp_dir("rlm-engine-files")
    on_exit(fn -> File.rm_rf!(tmp) end)

    File.write!(Path.join(tmp, "note.txt"), "alpha\nbeta\n")
    settings = TestHelpers.settings(%{max_iterations: 1})

    assert {:ok, bundle} = Loader.load({:path, Path.join(tmp, "note.txt")}, settings)
    assert {:ok, result} = Engine.run("summarize", bundle, settings, Rlm.TestFileAccessProvider)

    assert result.completed?
    assert result.answer == "1: alpha\n2: beta"
    assert hd(result.iteration_records).stdout =~ "note.txt"
  end

  test "tracks structured evidence from searches, previews, and reads" do
    tmp = TestHelpers.temp_dir("rlm-engine-evidence")
    on_exit(fn -> File.rm_rf!(tmp) end)

    EngineTestSupport.build_fixture_corpus(tmp)
    settings = TestHelpers.settings(%{max_iterations: 1})

    assert {:ok, bundle} = Loader.load({:path, tmp}, settings)

    assert {:ok, result} =
             Engine.run("summarize", bundle, settings, Rlm.TestEvidenceTrackingProvider)

    assert result.completed?
    assert result.grounding.grade == "A"
    assert result.grounding.level == :read_backed_multi

    evidence = get_in(hd(result.iteration_records), [:details, "evidence"])
    assert evidence["search_count"] >= 1
    assert length(evidence["previewed_files"]) >= 1
    assert length(evidence["read_files"]) >= 3
    assert length(evidence["read_windows"]) >= 3
    assert length(evidence["hit_paths"]) >= 1
  end

  test "tracks search provenance and hit-followup reads" do
    tmp = TestHelpers.temp_dir("rlm-engine-followup-evidence")
    on_exit(fn -> File.rm_rf!(tmp) end)

    File.write!(
      Path.join(tmp, "notes.txt"),
      "start with a narrow example\nthen verify the surrounding context\nhowever sometimes the user asks for broader exploration\n"
    )

    settings = TestHelpers.settings(%{max_iterations: 1})

    assert {:ok, bundle} = Loader.load({:path, Path.join(tmp, "notes.txt")}, settings)

    assert {:ok, result} =
             Engine.run(
               "inspect retrieval provenance",
               bundle,
               settings,
               Rlm.TestFollowupEvidenceProvider
             )

    assert result.completed?

    evidence = get_in(hd(result.iteration_records), [:details, "evidence"])
    assert Enum.any?(evidence["search_queries"], &(&1["kind"] == "expected_support"))
    assert Enum.any?(evidence["search_queries"], &(&1["kind"] == "counterexample"))
    assert Enum.any?(evidence["read_followups"], &(&1["query_kind"] == "expected_support"))
    assert Enum.any?(evidence["read_followups"], &(&1["query_kind"] == "counterexample"))
  end

  test "grep_files returns reusable hit objects" do
    tmp = TestHelpers.temp_dir("rlm-engine-grep")
    on_exit(fn -> File.rm_rf!(tmp) end)

    File.write!(Path.join(tmp, "note.txt"), "alpha\nbeta\n")
    settings = TestHelpers.settings(%{max_iterations: 1})

    assert {:ok, bundle} = Loader.load({:path, Path.join(tmp, "note.txt")}, settings)

    assert {:ok, result} =
             Engine.run("find beta", bundle, settings, Rlm.TestGrepFileAccessProvider)

    assert result.completed?
    assert result.answer =~ "note.txt"

    stdout = hd(result.iteration_records).stdout
    assert stdout =~ "note.txt:2: beta"
    assert stdout =~ "note.txt"
    assert stdout =~ "2"
    assert stdout =~ "beta"
  end

  test "grep_files tolerates tuple-style hit indexing used by the model" do
    tmp = TestHelpers.temp_dir("rlm-engine-grep-tuple")
    on_exit(fn -> File.rm_rf!(tmp) end)

    File.write!(Path.join(tmp, "note.txt"), "alpha\nbeta\n")
    settings = TestHelpers.settings(%{max_iterations: 1})

    assert {:ok, bundle} = Loader.load({:path, Path.join(tmp, "note.txt")}, settings)

    assert {:ok, result} =
             Engine.run("find beta", bundle, settings, Rlm.TestGrepTupleCompatibilityProvider)

    assert result.completed?
    assert result.answer =~ "note.txt:2"

    stdout = hd(result.iteration_records).stdout
    assert stdout =~ "note.txt"
    assert stdout =~ "2"
    assert stdout =~ "beta"
  end

  test "grep_open returns preview-ready hit objects" do
    tmp = TestHelpers.temp_dir("rlm-engine-grep-open")
    on_exit(fn -> File.rm_rf!(tmp) end)

    File.write!(Path.join(tmp, "note.txt"), "alpha\nbeta\ngamma\n")
    settings = TestHelpers.settings(%{max_iterations: 1})

    assert {:ok, bundle} = Loader.load({:path, Path.join(tmp, "note.txt")}, settings)

    assert {:ok, result} =
             Engine.run("find beta", bundle, settings, Rlm.TestGrepOpenProvider)

    assert result.completed?
    assert result.grounding.grade == "C"
    assert result.grounding.level == :scout_only
    assert result.answer =~ "1: alpha"
    assert result.answer =~ "2: beta"
    assert result.answer =~ "3: gamma"

    stdout = hd(result.iteration_records).stdout
    assert stdout =~ "note.txt:2: beta"
    assert stdout =~ "1: alpha"
  end

  test "grep_files supports path-scoped searches" do
    tmp = TestHelpers.temp_dir("rlm-engine-grep-scoped")
    on_exit(fn -> File.rm_rf!(tmp) end)

    File.write!(Path.join(tmp, "alpha.txt"), "alpha\n")
    File.write!(Path.join(tmp, "beta.txt"), "beta\n")
    File.write!(Path.join(tmp, "gamma.txt"), "gamma\n")
    settings = TestHelpers.settings(%{max_iterations: 1})

    assert {:ok, bundle} = Loader.load({:path, tmp}, settings)

    assert {:ok, result} =
             Engine.run("find beta", bundle, settings, Rlm.TestGrepScopedPathProvider)

    assert result.completed?
    assert result.answer =~ "1:"
    assert result.answer =~ "beta.txt"
    assert result.answer =~ ":1"
  end

  test "peek_hit and open_hit support direct hit follow-up" do
    tmp = TestHelpers.temp_dir("rlm-engine-hit-followup")
    on_exit(fn -> File.rm_rf!(tmp) end)

    File.write!(Path.join(tmp, "note.txt"), "alpha\nbeta\ngamma\n")
    settings = TestHelpers.settings(%{max_iterations: 1})

    assert {:ok, bundle} = Loader.load({:path, Path.join(tmp, "note.txt")}, settings)

    assert {:ok, result} =
             Engine.run("find beta", bundle, settings, Rlm.TestHitFollowupProvider)

    assert result.completed?
    assert result.answer =~ "1: alpha"
    assert result.answer =~ "2: beta"
    assert result.answer =~ "3: gamma"
  end

  test "sample_files and peek_file support file-shape scouting" do
    tmp = TestHelpers.temp_dir("rlm-engine-shape")
    on_exit(fn -> File.rm_rf!(tmp) end)

    File.write!(Path.join(tmp, "a.txt"), "alpha\nline2\n")
    File.write!(Path.join(tmp, "b.txt"), "beta\nline2\n")
    settings = TestHelpers.settings(%{max_iterations: 1})

    assert {:ok, bundle} = Loader.load({:path, tmp}, settings)

    assert {:ok, result} =
             Engine.run("inspect shape", bundle, settings, Rlm.TestFileShapeProvider)

    assert result.completed?
    assert result.answer == "1: alpha"

    stdout = hd(result.iteration_records).stdout
    assert stdout =~ "a.txt"
    assert stdout =~ "b.txt"
    assert stdout =~ "1: alpha"
  end

  test "read_file and peek_file support large late-file windows without whole-file access assumptions" do
    tmp = TestHelpers.temp_dir("rlm-engine-large-window")
    on_exit(fn -> File.rm_rf!(tmp) end)

    lines =
      Enum.map_join(1..1_000, "\n", fn index -> Jason.encode!(%{"row" => index}) end) <> "\n"

    File.write!(Path.join(tmp, "events.jsonl"), lines)
    settings = TestHelpers.settings(%{max_iterations: 1})

    assert {:ok, bundle} = Loader.load({:path, Path.join(tmp, "events.jsonl")}, settings)

    assert {:ok, result} =
             Engine.run(
               "inspect tail window",
               bundle,
               settings,
               Rlm.TestLargeOffsetFileAccessProvider
             )

    assert result.completed?
    assert result.answer == "999: {\"row\":999}\n1000: {\"row\":1000}"

    stdout = hd(result.iteration_records).stdout
    assert stdout =~ "995: {\"row\":995}"
    assert stdout =~ "997: {\"row\":997}"
  end
end
