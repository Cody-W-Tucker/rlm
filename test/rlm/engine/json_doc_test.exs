defmodule Rlm.Engine.JsonDocTest do
  use ExUnit.Case, async: false

  alias Rlm.Context.Loader
  alias Rlm.Engine
  alias Rlm.TestHelpers

  test "json helpers support schema sampling, path-aware search, and targeted object reads" do
    tmp = TestHelpers.temp_dir("rlm-engine-json-doc")
    on_exit(fn -> File.rm_rf!(tmp) end)

    payload = %{
      "people" => [
        %{
          "slug" => "people/alice",
          "title" => "Alice",
          "mentions" => [
            %{
              "slug" => "notes/q2-retro",
              "matched_lines" => [
                %{"line_number" => 14, "text" => "Alice flagged scope risk early."}
              ]
            }
          ]
        }
      ],
      "concepts" => [
        %{"slug" => "concepts/trust-building", "title" => "Trust Building", "mentions" => []}
      ]
    }

    path = Path.join(tmp, "graph.json")
    File.write!(path, Jason.encode!(payload))
    settings = TestHelpers.settings(%{max_iterations: 1})

    assert {:ok, bundle} = Loader.load({:path, path}, settings)

    assert {:ok, result} =
             Engine.run("inspect json exports", bundle, settings, Rlm.TestJsonDocProvider)

    assert result.completed?
    assert result.answer =~ "people[0].mentions[0].matched_lines[0].text"
    assert result.answer =~ "scope risk"

    stdout = hd(result.iteration_records).stdout
    assert stdout =~ "top_level_keys"
    assert stdout =~ "people[0].mentions[0].matched_lines[0].text"
    assert stdout =~ "Alice flagged scope risk early."
  end
end
