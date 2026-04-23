defmodule Rlm.TestLoopProvider do
  @behaviour Rlm.Providers.Provider

  def generate_code(_history, _system_prompt, _settings) do
    {:ok, %{text: "```python\nprint('working')\n```", input_tokens: 0, output_tokens: 0}}
  end

  def complete_subquery(_sub_context, _instruction, _settings) do
    {:ok, %{text: "unused", input_tokens: 0, output_tokens: 0}}
  end
end

defmodule Rlm.TestAsyncProvider do
  @behaviour Rlm.Providers.Provider

  def generate_code(_history, _system_prompt, _settings) do
    {:ok,
     %{text: "```python\nresult = async_llm_query(context, \"Summarize this chunk\")\nprint(result)\nFINAL(result)\n```", input_tokens: 0, output_tokens: 0}}
  end

  def complete_subquery(_sub_context, _instruction, _settings) do
    {:ok, %{text: "async summary", input_tokens: 0, output_tokens: 0}}
  end
end

defmodule Rlm.RLM.EngineTest do
  use ExUnit.Case, async: false

  alias Rlm.RLM.Engine
  alias Rlm.TestHelpers

  test "executes code in the Python runtime and returns a final answer" do
    settings = TestHelpers.settings(%{max_iterations: 4, max_sub_queries: 3})
    bundle = %{entries: [], text: "abcdef", bytes: 6}

    assert {:ok, result} = Engine.run("summarize", bundle, settings, Rlm.Providers.Mock)
    assert result.completed?
    assert result.answer =~ "Observed context"
    assert result.answer =~ "abcdef"
    assert result.total_sub_queries == 0
    assert length(result.iteration_records) == 1
  end

  test "returns bounded result when max iterations are reached" do
    settings = TestHelpers.settings(%{max_iterations: 2})
    bundle = %{entries: [], text: "abcdef", bytes: 6}

    assert {:ok, result} = Engine.run("loop forever", bundle, settings, Rlm.TestLoopProvider)
    assert result.status == :max_iterations
    refute result.completed?
  end

  test "handles async_llm_query when model code forgets to await it" do
    settings = TestHelpers.settings(%{max_iterations: 2, max_sub_queries: 3})
    bundle = %{entries: [], text: "abcdef", bytes: 6}

    assert {:ok, result} = Engine.run("summarize", bundle, settings, Rlm.TestAsyncProvider)
    assert result.completed?
    assert result.answer == "async summary"
    assert hd(result.iteration_records).stdout =~ "async summary"
    assert result.total_sub_queries == 1
  end
end
