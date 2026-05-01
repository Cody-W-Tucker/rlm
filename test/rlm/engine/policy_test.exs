defmodule Rlm.Engine.PolicyTest do
  use ExUnit.Case, async: true

  alias Rlm.Engine.Policy
  alias Rlm.TestHelpers

  test "context metadata stays constant-size while surfacing structure hints" do
    settings = TestHelpers.settings()

    bundle = %{
      entries: [
        %{label: "/tmp/Week-09-2025.md", type: :file},
        %{label: "/tmp/Week-10-2025.md", type: :file}
      ],
      lazy_entries: [
        %{label: "/tmp/Week-09-2025.md", type: :file},
        %{label: "/tmp/Week-10-2025.md", type: :file}
      ],
      text: "",
      bytes: 4096
    }

    metadata = Policy.context_metadata(bundle, settings, "summarize")

    assert metadata =~
             "Structure hint: Likely weekly or dated notes grouped by week-like source names."

    assert metadata =~ "File-backed sources: 2"
    assert metadata =~ "Lazy file-backed size: 0 bytes across 2 file(s)"
    assert metadata =~ "Grounding hint: Base the final answer on direct inspection of the files"
    assert metadata =~ "targeted `read_file()` windows count as inspected evidence"
    assert metadata =~ "Prefer verified claims from inspected files over path-heavy attribution"
    assert metadata =~ "Search for concrete behavioral markers, local examples, and contradictions"
    assert metadata =~ "Metadata budget: constant-size summary only"
    refute metadata =~ "/tmp/Week-09-2025.md"
    refute metadata =~ "First 20 files"
  end

  test "context metadata highlights jsonl-specific retrieval hints" do
    settings = TestHelpers.settings()

    bundle = %{
      entries: [
        %{label: "/tmp/chat-history.jsonl", type: :file}
      ],
      lazy_entries: [
        %{label: "/tmp/chat-history.jsonl", type: :file}
      ],
      text: "",
      bytes: 0,
      lazy_bytes: 10_000
    }

    metadata = Policy.context_metadata(bundle, settings, "summarize coding style")

    assert metadata =~ "Likely line-delimited structured records such as JSONL or event/chat history."
    assert metadata =~ "Discover what is actually there"
    assert metadata =~ "hunting for keywords"
    assert metadata =~ "weakening or boundary-check pass"
  end

  test "system prompt requires scouting before chunking" do
    settings = TestHelpers.settings()

    run_state = %{
      total_sub_queries: 0,
      recovery_flags: %{
        recovery_mode: false,
        async_disabled: false,
        broad_subqueries_disabled: false
      }
    }

    prompt = Policy.system_prompt(settings, 1, run_state)

    assert prompt =~ "Always start with a scouting pass"
    assert prompt =~ "ONLY a single Python code block"
    assert prompt =~ "very first characters must be ```python"
    assert prompt =~ "After 2-3 search rounds, stop expanding the search space"

    assert prompt =~
             "look for the concrete content patterns most likely to answer the prompt"

    assert prompt =~ "Make scouting goal-directed"
    assert prompt =~ "Do not spend iterations re-deriving filenames"
    assert prompt =~ "first decide whether filename/path structure is informative"
    assert prompt =~ "use `sample_files()` or `list_files()`"
    assert prompt =~ "return path strings"
    assert prompt =~ "Good: `path = files[0]`"
    assert prompt =~ "Also tolerated: `path = files[0]['path']`"
    assert prompt =~ "Do not use `files[0].path`"
    assert prompt =~ "`read_jsonl(path, offset=1, limit=20)`"
    assert prompt =~ "`sample_jsonl(path, limit=20)`"
    assert prompt =~ "`grep_jsonl_fields(path, field_pattern, text_pattern=\".*\", limit=20)`"
    assert prompt =~ "first search neutral behavioral markers and nearby phrasing"
    assert prompt =~ "`grep_open(pattern, limit=10, window=12)`"
    assert prompt =~ "`assess_evidence(question, hits=None, reads=None, hypothesis=None)`"
    assert prompt =~ "prefer `peek_hit(hit)` or `open_hit(hit)`"
    assert prompt =~ "For large line-delimited files such as `jsonl`, logs, CSV, or TSV"
    assert prompt =~ "For JSONL or chat-history corpora, first inspect the schema with `sample_jsonl()`"
    assert prompt =~ "Hit objects from `grep_files()`, `grep_open()`, and `grep_jsonl_fields()` expose attributes"
    assert prompt =~ "Prefer attribute access for hits"
    assert prompt =~ "Good: `hit.path`, `hit.line`, `hit.text`, `hit.field`, `hit.value`"
    assert prompt =~ "Also tolerated: `hit['line']`, `hit['field']`, `hit['value']`"
    assert prompt =~ "Tuple-style indexing like `hit[0]`, `hit[1]` may work for compatibility"
    assert prompt =~ "a targeted `read_file()` window counts as direct inspection"
    assert prompt =~ "do not force every claim into a `(from /path/to/file)` label"
    assert prompt =~ "If a concept is synthesized across multiple notes, say so"
    assert prompt =~ "Prefer `peek_file()` before `read_file()`"
    assert prompt =~ "run a neutral retrieval pass, read surrounding passages, form a tentative claim"
    assert prompt =~ "usually 3-4 direct reads"
    assert prompt =~ "Use `assess_evidence()` after a few searches"
    assert prompt =~ "Keep an explicit verification loop in variables"
    assert prompt =~ "`working_claim`, `expected_nearby_patterns`, `weakening_patterns`"
    assert prompt =~ "Search for context that is close to evidence"
    assert prompt =~ "Let inspected passages update the claim"
    assert prompt =~ "prefer a brief structured evidence pass first"

    assert prompt =~
             "prefer parallel sub-queries with `asyncio.gather(async_llm_query(...), ...)`"
  end

  test "system prompt forces synthesis on the final iteration" do
    settings = TestHelpers.settings(%{max_iterations: 4})

    run_state = %{
      total_sub_queries: 0,
      recovery_flags: %{
        recovery_mode: false,
        async_disabled: false,
        broad_subqueries_disabled: false
      }
    }

    prompt = Policy.system_prompt(settings, 4, run_state)

    assert prompt =~ "FINAL ITERATION: Do not gather more evidence"
    assert prompt =~ "end this iteration by calling `FINAL(...)`"
    assert prompt =~ "expected-nearby patterns"
    assert prompt =~ "weakening patterns"
  end

  test "iteration feedback escalates toward finalization near the budget limit" do
    settings = TestHelpers.settings(%{max_iterations: 4})

    exec_result = %{
      stdout: "",
      stderr: "",
      has_final: false,
      details: %{
        evidence: %{
          read_files: ["/tmp/a.jsonl"],
          read_windows: ["/tmp/a.jsonl:98:10"],
          read_followups: [%{path: "/tmp/a.jsonl", query_kind: "behavioral"}],
          search_count: 3,
          search_queries: [%{kind: "behavioral"}],
          hit_paths: ["/tmp/a.jsonl"],
          previewed_files: ["/tmp/a.jsonl"]
        }
      }
    }

    run_state = %{
      total_sub_queries: 0,
      best_answer_so_far: "A concise synthesis is ready",
      best_answer_reason: :stdout,
      last_successful_subquery_result: nil
    }

    bundle = %{
      entries: [%{label: "/tmp/a.jsonl", type: :file}],
      lazy_entries: [%{label: "/tmp/a.jsonl", type: :file}],
      text: "",
      bytes: 0,
      lazy_bytes: 10_000
    }

    feedback = Policy.iteration_feedback(exec_result, settings, 3, run_state, bundle)

    assert feedback =~ "The last step inspected file content but produced no visible output"
    assert feedback =~ "One iteration remains"
    assert feedback =~ "Do not gather more evidence on the next turn"
    assert feedback =~ "call `FINAL(...)` next"
  end
end
