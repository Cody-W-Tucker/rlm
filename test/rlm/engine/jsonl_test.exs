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
        %{"messages" => [%{"role" => "user", "content" => "please review this change"}], "source" => "cursor"},
        %{"messages" => [%{"role" => "user", "content" => "I prefer async def with await and asyncio.gather"}], "source" => "cursor"},
        %{"messages" => [%{"role" => "user", "content" => "use Semaphore to cap concurrency"}], "source" => "cursor"}
      ]
      |> Enum.map_join("\n", &Jason.encode!/1)
      |> Kernel.<>("\n")

    File.write!(Path.join(tmp, "history.jsonl"), lines)
    settings = TestHelpers.settings(%{max_iterations: 1})

    assert {:ok, bundle} = Loader.load({:path, Path.join(tmp, "history.jsonl")}, settings)

    assert {:ok, result} =
             Engine.run("extract coding style evidence", bundle, settings, Rlm.TestJsonlRetrievalProvider)

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
        %{"messages" => [%{"role" => "user", "content" => "plain request"}], "source" => "cursor"},
        %{"messages" => [%{"role" => "user", "content" => "I prefer async def with await"}], "source" => "cursor"}
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
end
