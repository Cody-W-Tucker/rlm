defmodule Rlm.Engine.JsonlTest do
  use ExUnit.Case, async: false

  alias Rlm.Context.Loader
  alias Rlm.Engine
  alias Rlm.TestHelpers

  test "jsonl helpers support schema sampling, field-aware search, and targeted record reads" do
    tmp = TestHelpers.temp_dir("rlm-engine-jsonl-helpers")
    on_exit(fn -> File.rm_rf!(tmp) end)

    lines =
      [
        %{
          "messages" => [%{"role" => "user", "content" => "please review this change"}],
          "source" => "cursor"
        },
        %{
          "messages" => [
            %{"role" => "user", "content" => "I prefer async def with await and asyncio.gather"}
          ],
          "source" => "cursor"
        },
        %{
          "messages" => [%{"role" => "user", "content" => "use Semaphore to cap concurrency"}],
          "source" => "cursor"
        }
      ]
      |> Enum.map_join("\n", &Jason.encode!/1)
      |> Kernel.<>("\n")

    File.write!(Path.join(tmp, "history.jsonl"), lines)
    settings = TestHelpers.settings(%{max_iterations: 1})

    assert {:ok, bundle} = Loader.load({:path, Path.join(tmp, "history.jsonl")}, settings)

    assert {:ok, result} =
             Engine.run(
               "extract coding style evidence",
               bundle,
               settings,
               Rlm.TestJsonlRetrievalProvider
             )

    assert result.completed?
    assert result.answer =~ "messages[0].content"
    assert result.answer =~ "async"

    stdout = hd(result.iteration_records).stdout
    assert stdout =~ "'record'"
    assert stdout =~ "messages[0].content"
    assert stdout =~ "Semaphore"
  end

  test "jsonl helpers tolerate dict-style access patterns used by the model" do
    tmp = TestHelpers.temp_dir("rlm-engine-jsonl-compat")
    on_exit(fn -> File.rm_rf!(tmp) end)

    lines =
      [
        %{
          "messages" => [%{"role" => "user", "content" => "plain request"}],
          "source" => "cursor"
        },
        %{
          "messages" => [%{"role" => "user", "content" => "I prefer async def with await"}],
          "source" => "cursor"
        }
      ]
      |> Enum.map_join("\n", &Jason.encode!/1)
      |> Kernel.<>("\n")

    File.write!(Path.join(tmp, "history.jsonl"), lines)
    settings = TestHelpers.settings(%{max_iterations: 1})

    assert {:ok, bundle} = Loader.load({:path, Path.join(tmp, "history.jsonl")}, settings)

    assert {:ok, result} =
             Engine.run("compat access", bundle, settings, Rlm.TestJsonlCompatibilityProvider)

    assert result.completed?
    assert result.answer == "2"

    stdout = hd(result.iteration_records).stdout
    assert stdout =~ "history.jsonl"
    assert stdout =~ "messages[0].content"
    assert stdout =~ "async def with await"
  end

  test "repeated JSONL search must promote hits into targeted read windows" do
    tmp = TestHelpers.temp_dir("rlm-engine-jsonl-promotion")
    on_exit(fn -> File.rm_rf!(tmp) end)

    lines =
      [
        %{"messages" => [%{"role" => "user", "content" => "alpha decision evidence"}]},
        %{"messages" => [%{"role" => "user", "content" => "beta learning evidence"}]},
        %{"messages" => [%{"role" => "user", "content" => "gamma adaptation evidence"}]}
      ]
      |> Enum.map_join("\n", &Jason.encode!/1)
      |> Kernel.<>("\n")

    File.write!(Path.join(tmp, "history.jsonl"), lines)
    settings = TestHelpers.settings(%{max_iterations: 2})

    assert {:ok, bundle} = Loader.load({:path, Path.join(tmp, "history.jsonl")}, settings)

    assert {:ok, result} =
             Engine.run(
               "extract grounded profile evidence",
               bundle,
               settings,
               Rlm.TestJsonlSearchPromotionProvider
             )

    assert result.completed?
    assert result.answer == "Recovered from promoted JSONL windows"
    assert result.iterations == 2
    assert result.grounding.grade == "A"
    assert result.grounding.metrics.read_windows >= 3

    [first, second] = result.iteration_records
    refute first.has_final
    assert is_nil(first.final_value)
    assert get_in(first, [:details, "evidence", "search_count"]) == 3
    assert get_in(first, [:details, "evidence", "read_windows"]) == []
    assert length(get_in(second, [:details, "evidence", "read_windows"])) >= 3
  end

  test "assess_evidence recommends the next convergence step" do
    tmp = TestHelpers.temp_dir("rlm-engine-jsonl-assess-evidence")
    on_exit(fn -> File.rm_rf!(tmp) end)

    lines =
      [
        %{"messages" => [%{"role" => "user", "content" => "start with the smallest version first"}]},
        %{"messages" => [%{"role" => "user", "content" => "however, sometimes a direct answer is enough"}]},
        %{"messages" => [%{"role" => "user", "content" => "scope the problem before adding more steps"}]}
      ]
      |> Enum.map_join("\n", &Jason.encode!/1)
      |> Kernel.<>("\n")

    File.write!(Path.join(tmp, "history.jsonl"), lines)
    settings = TestHelpers.settings(%{max_iterations: 1})

    assert {:ok, bundle} = Loader.load({:path, Path.join(tmp, "history.jsonl")}, settings)

    assert {:ok, result} =
             Engine.run(
               "assess convergence state",
               bundle,
               settings,
               Rlm.TestAssessEvidenceProvider
             )

    assert result.completed?
    assert result.answer == "run_contradiction_search|0"

    stdout = hd(result.iteration_records).stdout
    assert stdout =~ "support_summary"
    assert stdout =~ "suggested_reads"
    assert stdout =~ "next_action"
  end
end
