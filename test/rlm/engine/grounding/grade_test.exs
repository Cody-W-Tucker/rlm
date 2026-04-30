defmodule Rlm.Engine.Grounding.GradeTest do
  use ExUnit.Case, async: true

  alias Rlm.Engine.Grounding.Grade

  test "requires three reads for top grounding grade" do
    bundle = %{lazy_entries: [%{label: "/tmp/note.md"}]}

    scout_only = [
      %{
        details: %{
          "evidence" => %{
            "search_count" => 2,
            "hit_paths" => ["/tmp/note.md"],
            "previewed_files" => ["/tmp/note.md"],
            "read_files" => []
          }
        }
      }
    ]

    read_backed = [
      %{
        details: %{
          "evidence" => %{
            "search_count" => 2,
            "hit_paths" => ["/tmp/note.md", "/tmp/other.md"],
            "previewed_files" => ["/tmp/note.md"],
            "read_files" => ["/tmp/note.md", "/tmp/other.md"]
          }
        }
      }
    ]

    strong_read_backed = [
      %{
        details: %{
          "evidence" => %{
            "search_count" => 2,
            "hit_paths" => ["/tmp/note.md", "/tmp/other.md", "/tmp/third.md"],
            "previewed_files" => ["/tmp/note.md", "/tmp/other.md"],
            "read_files" => ["/tmp/note.md", "/tmp/other.md", "/tmp/third.md"]
          }
        }
      }
    ]

    assert %{grade: "C", level: :scout_only} = Grade.assess(bundle, scout_only)
    assert %{grade: "B", level: :read_backed} = Grade.assess(bundle, read_backed)
    assert %{grade: "A", level: :read_backed_multi} = Grade.assess(bundle, strong_read_backed)
  end

  test "returns nil for non file-backed runs" do
    assert Grade.assess(%{lazy_entries: []}, []) == nil
  end

  test "counts targeted windows for single line-delimited sources" do
    bundle = %{lazy_entries: [%{label: "/tmp/history.jsonl"}]}

    records = [
      %{
        details: %{
          "evidence" => %{
            "search_count" => 3,
            "hit_paths" => ["/tmp/history.jsonl"],
            "previewed_files" => [],
            "read_files" => ["/tmp/history.jsonl"],
            "read_windows" => [
              "/tmp/history.jsonl:1:1",
              "/tmp/history.jsonl:7:1",
              "/tmp/history.jsonl:12:1"
            ]
          }
        }
      }
    ]

    assert %{grade: "A", level: :read_backed_multi, metrics: %{read_windows: 3}} =
             Grade.assess(bundle, records)
  end
end
