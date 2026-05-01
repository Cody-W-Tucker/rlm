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
            "search_count" => 6,
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

  test "rejects answer that echoes search scaffolding without read support" do
    bundle = %{
      lazy_entries: [%{label: "/tmp/a.md"}, %{label: "/tmp/b.md"}, %{label: "/tmp/c.md"}]
    }

    records = [
      %{
        details: %{
          "evidence" => %{
            "search_count" => 3,
            "search_patterns" => [
              "\\bplan\\b|\\bplanning\\b",
              "\\bscope\\b|\\bscoping\\b",
              "\\bstrategy\\b|\\bapproach\\b",
              "\\bdecompose\\b|\\bbreakdown\\b"
            ],
            "hit_paths" => ["/tmp/a.md"],
            "read_files" => ["/tmp/a.md", "/tmp/b.md", "/tmp/c.md"],
            "read_windows" => ["/tmp/a.md:20:5"],
            "read_followups" => [
              %{
                "path" => "/tmp/a.md",
                "line" => 20,
                "pattern" => "start with|first",
                "query_kind" => "behavioral",
                "text" => "start with the narrow example"
              }
            ]
          }
        }
      }
    ]

    assert {:error, message} =
             Policy.validate_final_answer(
               bundle,
               "The user uses planning and scoping with a strategy of decomposing tasks into a breakdown.",
               hd(records).details,
               records
             )

    assert message =~ "search scaffolding"
  end

  test "allows answer when search phrases are backed by read followups" do
    bundle = %{
      lazy_entries: [%{label: "/tmp/a.md"}, %{label: "/tmp/b.md"}, %{label: "/tmp/c.md"}]
    }

    records = [
      %{
        details: %{
          "evidence" => %{
            "search_count" => 3,
            "search_patterns" => [
              "\\bplan\\b|\\bplanning\\b",
              "\\bscope\\b|\\bscoping\\b",
              "\\bstrategy\\b"
            ],
            "hit_paths" => ["/tmp/a.md"],
            "read_files" => ["/tmp/a.md", "/tmp/b.md", "/tmp/c.md"],
            "read_windows" => ["/tmp/a.md:20:5"],
            "read_followups" => [
              %{
                "path" => "/tmp/a.md",
                "line" => 20,
                "pattern" => "plan|scope",
                "query_kind" => "behavioral",
                "text" => "make a plan to scope the work before starting"
              },
              %{
                "path" => "/tmp/b.md",
                "line" => 10,
                "pattern" => "strategy",
                "query_kind" => "behavioral",
                "text" => "the strategy is to build incrementally"
              }
            ]
          }
        }
      }
    ]

    assert :ok =
             Policy.validate_final_answer(
               bundle,
               "The user makes a plan to scope work, following a strategy of building incrementally.",
               hd(records).details,
               records
             )
  end

  test "allows answer with common words even when they appeared in search patterns" do
    bundle = %{
      lazy_entries: [%{label: "/tmp/a.md"}, %{label: "/tmp/b.md"}, %{label: "/tmp/c.md"}]
    }

    records = [
      %{
        details: %{
          "evidence" => %{
            "search_count" => 2,
            "search_patterns" => [
              "\\bfirst\\b|\\bthen\\b"
            ],
            "hit_paths" => ["/tmp/a.md"],
            "read_files" => ["/tmp/a.md", "/tmp/b.md", "/tmp/c.md"],
            "read_windows" => ["/tmp/a.md:20:5"],
            "read_followups" => [
              %{
                "path" => "/tmp/a.md",
                "line" => 20,
                "pattern" => "first|then",
                "query_kind" => "behavioral",
                "text" => "first review, then execute"
              }
            ]
          }
        }
      }
    ]

    assert :ok =
             Policy.validate_final_answer(
               bundle,
               "The user iteratively refines their approach, first reviewing then executing.",
               hd(records).details,
               records
             )
  end

  test "ignores low-signal probe terms when checking search scaffolding echoes" do
    bundle = %{
      lazy_entries: [%{label: "/tmp/a.md"}, %{label: "/tmp/b.md"}, %{label: "/tmp/c.md"}]
    }

    records = [
      %{
        details: %{
          "evidence" => %{
            "search_count" => 3,
            "search_patterns" => [
              "\\bdecision\\b|\\bprefer\\b|\\bviable\\b|\\bpath\\b",
              "\\bfirst\\b|\\binspect\\b|\\bread\\b"
            ],
            "hit_paths" => ["/tmp/a.md"],
            "read_files" => ["/tmp/a.md", "/tmp/b.md", "/tmp/c.md"],
            "read_windows" => ["/tmp/a.md:20:5"],
            "read_followups" => [
              %{
                "path" => "/tmp/a.md",
                "line" => 20,
                "pattern" => "start with|first",
                "query_kind" => "behavioral",
                "text" => "start with the narrow example"
              }
            ]
          }
        }
      }
    ]

    assert :ok =
             Policy.validate_final_answer(
               bundle,
               "The user inspects a small sample first, then reads more when a viable path emerges.",
               hd(records).details,
               records
             )
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
