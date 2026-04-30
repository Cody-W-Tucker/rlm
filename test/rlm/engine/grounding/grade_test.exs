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
    assert %{grade: "A", level: :read_backed_multi, semantic: %{grade: "D"}} =
             Grade.assess(bundle, strong_read_backed)
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

  test "semantic grounding improves when reads follow matched passages and contradictions" do
    bundle = %{lazy_entries: [%{label: "/tmp/history.jsonl"}]}

    records = [
      %{
        details: %{
          "evidence" => %{
            "search_count" => 3,
            "search_queries" => [
              %{"id" => 1, "kind" => "behavioral", "pattern" => "start with", "source" => "grep_files"},
              %{"id" => 2, "kind" => "contradiction", "pattern" => "however", "source" => "grep_files"}
            ],
            "hit_paths" => ["/tmp/history.jsonl"],
            "read_files" => ["/tmp/history.jsonl"],
            "read_windows" => ["/tmp/history.jsonl:10:2", "/tmp/history.jsonl:20:1", "/tmp/history.jsonl:30:1"],
            "read_followups" => [
              %{"path" => "/tmp/history.jsonl", "line" => 10, "pattern" => "start with", "query_kind" => "behavioral", "text" => "start with a narrow example"},
              %{"path" => "/tmp/history.jsonl", "line" => 20, "pattern" => "however", "query_kind" => "contradiction", "text" => "however sometimes the scope expands"}
            ]
          }
        }
      }
    ]

    assert %{semantic: %{grade: "A", level: :verified_with_challenge}} =
             Grade.assess(bundle, records)
  end
end
