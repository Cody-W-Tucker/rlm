defmodule Rlm.Engine.Grounding.PolicyTest do
  use ExUnit.Case, async: true

  alias Rlm.Engine.Grounding.Policy

  test "rejects repeated search with generic file-start reads" do
    bundle = %{lazy_entries: [%{label: "/tmp/a.md"}, %{label: "/tmp/b.md"}, %{label: "/tmp/c.md"}]}

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

    assert {:error, message} = Policy.validate_search_progress(bundle, records)
    assert message =~ "generic file-start reads"
  end

  test "rejects unsupported abstract labels without followed evidence" do
    bundle = %{lazy_entries: [%{label: "/tmp/a.md"}, %{label: "/tmp/b.md"}, %{label: "/tmp/c.md"}]}

    records = [
      %{
        details: %{
          "evidence" => %{
            "search_count" => 1,
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
               "The user follows an iterative MVP strategy.",
               hd(records).details,
               records
             )

    assert message =~ "unsupported abstract labels"
    assert message =~ "iterative"
    assert message =~ "mvp"
  end

  test "allows abstract labels when followed passages support them directly" do
    bundle = %{lazy_entries: [%{label: "/tmp/a.md"}, %{label: "/tmp/b.md"}, %{label: "/tmp/c.md"}]}

    records = [
      %{
        details: %{
          "evidence" => %{
            "search_count" => 1,
            "hit_paths" => ["/tmp/a.md"],
            "read_files" => ["/tmp/a.md", "/tmp/b.md", "/tmp/c.md"],
            "read_windows" => ["/tmp/a.md:20:5"],
            "read_followups" => [
              %{
                "path" => "/tmp/a.md",
                "line" => 20,
                "pattern" => "MVP|minimum viable",
                "query_kind" => "theory_loaded",
                "text" => "we should build an MVP first and keep the slice narrow"
              }
            ]
          }
        }
      }
    ]

    assert :ok =
             Policy.validate_final_answer(
               bundle,
               "The user explicitly asks for an MVP first.",
               hd(records).details,
               records
             )
  end
end
