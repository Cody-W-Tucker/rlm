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

defmodule Rlm.TestTopLevelAwaitProvider do
  @behaviour Rlm.Providers.Provider

  def generate_code(_history, _system_prompt, _settings) do
    {:ok,
     %{
       text:
         "```python\nresult = await async_llm_query(context, \"Summarize this chunk\")\nFINAL(result)\n```",
       input_tokens: 0,
       output_tokens: 0
     }}
  end

  def complete_subquery(_sub_context, _instruction, _settings) do
    {:ok, %{text: "awaited async summary", input_tokens: 0, output_tokens: 0}}
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

defmodule Rlm.TestMultiFenceProvider do
  @behaviour Rlm.Providers.Provider

  def generate_code(_history, _system_prompt, _settings) do
    {:ok,
     %{
       text: """
       ```python
       value = "alpha"
       print(value)
       ```

       ```python
       value = value + " beta"
       print(value)
       FINAL(value)
       ```
       """,
       input_tokens: 0,
       output_tokens: 0
     }}
  end

  def complete_subquery(_sub_context, _instruction, _settings) do
    {:ok, %{text: "unused", input_tokens: 0, output_tokens: 0}}
  end
end

defmodule Rlm.TestMultiFenceUnclosedTailProvider do
  @behaviour Rlm.Providers.Provider

  def generate_code(_history, _system_prompt, _settings) do
    {:ok,
     %{
       text: """
       ```python
       value = "alpha"
       print(value)
       ```

       ```
       value = value + " beta"
       print(value)
       FINAL(value)
       """,
       input_tokens: 0,
       output_tokens: 0
     }}
  end

  def complete_subquery(_sub_context, _instruction, _settings) do
    {:ok, %{text: "unused", input_tokens: 0, output_tokens: 0}}
  end
end

defmodule Rlm.TestProseThenPythonProvider do
  @behaviour Rlm.Providers.Provider

  def generate_code(_history, _system_prompt, _settings) do
    {:ok,
     %{
       text: "I'll inspect the context first.\n\nanswer = \"salvaged from prose\"\nFINAL(answer)",
       input_tokens: 0,
       output_tokens: 0
     }}
  end

  def complete_subquery(_sub_context, _instruction, _settings) do
    {:ok, %{text: "unused", input_tokens: 0, output_tokens: 0}}
  end
end

defmodule Rlm.TestFixtureProvider do
  @behaviour Rlm.Providers.Provider

  def generate_code(_history, _system_prompt, _settings) do
    {:ok,
     %{
       text: Application.fetch_env!(:rlm, :test_fixture_response),
       input_tokens: 0,
       output_tokens: 0
     }}
  end

  def complete_subquery(sub_context, instruction, settings) do
    handler =
      Application.get_env(:rlm, :test_fixture_subquery_handler, fn _sub_context,
                                                                   _instruction,
                                                                   _settings ->
        {:ok, %{text: "fixture summary", input_tokens: 0, output_tokens: 0}}
      end)

    handler.(sub_context, instruction, settings)
  end
end

defmodule Rlm.TestRecoveryFixtureProvider do
  @behaviour Rlm.Providers.Provider

  def generate_code(history, _system_prompt, _settings) do
    text =
      if Enum.any?(history, &String.contains?(&1.content, "Python suggested this likely fix")) do
        Application.fetch_env!(:rlm, :test_fixture_recovery_response)
      else
        Application.fetch_env!(:rlm, :test_fixture_response)
      end

    {:ok, %{text: text, input_tokens: 0, output_tokens: 0}}
  end

  def complete_subquery(sub_context, instruction, settings) do
    handler =
      Application.get_env(:rlm, :test_fixture_subquery_handler, fn _sub_context,
                                                                   _instruction,
                                                                   _settings ->
        {:ok, %{text: "fixture summary", input_tokens: 0, output_tokens: 0}}
      end)

    handler.(sub_context, instruction, settings)
  end
end

defmodule Rlm.TestMultiBlockTypoRecoveryProvider do
  @behaviour Rlm.Providers.Provider

  def generate_code(history, _system_prompt, _settings) do
    if Enum.any?(history, &String.contains?(&1.content, "Python suggested this likely fix")) do
      {:ok,
       %{
         text:
           "```python\ncontemporary_hits = grep_files(\"Belief|belief|meaning|introspection|identity\", limit=5)\ntargets = []\nfor hit in contemporary_hits:\n    if hit.path not in targets:\n        targets.append(hit.path)\n    if len(targets) == 3:\n        break\nfor target in targets:\n    print(read_file(target, limit=5))\nprint(contemporary_hits)\nFINAL(\"recovered after typo\")\n```",
         input_tokens: 0,
         output_tokens: 0
       }}
    else
      {:ok,
       %{
         text: """
         ```python
         print("first block ok")
         contemporary_hits = grep_files("belief", limit=2)
         ```

         ```python
         print(contemporary_haits)
         ```
         """,
         input_tokens: 0,
         output_tokens: 0
       }}
    end
  end

  def complete_subquery(_sub_context, _instruction, _settings) do
    {:ok, %{text: "unused", input_tokens: 0, output_tokens: 0}}
  end
end

defmodule Rlm.TestUnterminatedFinalProvider do
  @behaviour Rlm.Providers.Provider

  def generate_code(_history, _system_prompt, _settings) do
    {:ok,
     %{
       text:
         "```python\nFINAL(\"\"\"\nRecovered final answer from malformed output\n\n- kept the markdown body\n```",
       input_tokens: 0,
       output_tokens: 0
     }}
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

defmodule Rlm.TestFileAccessProvider do
  @behaviour Rlm.Providers.Provider

  def generate_code(_history, _system_prompt, _settings) do
    {:ok,
     %{
       text:
         "```python\npath = list_files()[0]\ncontent = read_file(path)\nprint(path)\nFINAL(content)\n```",
       input_tokens: 0,
       output_tokens: 0
     }}
  end

  def complete_subquery(_sub_context, _instruction, _settings) do
    {:ok, %{text: "unused", input_tokens: 0, output_tokens: 0}}
  end
end

defmodule Rlm.TestGrepFileAccessProvider do
  @behaviour Rlm.Providers.Provider

  def generate_code(_history, _system_prompt, _settings) do
    {:ok,
     %{
       text: """
       ```python
       matches = grep_files("beta", limit=5)
       first = matches[0]
       print(first)
       print(first.path)
       print(first.line)
       print(first.text)
       FINAL(first.path)
       ```
       """,
       input_tokens: 0,
       output_tokens: 0
     }}
  end

  def complete_subquery(_sub_context, _instruction, _settings) do
    {:ok, %{text: "unused", input_tokens: 0, output_tokens: 0}}
  end
end

defmodule Rlm.TestGrepOpenProvider do
  @behaviour Rlm.Providers.Provider

  def generate_code(_history, _system_prompt, _settings) do
    {:ok,
     %{
       text: """
       ```python
       hits = grep_open("beta", limit=2, window=1)
       first = hits[0]
       print(first)
       print(first.preview)
       FINAL(first.preview)
       ```
       """,
       input_tokens: 0,
       output_tokens: 0
     }}
  end

  def complete_subquery(_sub_context, _instruction, _settings) do
    {:ok, %{text: "unused", input_tokens: 0, output_tokens: 0}}
  end
end

defmodule Rlm.TestHitFollowupProvider do
  @behaviour Rlm.Providers.Provider

  def generate_code(_history, _system_prompt, _settings) do
    {:ok,
     %{
       text: """
       ```python
       hit = grep_files("beta", limit=1)[0]
       print(peek_hit(hit, before=1, after=1))
       opened = open_hit(hit, window=1)
       print(opened)
       FINAL(opened.preview)
       ```
       """,
       input_tokens: 0,
       output_tokens: 0
     }}
  end

  def complete_subquery(_sub_context, _instruction, _settings) do
    {:ok, %{text: "unused", input_tokens: 0, output_tokens: 0}}
  end
end

defmodule Rlm.TestFileShapeProvider do
  @behaviour Rlm.Providers.Provider

  def generate_code(_history, _system_prompt, _settings) do
    {:ok,
     %{
       text: """
       ```python
       files = sample_files(2)
       print(files)
       preview = peek_file(files[0], limit=1)
       print(preview)
       FINAL(preview)
       ```
       """,
       input_tokens: 0,
       output_tokens: 0
     }}
  end

  def complete_subquery(_sub_context, _instruction, _settings) do
    {:ok, %{text: "unused", input_tokens: 0, output_tokens: 0}}
  end
end

defmodule Rlm.TestLargeOffsetFileAccessProvider do
  @behaviour Rlm.Providers.Provider

  def generate_code(_history, _system_prompt, _settings) do
    {:ok,
     %{
       text: "```python\npath = list_files()[0]\npreview = peek_file(path, offset=995, limit=3)\ncontent = read_file(path, offset=999, limit=2)\nprint(preview)\nFINAL(content)\n```",
       input_tokens: 0,
       output_tokens: 0
     }}
  end

  def complete_subquery(_sub_context, _instruction, _settings) do
    {:ok, %{text: "unused", input_tokens: 0, output_tokens: 0}}
  end
end

defmodule Rlm.TestEvidenceTrackingProvider do
  @behaviour Rlm.Providers.Provider

  def generate_code(_history, _system_prompt, _settings) do
    {:ok,
     %{
       text: """
       ```python
       files = sample_files(3)
       preview = peek_file(files[0], limit=2)
       hits = grep_open("identity|meaning", limit=2, window=1)
       contents = [read_file(path, limit=2) for path in files]
       print(preview)
       print(hits)
       FINAL(contents[-1])
       ```
       """,
       input_tokens: 0,
       output_tokens: 0
     }}
  end

  def complete_subquery(_sub_context, _instruction, _settings) do
    {:ok, %{text: "unused", input_tokens: 0, output_tokens: 0}}
  end
end

defmodule Rlm.TestUngroundedCitationRecoveryProvider do
  @behaviour Rlm.Providers.Provider

  def generate_code(history, _system_prompt, _settings) do
    if Enum.any?(
         history,
         &String.contains?(&1.content, "Final answer cited file paths without inspecting them")
       ) do
      {:ok,
       %{
         text: """
         ```python
         target = [path for path in list_files() if path.endswith("Aimlessness.md")][0]
         content = read_file(target, limit=5)
         print(content)
         FINAL(f"Recovered with inspected evidence from `\#{target}`")
         ```
         """,
         input_tokens: 0,
         output_tokens: 0
       }}
    else
      {:ok,
       %{
         text: """
         ```python
         target = [path for path in list_files() if path.endswith("Belief.md")][0]
         print(read_file(target, limit=5))
         FINAL("Unsupported citation from `/tmp/placeholder/Aimlessness.md`")
         ```
         """,
         input_tokens: 0,
         output_tokens: 0
       }}
    end
  end

  def complete_subquery(_sub_context, _instruction, _settings) do
    {:ok, %{text: "unused", input_tokens: 0, output_tokens: 0}}
  end
end

defmodule Rlm.TestInsufficientGroundingRecoveryProvider do
  @behaviour Rlm.Providers.Provider

  def generate_code(history, _system_prompt, _settings) do
    if Enum.any?(history, &String.contains?(&1.content, "insufficient_grounding")) do
      {:ok,
       %{
         text:
           "```python\ntargets = [\n    path\n    for path in list_files()\n    if path.endswith(\"Aimlessness.md\") or path.endswith(\"Belief.md\") or path.endswith(\"Sexual Urges Are Elusive to Introspection.md\")\n]\ncontents = [read_file(path, limit=5) for path in targets]\nfor content in contents:\n    print(content)\nFINAL(\"Recovered with 3-file read-backed grounding\")\n```",
         input_tokens: 0,
         output_tokens: 0
       }}
    else
      {:ok,
       %{
         text: """
         ```python
         hits = grep_open("identity|meaning", limit=2, window=1)
         print(hits)
         FINAL("Scout-only synthesis that should be blocked")
         ```
         """,
         input_tokens: 0,
         output_tokens: 0
       }}
    end
  end

  def complete_subquery(_sub_context, _instruction, _settings) do
    {:ok, %{text: "unused", input_tokens: 0, output_tokens: 0}}
  end
end

defmodule Rlm.EngineTest do
  use ExUnit.Case, async: false

  alias Rlm.Engine
  alias Rlm.TestHelpers

  defp fixture_response(name, replacements) do
    path = Path.expand("../fixtures/provider_responses/#{name}", __DIR__)

    Enum.reduce(replacements, File.read!(path), fn {needle, replacement}, acc ->
      String.replace(acc, needle, replacement)
    end)
  end

  defp put_fixture_response(text) do
    Application.put_env(:rlm, :test_fixture_response, text)

    on_exit(fn ->
      Application.delete_env(:rlm, :test_fixture_response)
      Application.delete_env(:rlm, :test_fixture_recovery_response)
      Application.delete_env(:rlm, :test_fixture_subquery_handler)
    end)
  end

  defp put_fixture_recovery_response(text) do
    Application.put_env(:rlm, :test_fixture_recovery_response, text)
  end

  defp build_fixture_corpus(tmp) do
    File.mkdir_p!(Path.join(tmp, "Sexuality"))

    File.write!(
      Path.join(tmp, "Aimlessness.md"),
      "# Aimlessness\n\nAimlessness can feel existential when unused potential presses on identity.\n"
    )

    File.write!(
      Path.join(tmp, "Belief.md"),
      "# Belief Construction\n\nBelief can arise from experience and alter the sense of time and meaning.\n"
    )

    File.write!(
      Path.join(tmp, "Sexuality/Sexual Urges Are Elusive to Introspection.md"),
      "# Sexual Urges Are Elusive to Introspection\n\nSome drives resist direct introspection and are known mostly through effects.\n"
    )
  end

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
    assert hd(result.iteration_records).status == :ok
  end

  test "executes multiple fenced python blocks sequentially in one iteration" do
    settings = TestHelpers.settings(%{max_iterations: 1})
    bundle = %{entries: [], text: "abcdef", bytes: 6}

    assert {:ok, result} = Engine.run("summarize", bundle, settings, Rlm.TestMultiFenceProvider)

    assert result.completed?
    assert result.answer == "alpha beta"
    assert length(result.iteration_records) == 1

    record = hd(result.iteration_records)
    assert record.stdout == "alpha\nalpha beta\n"
    assert record.code =~ "value = \"alpha\""
    assert record.code =~ "FINAL(value)"
  end

  test "salvages an unclosed final fenced block after earlier blocks" do
    settings = TestHelpers.settings(%{max_iterations: 1})
    bundle = %{entries: [], text: "abcdef", bytes: 6}

    assert {:ok, result} =
             Engine.run("summarize", bundle, settings, Rlm.TestMultiFenceUnclosedTailProvider)

    assert result.completed?
    assert result.answer == "alpha beta"
    assert length(result.iteration_records) == 1
  end

  test "salvages prose followed by plain python" do
    settings = TestHelpers.settings(%{max_iterations: 1})
    bundle = %{entries: [], text: "abcdef", bytes: 6}

    assert {:ok, result} =
             Engine.run("summarize", bundle, settings, Rlm.TestProseThenPythonProvider)

    assert result.completed?
    assert result.answer == "salvaged from prose"
    assert result.failure_history == []
  end

  test "executes staged multi-block fixture responses seen in the wild" do
    tmp = TestHelpers.temp_dir("rlm-engine-fixture-staged")
    on_exit(fn -> File.rm_rf!(tmp) end)
    build_fixture_corpus(tmp)

    put_fixture_response(fixture_response("wild_staged_plan.txt", [{"__ROOT__", tmp}]))

    Application.put_env(:rlm, :test_fixture_subquery_handler, fn sub_context,
                                                                 _instruction,
                                                                 _settings ->
      title =
        cond do
          String.contains?(sub_context, "Aimlessness") -> "aimlessness summary"
          String.contains?(sub_context, "Sexual Urges") -> "sexual urges summary"
          String.contains?(sub_context, "Belief Construction") -> "belief summary"
          true -> "fixture summary"
        end

      {:ok, %{text: title, input_tokens: 0, output_tokens: 0}}
    end)

    settings = TestHelpers.settings(%{max_iterations: 1, max_sub_queries: 5})
    assert {:ok, bundle} = Rlm.Context.Loader.load({:path, tmp}, settings)

    assert {:ok, result} = Engine.run("summarize", bundle, settings, Rlm.TestFixtureProvider)

    assert result.completed?
    assert result.failure_history == []
    assert length(result.iteration_records) == 1
    assert result.total_sub_queries == 3
    assert result.answer =~ "aimlessness summary"
    assert result.answer =~ "sexual urges summary"
    assert result.answer =~ "belief summary"

    stdout = hd(result.iteration_records).stdout
    assert stdout =~ "=== Sampling files to understand corpus shape ==="
    assert stdout =~ "=== Searching for philosophical and identity concepts ==="
    assert stdout =~ "=== Loaded key files ==="
  end

  test "salvages malformed interleaved fixture responses from the wild" do
    tmp = TestHelpers.temp_dir("rlm-engine-fixture-malformed")
    on_exit(fn -> File.rm_rf!(tmp) end)
    build_fixture_corpus(tmp)

    put_fixture_response(
      fixture_response("malformed_interleaved_unclosed_tail.txt", [{"__ROOT__", tmp}])
    )

    settings = TestHelpers.settings(%{max_iterations: 1})
    assert {:ok, bundle} = Rlm.Context.Loader.load({:path, tmp}, settings)

    assert {:ok, result} = Engine.run("summarize", bundle, settings, Rlm.TestFixtureProvider)

    assert result.completed?
    assert result.failure_history == []
    assert length(result.iteration_records) == 1
    assert result.answer == "fixture recovered from malformed response"

    stdout = hd(result.iteration_records).stdout
    assert stdout =~ "=== Reading key file ==="
    assert stdout =~ "=== Searching related concepts ==="
  end

  test "recovery feedback includes failing block and python suggestion for later-block typos" do
    tmp = TestHelpers.temp_dir("rlm-engine-typo-recovery")
    on_exit(fn -> File.rm_rf!(tmp) end)
    build_fixture_corpus(tmp)

    settings = TestHelpers.settings(%{max_iterations: 3})
    assert {:ok, bundle} = Rlm.Context.Loader.load({:path, tmp}, settings)

    assert {:ok, result} =
             Engine.run("summarize", bundle, settings, Rlm.TestMultiBlockTypoRecoveryProvider)

    assert result.completed?
    assert result.answer == "recovered after typo"
    assert length(result.failure_history) == 1

    failure = hd(result.failure_history)
    assert failure.class == :python_exec_error
    assert failure.message =~ "Failure occurred in block 2 of 2"
    assert failure.message =~ "print(contemporary_haits)"

    recovery_prompt = Enum.at(result.iteration_records, 0)
    assert recovery_prompt.stderr =~ "Did you mean: 'contemporary_hits'?"
  end

  test "fixture regression covers typo-driven multiblock runtime failure from the wild" do
    tmp = TestHelpers.temp_dir("rlm-engine-typo-fixture")
    on_exit(fn -> File.rm_rf!(tmp) end)
    build_fixture_corpus(tmp)

    put_fixture_response(
      fixture_response("typo_multiblock_runtime_error.txt", [{"__ROOT__", tmp}])
    )

    put_fixture_recovery_response("""
    ```python
    print("=== Recovery pass ===")
    contemporary_hits = grep_files("identity|meaning|Belief|belief|introspection", limit=10)
    targets = []
    for hit in contemporary_hits:
        if hit.path not in targets:
            targets.append(hit.path)
        if len(targets) == 3:
            break
    for target in targets:
        print(read_file(target, limit=5))
    print(contemporary_hits)
    FINAL("recovered from fixture typo")
    ```
    """)

    settings = TestHelpers.settings(%{max_iterations: 3})
    assert {:ok, bundle} = Rlm.Context.Loader.load({:path, tmp}, settings)

    assert {:ok, result} =
             Engine.run("summarize", bundle, settings, Rlm.TestRecoveryFixtureProvider)

    assert result.completed?
    assert result.answer == "recovered from fixture typo"
    assert length(result.failure_history) == 1

    failure = hd(result.failure_history)
    assert failure.message =~ "Failure occurred in block 6 of 6"
    assert failure.message =~ "print(contemporary_haits)"
    assert failure.message =~ "Did you mean: 'contemporary_hits'?"

    first_record = hd(result.iteration_records)
    assert first_record.stdout =~ "=== Sampling files to understand corpus shape ==="
    assert first_record.stdout =~ "=== Searching for philosophical concepts ==="
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

  test "exposes lazy file access tools in the repl" do
    tmp = TestHelpers.temp_dir("rlm-engine-files")
    on_exit(fn -> File.rm_rf!(tmp) end)

    File.write!(Path.join(tmp, "note.txt"), "alpha\nbeta\n")
    settings = TestHelpers.settings(%{max_iterations: 1})

    assert {:ok, bundle} = Rlm.Context.Loader.load({:path, Path.join(tmp, "note.txt")}, settings)
    assert {:ok, result} = Engine.run("summarize", bundle, settings, Rlm.TestFileAccessProvider)

    assert result.completed?
    assert result.answer == "1: alpha\n2: beta"
    assert hd(result.iteration_records).stdout =~ "note.txt"
  end

  test "tracks structured evidence from searches, previews, and reads" do
    tmp = TestHelpers.temp_dir("rlm-engine-evidence")
    on_exit(fn -> File.rm_rf!(tmp) end)

    build_fixture_corpus(tmp)
    settings = TestHelpers.settings(%{max_iterations: 1})

    assert {:ok, bundle} = Rlm.Context.Loader.load({:path, tmp}, settings)

    assert {:ok, result} =
             Engine.run("summarize", bundle, settings, Rlm.TestEvidenceTrackingProvider)

    assert result.completed?
    assert result.grounding.grade == "A"
    assert result.grounding.level == :read_backed_multi

    evidence = get_in(hd(result.iteration_records), [:details, "evidence"])
    assert evidence["search_count"] >= 1
    assert length(evidence["previewed_files"]) >= 1
    assert length(evidence["read_files"]) >= 3
    assert length(evidence["hit_paths"]) >= 1
  end

  test "recovers when final answer cites unread file paths" do
    tmp = TestHelpers.temp_dir("rlm-engine-grounding")
    on_exit(fn -> File.rm_rf!(tmp) end)

    build_fixture_corpus(tmp)
    settings = TestHelpers.settings(%{max_iterations: 3})

    assert {:ok, bundle} = Rlm.Context.Loader.load({:path, tmp}, settings)

    assert {:ok, result} =
             Engine.run("summarize", bundle, settings, Rlm.TestUngroundedCitationRecoveryProvider)

    assert result.completed?
    assert result.answer =~ "Recovered with inspected evidence"
    assert length(result.failure_history) == 1

    failure = hd(result.failure_history)
    assert failure.class == :ungrounded_final_answer
    assert failure.message =~ "without inspecting them in this run"
    assert failure.message =~ "Aimlessness.md"
  end

  test "blocks scout-only finalization on multi-file file-backed runs" do
    tmp = TestHelpers.temp_dir("rlm-engine-grounding-grade")
    on_exit(fn -> File.rm_rf!(tmp) end)

    build_fixture_corpus(tmp)
    settings = TestHelpers.settings(%{max_iterations: 3})

    assert {:ok, bundle} = Rlm.Context.Loader.load({:path, tmp}, settings)

    assert {:ok, result} =
             Engine.run(
               "summarize",
               bundle,
               settings,
               Rlm.TestInsufficientGroundingRecoveryProvider
             )

    assert result.completed?
    assert result.answer =~ "Recovered with 3-file read-backed grounding"
    assert result.grounding.grade == "A"
    assert length(result.failure_history) == 1

    failure = hd(result.failure_history)
    assert failure.class == :insufficient_grounding
    assert failure.message =~ "at least 3 relevant files"
  end

  test "grep_files returns reusable hit objects" do
    tmp = TestHelpers.temp_dir("rlm-engine-grep")
    on_exit(fn -> File.rm_rf!(tmp) end)

    File.write!(Path.join(tmp, "note.txt"), "alpha\nbeta\n")
    settings = TestHelpers.settings(%{max_iterations: 1})

    assert {:ok, bundle} = Rlm.Context.Loader.load({:path, Path.join(tmp, "note.txt")}, settings)

    assert {:ok, result} =
             Engine.run("find beta", bundle, settings, Rlm.TestGrepFileAccessProvider)

    assert result.completed?
    assert result.answer =~ "note.txt"

    stdout = hd(result.iteration_records).stdout
    assert stdout =~ "note.txt:2: beta"
    assert stdout =~ "note.txt"
    assert stdout =~ "2"
    assert stdout =~ "beta"
  end

  test "grep_open returns preview-ready hit objects" do
    tmp = TestHelpers.temp_dir("rlm-engine-grep-open")
    on_exit(fn -> File.rm_rf!(tmp) end)

    File.write!(Path.join(tmp, "note.txt"), "alpha\nbeta\ngamma\n")
    settings = TestHelpers.settings(%{max_iterations: 1})

    assert {:ok, bundle} = Rlm.Context.Loader.load({:path, Path.join(tmp, "note.txt")}, settings)

    assert {:ok, result} =
             Engine.run("find beta", bundle, settings, Rlm.TestGrepOpenProvider)

    assert result.completed?
    assert result.grounding.grade == "C"
    assert result.grounding.level == :scout_only
    assert result.answer =~ "1: alpha"
    assert result.answer =~ "2: beta"
    assert result.answer =~ "3: gamma"

    stdout = hd(result.iteration_records).stdout
    assert stdout =~ "note.txt:2: beta"
    assert stdout =~ "1: alpha"
  end

  test "peek_hit and open_hit support direct hit follow-up" do
    tmp = TestHelpers.temp_dir("rlm-engine-hit-followup")
    on_exit(fn -> File.rm_rf!(tmp) end)

    File.write!(Path.join(tmp, "note.txt"), "alpha\nbeta\ngamma\n")
    settings = TestHelpers.settings(%{max_iterations: 1})

    assert {:ok, bundle} = Rlm.Context.Loader.load({:path, Path.join(tmp, "note.txt")}, settings)

    assert {:ok, result} =
             Engine.run("find beta", bundle, settings, Rlm.TestHitFollowupProvider)

    assert result.completed?
    assert result.answer =~ "1: alpha"
    assert result.answer =~ "2: beta"
    assert result.answer =~ "3: gamma"
  end

  test "sample_files and peek_file support file-shape scouting" do
    tmp = TestHelpers.temp_dir("rlm-engine-shape")
    on_exit(fn -> File.rm_rf!(tmp) end)

    File.write!(Path.join(tmp, "a.txt"), "alpha\nline2\n")
    File.write!(Path.join(tmp, "b.txt"), "beta\nline2\n")
    settings = TestHelpers.settings(%{max_iterations: 1})

    assert {:ok, bundle} = Rlm.Context.Loader.load({:path, tmp}, settings)

    assert {:ok, result} =
             Engine.run("inspect shape", bundle, settings, Rlm.TestFileShapeProvider)

    assert result.completed?
    assert result.answer == "1: alpha"

    stdout = hd(result.iteration_records).stdout
    assert stdout =~ "a.txt"
    assert stdout =~ "b.txt"
    assert stdout =~ "1: alpha"
  end

  test "read_file and peek_file support large late-file windows without whole-file access assumptions" do
    tmp = TestHelpers.temp_dir("rlm-engine-large-window")
    on_exit(fn -> File.rm_rf!(tmp) end)

    lines = Enum.map_join(1..1_000, "\n", fn index -> Jason.encode!(%{"row" => index}) end) <> "\n"

    File.write!(Path.join(tmp, "events.jsonl"), lines)
    settings = TestHelpers.settings(%{max_iterations: 1})

    assert {:ok, bundle} = Rlm.Context.Loader.load({:path, Path.join(tmp, "events.jsonl")}, settings)

    assert {:ok, result} =
             Engine.run("inspect tail window", bundle, settings, Rlm.TestLargeOffsetFileAccessProvider)

    assert result.completed?
    assert result.answer == "999: {\"row\":999}\n1000: {\"row\":1000}"

    stdout = hd(result.iteration_records).stdout
    assert stdout =~ "995: {\"row\":995}"
    assert stdout =~ "997: {\"row\":997}"
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

  test "uses async wrapper fallback for top-level await" do
    settings = TestHelpers.settings(%{max_iterations: 1, max_sub_queries: 2})
    bundle = %{entries: [], text: "abcdef", bytes: 6}

    assert {:ok, result} =
             Engine.run("summarize", bundle, settings, Rlm.TestTopLevelAwaitProvider)

    assert result.completed?
    assert result.answer == "awaited async summary"

    record = hd(result.iteration_records)
    assert record.status == :recovered
    assert record.recovery_kind == :async_wrapper
    assert record.error_kind == nil
    assert record.details["compile_stage"] == "async_wrapper"
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

  test "recovers an unterminated triple-quoted FINAL body" do
    settings = TestHelpers.settings(%{max_iterations: 1})
    bundle = %{entries: [], text: "abcdef", bytes: 6}

    assert {:ok, result} =
             Engine.run("summarize", bundle, settings, Rlm.TestUnterminatedFinalProvider)

    assert result.completed?

    assert result.answer ==
             "Recovered final answer from malformed output\n\n- kept the markdown body"

    record = hd(result.iteration_records)
    assert record.has_final
    assert record.final_value == result.answer
    assert record.stderr == ""
    assert record.status == :recovered
    assert record.error_kind == :syntax_unterminated_triple_quote
    assert record.recovery_kind == :salvaged_unterminated_final
    assert record.details["compile_stage"] == "direct"
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
