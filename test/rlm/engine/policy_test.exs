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
    assert metadata =~ "Grounding hint: Base the final answer on retrieved evidence"
    assert metadata =~ "Metadata budget: constant-size summary only"
    refute metadata =~ "/tmp/Week-09-2025.md"
    refute metadata =~ "First 20 files"
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
             "look for the content patterns most likely to answer the prompt"

    assert prompt =~ "Make scouting goal-directed"
    assert prompt =~ "Do not spend iterations re-deriving filenames"
    assert prompt =~ "first decide whether filename/path structure is informative"
    assert prompt =~ "use `sample_files()` or `list_files()`"
    assert prompt =~ "use `grep_files()` with high-signal query terms"
    assert prompt =~ "`grep_open()` when you want immediate previews"
    assert prompt =~ "prefer `peek_hit(hit)` or `open_hit(hit)`"
    assert prompt =~ "Prefer `peek_file()` before `read_file()`"

    assert prompt =~
             "prefer parallel sub-queries with `asyncio.gather(async_llm_query(...), ...)`"
  end
end
