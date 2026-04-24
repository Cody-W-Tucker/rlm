defmodule Rlm.Engine.PolicyTest do
  use ExUnit.Case, async: true

  alias Rlm.Engine.Policy
  alias Rlm.TestHelpers

  test "context metadata surfaces weekly structure hints" do
    settings = TestHelpers.settings()

    bundle = %{
      entries: [
        %{label: "/tmp/Week-09-2025.md", type: :file},
        %{label: "/tmp/Week-10-2025.md", type: :file}
      ],
      text: "# Week-09\nalpha\n# Week-10\nbeta",
      bytes: byte_size("# Week-09\nalpha\n# Week-10\nbeta")
    }

    metadata = Policy.context_metadata(bundle, settings, "summarize")

    assert metadata =~
             "Structure hint: Likely weekly or dated notes grouped by week-like source names."
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

    assert prompt =~ "Always start with a scouting pass: `print(len(context))`"

    assert prompt =~
             "identify the most useful content structure for answering the user's question"

    assert prompt =~ "Make scouting goal-directed"
    assert prompt =~ "Do not spend iterations re-deriving filenames"
    assert prompt =~ "optional signals, not the main retrieval strategy"

    assert prompt =~
             "prefer parallel sub-queries with `asyncio.gather(async_llm_query(...), ...)`"
  end
end
