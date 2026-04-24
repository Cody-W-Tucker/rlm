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

defmodule Rlm.TestSubqueryErrorProvider do
  @behaviour Rlm.Providers.Provider

  def generate_code(_history, _system_prompt, _settings) do
    {:ok,
     %{
       text:
         "```python\nresult = llm_query(context, \"Summarize this chunk\")\nprint(\"subquery completed\")\nprint(result)\n```",
       input_tokens: 0,
       output_tokens: 0
     }}
  end

  def complete_subquery(_sub_context, _instruction, _settings) do
    {:error, "%Req.TransportError{reason: :timeout}"}
  end
end

defmodule Rlm.TestParallelAsyncProvider do
  @behaviour Rlm.Providers.Provider

  def generate_code(_history, _system_prompt, _settings) do
    {:ok,
     %{
       text: """
       ```python
       import asyncio

       async def main():
           results = await asyncio.gather(
               async_llm_query(context[:3], "left"),
               async_llm_query(context[3:], "right"),
           )
           answer = " | ".join(results)
           print(answer)
           FINAL(answer)

       asyncio.run(main())
       ```
       """,
       input_tokens: 0,
       output_tokens: 0
     }}
  end

  def complete_subquery(_sub_context, instruction, _settings) do
    Process.sleep(250)
    {:ok, %{text: "#{instruction} summary", input_tokens: 0, output_tokens: 0}}
  end
end

defmodule Rlm.TestRecoveringProvider do
  @behaviour Rlm.Providers.Provider

  def generate_code(history, _system_prompt, _settings) do
    if Enum.any?(history, &String.contains?(&1.content, "Recovery mode:")) do
      {:ok,
       %{
         text: "```python\nFINAL(\"Recovered via a simpler direct answer\")\n```",
         input_tokens: 0,
         output_tokens: 0
       }}
    else
      {:ok,
       %{
         text:
           "```python\nresult = llm_query(context, \"Summarize this chunk\")\nprint(\"subquery completed\")\nprint(result)\n```",
         input_tokens: 0,
         output_tokens: 0
       }}
    end
  end

  def complete_subquery(_sub_context, _instruction, _settings) do
    {:error, "%Req.TransportError{reason: :timeout}"}
  end
end

defmodule Rlm.TestMalformedFenceProvider do
  @behaviour Rlm.Providers.Provider

  def generate_code(_history, _system_prompt, _settings) do
    {:ok,
     %{
       text: "```\n# The user probably wants Markdown fences here\nFINAL(\"should not execute\")",
       input_tokens: 0,
       output_tokens: 0
     }}
  end

  def complete_subquery(_sub_context, _instruction, _settings) do
    {:ok, %{text: "unused", input_tokens: 0, output_tokens: 0}}
  end
end

defmodule Rlm.TestPlainPythonProvider do
  @behaviour Rlm.Providers.Provider

  def generate_code(_history, _system_prompt, _settings) do
    {:ok, %{text: "FINAL(\"plain python works\")", input_tokens: 0, output_tokens: 0}}
  end

  def complete_subquery(_sub_context, _instruction, _settings) do
    {:ok, %{text: "unused", input_tokens: 0, output_tokens: 0}}
  end
end

defmodule Rlm.TestSilentSubqueryProvider do
  @behaviour Rlm.Providers.Provider

  def generate_code(_history, _system_prompt, _settings) do
    {:ok,
     %{
       text: "```python\nanswer = llm_query(context, \"Summarize this chunk\")\n```",
       input_tokens: 0,
       output_tokens: 0
     }}
  end

  def complete_subquery(_sub_context, _instruction, _settings) do
    {:ok, %{text: "silent subquery answer", input_tokens: 0, output_tokens: 0}}
  end
end

defmodule Rlm.TestSilentSubqueryRecoveryProvider do
  @behaviour Rlm.Providers.Provider

  def generate_code(history, _system_prompt, _settings) do
    if Enum.any?(
         history,
         &String.contains?(&1.content, "Candidate answer text from that sub-query:")
       ) do
      {:ok,
       %{
         text: "```python\nFINAL(answer)\n```",
         input_tokens: 0,
         output_tokens: 0
       }}
    else
      {:ok,
       %{
         text: "```python\nanswer = llm_query(context, \"Summarize this chunk\")\n```",
         input_tokens: 0,
         output_tokens: 0
       }}
    end
  end

  def complete_subquery(_sub_context, _instruction, _settings) do
    {:ok, %{text: "silent subquery answer", input_tokens: 0, output_tokens: 0}}
  end
end

defmodule Rlm.EngineTest do
  use ExUnit.Case, async: false

  alias Rlm.Engine
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

  test "strips malformed fenced responses before execution" do
    settings = TestHelpers.settings(%{max_iterations: 1})
    bundle = %{entries: [], text: "abcdef", bytes: 6}

    assert {:ok, result} =
             Engine.run("summarize", bundle, settings, Rlm.TestMalformedFenceProvider)

    assert result.completed?
    assert result.answer == "should not execute"
    assert length(result.iteration_records) == 1
  end

  test "still accepts unfenced plain python responses" do
    settings = TestHelpers.settings(%{max_iterations: 1})
    bundle = %{entries: [], text: "abcdef", bytes: 6}

    assert {:ok, result} = Engine.run("summarize", bundle, settings, Rlm.TestPlainPythonProvider)

    assert result.completed?
    assert result.answer == "plain python works"
  end

  test "uses successful silent sub-query text as the best partial answer" do
    settings = TestHelpers.settings(%{max_iterations: 1, max_sub_queries: 2})
    bundle = %{entries: [], text: "abcdef", bytes: 6}

    assert {:ok, result} =
             Engine.run("summarize", bundle, settings, Rlm.TestSilentSubqueryProvider)

    assert result.status == :max_iterations
    refute result.completed?
    assert result.answer =~ "silent subquery answer"
    assert result.best_answer_reason == :subquery_success
    assert result.last_successful_subquery_result == "silent subquery answer"
  end

  test "iteration feedback steers silent sub-query results toward finalization" do
    settings = TestHelpers.settings(%{max_iterations: 2, max_sub_queries: 2})
    bundle = %{entries: [], text: "abcdef", bytes: 6}

    assert {:ok, result} =
             Engine.run("summarize", bundle, settings, Rlm.TestSilentSubqueryRecoveryProvider)

    assert result.completed?
    assert result.answer == "silent subquery answer"
    assert result.total_sub_queries == 1
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

  test "runs async_llm_query calls in parallel with asyncio gather" do
    settings = TestHelpers.settings(%{max_iterations: 2, max_sub_queries: 4})
    bundle = %{entries: [], text: "abcdef", bytes: 6}
    started_at = System.monotonic_time(:millisecond)

    assert {:ok, result} =
             Engine.run("summarize", bundle, settings, Rlm.TestParallelAsyncProvider)

    elapsed = System.monotonic_time(:millisecond) - started_at

    assert result.completed?
    assert result.answer == "left summary | right summary"
    assert result.total_sub_queries == 2
    assert elapsed < 450
  end

  test "returns the best partial answer instead of a raw internal error" do
    settings = TestHelpers.settings(%{max_iterations: 3, max_sub_queries: 3})
    bundle = %{entries: [], text: "abcdef", bytes: 6}

    assert {:ok, result} = Engine.run("summarize", bundle, settings, PartialThenErrorProvider)
    refute result.completed?
    assert result.status == :provider_timeout
    assert result.answer =~ "Recovered summary from partial work"
    assert result.answer =~ "best partial answer available"
    assert result.answer =~ "provider timed out"
    assert result.best_answer_reason == :stdout
    assert Enum.any?(result.failure_history, &(&1.class == :provider_timeout))
  end

  test "routes sub-query failures to stderr instead of normal response text" do
    settings = TestHelpers.settings(%{max_iterations: 1, max_sub_queries: 3})
    bundle = %{entries: [], text: "abcdef", bytes: 6}

    assert {:ok, result} =
             Engine.run("summarize", bundle, settings, Rlm.TestSubqueryErrorProvider)

    assert result.status == :provider_timeout
    refute result.completed?

    record = hd(result.iteration_records)
    assert record.stdout == ""
    assert record.stderr =~ "SubqueryError"
    assert record.stderr =~ "%Req.TransportError{reason: :timeout}"
    refute record.stderr =~ "Unexpected sub-query result"
  end

  test "uses one recovery iteration with stricter policy after a sub-query timeout" do
    settings = TestHelpers.settings(%{max_iterations: 2, max_sub_queries: 3})
    bundle = %{entries: [], text: "abcdef", bytes: 6}

    assert {:ok, result} = Engine.run("summarize", bundle, settings, Rlm.TestRecoveringProvider)
    assert result.completed?
    assert result.answer == "Recovered via a simpler direct answer"
    assert result.recovery_flags.recovery_mode
    assert result.recovery_flags.broad_subqueries_disabled
    assert Enum.any?(result.failure_history, &(&1.class == :provider_timeout))
    assert result.iterations == 2
  end
end
