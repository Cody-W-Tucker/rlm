defmodule Rlm.Engine.Grounding.PolicyTest do
  use ExUnit.Case, async: true

  alias Rlm.Engine.Grounding.Policy

  test "search progress no longer blocks continuation" do
    bundle = %{
      lazy_entries: [%{label: "/tmp/a.md"}, %{label: "/tmp/b.md"}, %{label: "/tmp/c.md"}]
    }

    records = [
      %{
        details: %{
          "evidence" => %{
            "search_count" => 3,
            "hit_paths" => ["/tmp/a.md"],
            "read_files" => ["/tmp/a.md", "/tmp/b.md", "/tmp/c.md"],
            "read_windows" => ["/tmp/a.md:1:100", "/tmp/b.md:1:100", "/tmp/c.md:1:100"],
            "read_followups" => []
          }
        }
      }
    ]

    assert :ok = Policy.validate_search_progress(bundle, records)
  end

  test "search progress blocks repeated scouting with too few promoted reads" do
    bundle = %{
      lazy_entries: [%{label: "/tmp/a.md"}, %{label: "/tmp/b.md"}, %{label: "/tmp/c.md"}]
    }

    records = [
      %{
        details: %{
          "evidence" => %{
            "search_count" => 3,
            "hit_paths" => ["/tmp/a.md"],
            "read_files" => ["/tmp/a.md"],
            "read_windows" => ["/tmp/a.md:1:20"],
            "read_followups" => []
          }
        }
      }
    ]

    assert {:error, message} = Policy.validate_search_progress(bundle, records)
    assert message =~ "Stop expanding the search space"
    assert message =~ "promote at least 3 strongest hits"
  end

  test "validate_final_answer still rejects generic file-start reads" do
    bundle = %{
      lazy_entries: [%{label: "/tmp/a.md"}, %{label: "/tmp/b.md"}, %{label: "/tmp/c.md"}]
    }

    records = [
      %{
        details: %{
          "evidence" => %{
            "search_count" => 3,
            "hit_paths" => ["/tmp/a.md"],
            "read_files" => ["/tmp/a.md", "/tmp/b.md", "/tmp/c.md"],
            "read_windows" => ["/tmp/a.md:1:100", "/tmp/b.md:1:100", "/tmp/c.md:1:100"],
            "read_followups" => []
          }
        }
      }
    ]

    assert {:error, message} =
             Policy.validate_final_answer(
               bundle,
               "The user does X.",
               hd(records).details,
               records
             )

    assert message =~ "generic file-start reads"
  end

  test "allows multi-file line-delimited runs with window-backed followup evidence" do
    bundle = %{
      lazy_entries: [
        %{label: "/tmp/a.jsonl"},
        %{label: "/tmp/b.jsonl"},
        %{label: "/tmp/c.jsonl"}
      ]
    }

    records = [
      %{
        details: %{
          "evidence" => %{
            "search_count" => 4,
            "search_queries" => [
              %{
                "id" => 1,
                "kind" => "behavioral",
                "pattern" => "start with",
                "source" => "grep_jsonl_fields"
              }
            ],
            "hit_paths" => ["/tmp/a.jsonl"],
            "previewed_files" => ["/tmp/a.jsonl", "/tmp/b.jsonl", "/tmp/c.jsonl"],
            "read_files" => ["/tmp/a.jsonl"],
            "read_windows" => [
              "/tmp/a.jsonl:10:1",
              "/tmp/a.jsonl:20:1",
              "/tmp/a.jsonl:30:1"
            ],
            "read_followups" => [
              %{
                "path" => "/tmp/a.jsonl",
                "line" => 10,
                "pattern" => "start with",
                "query_kind" => "behavioral",
                "text" => "start with a narrow example"
              }
            ]
          }
        }
      }
    ]

    assert :ok =
             Policy.validate_final_answer(
               bundle,
               "The user usually starts with a narrow example and builds outward.",
               hd(records).details,
               records
             )
  end

  test "still rejects multi-file line-delimited runs with only structural windows" do
    bundle = %{
      lazy_entries: [
        %{label: "/tmp/a.jsonl"},
        %{label: "/tmp/b.jsonl"},
        %{label: "/tmp/c.jsonl"}
      ]
    }

    records = [
      %{
        details: %{
          "evidence" => %{
            "search_count" => 4,
            "hit_paths" => ["/tmp/a.jsonl"],
            "previewed_files" => ["/tmp/a.jsonl", "/tmp/b.jsonl", "/tmp/c.jsonl"],
            "read_files" => ["/tmp/a.jsonl"],
            "read_windows" => [
              "/tmp/a.jsonl:10:1",
              "/tmp/a.jsonl:20:1",
              "/tmp/a.jsonl:30:1"
            ],
            "read_followups" => []
          }
        }
      }
    ]

    assert {:error, message} =
             Policy.validate_final_answer(
               bundle,
               "The user usually starts with a narrow example and builds outward.",
               hd(records).details,
               records
             )

    assert message =~ "multi-file line-delimited final answer"
    assert message =~ "hit-followup read"
  end
end
