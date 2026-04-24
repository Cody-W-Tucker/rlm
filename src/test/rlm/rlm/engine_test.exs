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
     %{
       text:
         "```python\nresult = async_llm_query(context, \"Summarize this chunk\")\nprint(result)\nFINAL(result)\n```",
       input_tokens: 0,
       output_tokens: 0
     }}
  end

  def complete_subquery(_sub_context, _instruction, _settings) do
    {:ok, %{text: "async summary", input_tokens: 0, output_tokens: 0}}
  end
end

defmodule Rlm.RLM.EngineTest do
  use ExUnit.Case, async: false

  alias Rlm.RLM.Engine
  alias Rlm.TestHelpers

  defmodule PartialThenErrorProvider do
    @behaviour Rlm.Providers.Provider

    def generate_code(history, _system_prompt, _settings) do
      if Enum.empty?(history) or length(history) == 1 do
        {:ok,
         %{
           text: "```python\nprint('Recovered summary from partial work')\n```",
           input_tokens: 0,
           output_tokens: 0
         }}
      else
        {:error, "provider timed out while refining the answer"}
      end
    end

    def complete_subquery(_sub_context, _instruction, _settings) do
      {:ok, %{text: "unused", input_tokens: 0, output_tokens: 0}}
    end
  end

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

  test "returns the best partial answer instead of a raw internal error" do
    settings = TestHelpers.settings(%{max_iterations: 3, max_sub_queries: 3})
    bundle = %{entries: [], text: "abcdef", bytes: 6}

    assert {:ok, result} = Engine.run("summarize", bundle, settings, PartialThenErrorProvider)
    refute result.completed?
    assert result.status == :provider_error
    assert result.answer =~ "Recovered summary from partial work"
    assert result.answer =~ "best partial answer available"
    assert result.answer =~ "provider timed out"
    assert result.best_answer_reason == :stdout
  end
end
