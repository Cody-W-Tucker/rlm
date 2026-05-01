defmodule Rlm.EngineTestSupport do
  def fixture_response(name, replacements) do
    path = Path.expand("../fixtures/provider_responses/#{name}", __DIR__)

    Enum.reduce(replacements, File.read!(path), fn {needle, replacement}, acc ->
      String.replace(acc, needle, replacement)
    end)
  end

  def build_fixture_corpus(tmp) do
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
end

defmodule Rlm.TestLoopProvider do
  @behaviour Rlm.Providers.Provider

  def generate_code(_history, _system_prompt, _settings) do
    {:ok, %{text: "```python\nprint('working')\n```", input_tokens: 0, output_tokens: 0}}
  end

  def complete_subquery(_sub_context, _instruction, _settings) do
    {:ok, %{text: "unused", input_tokens: 0, output_tokens: 0}}
  end
end

defmodule Rlm.TestEvidenceLoopProvider do
  @behaviour Rlm.Providers.Provider

  def generate_code(_history, _system_prompt, _settings) do
    {:ok,
     %{
       text:
         "```python\nprint('=== KEY EXAMPLE 1 ===')\nprint('1: {\"title\": \"Assess and plan\"}')\nprint('=== KEY EXAMPLE 2 ===')\nprint('/tmp/corpus.jsonl:16: {\"title\": \"Review and plan\"}')\n```",
       input_tokens: 0,
       output_tokens: 0
     }}
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
       text:
         "```python\npath = list_files()[0]\npreview = peek_file(path, offset=995, limit=3)\ncontent = read_file(path, offset=999, limit=2)\nprint(preview)\nFINAL(content)\n```",
       input_tokens: 0,
       output_tokens: 0
     }}
  end

  def complete_subquery(_sub_context, _instruction, _settings) do
    {:ok, %{text: "unused", input_tokens: 0, output_tokens: 0}}
  end
end

defmodule Rlm.TestJsonlRetrievalProvider do
  @behaviour Rlm.Providers.Provider

  def generate_code(_history, _system_prompt, _settings) do
    {:ok,
     %{
       text: """
       ```python
       path = list_files()[0]
       sample = sample_jsonl(path, limit=3)
       hits = grep_jsonl_fields(path, r"messages\[[0-9]+\]\.content", r"async|await|Semaphore|gather", limit=5)
       records = read_jsonl(path, offset=hits[0].line, limit=1)
       print(sample)
       print(hits)
       print(records)
       FINAL(hits[0].field + "|" + hits[0].value)
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

defmodule Rlm.TestJsonlCompatibilityProvider do
  @behaviour Rlm.Providers.Provider

  def generate_code(_history, _system_prompt, _settings) do
    {:ok,
     %{
       text: """
       ```python
       files = list_files()
       path = files[0]['path']
       hits = grep_jsonl_fields(path, r"messages\[[0-9]+\]\.content", r"async|await", limit=2)
       first = hits[0]
       print(path)
       print(first['line'])
       print(first['field'])
       print(first['value'])
       FINAL(str(first['line']))
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

defmodule Rlm.TestJsonlSearchPromotionProvider do
  @behaviour Rlm.Providers.Provider

  def generate_code(history, _system_prompt, _settings) do
    if Enum.any?(history, &String.contains?(&1.content, "Stop expanding search")) do
      {:ok,
       %{
         text: """
         ```python
         path = list_files()[0]
         hits = grep_jsonl_fields(path, r"messages\[[0-9]+\]\.content", r"alpha|beta|gamma", limit=3)
         records = [read_jsonl(path, offset=hit.line, limit=1) for hit in hits]
         print(records)
         FINAL("Recovered from promoted JSONL windows")
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
         path = list_files()[0]
         alpha = grep_jsonl_fields(path, r".*", r"alpha", limit=5)
         beta = grep_jsonl_fields(path, r".*", r"beta", limit=5)
         gamma = grep_jsonl_fields(path, r".*", r"gamma", limit=5)
         print(alpha, beta, gamma)
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

defmodule Rlm.TestAssessEvidenceProvider do
  @behaviour Rlm.Providers.Provider

  def generate_code(_history, _system_prompt, _settings) do
    {:ok,
     %{
       text: """
       ```python
       path = list_files()[0]
       hits = grep_jsonl_fields(path, r"messages\[[0-9]+\]\.content", r"start with|scope", limit=3)
       records = [read_jsonl(path, offset=hit.line, limit=1) for hit in hits[:2]]
       report = assess_evidence(
           question="How does the user scope complex tasks?",
           hits=hits,
           reads=records,
           hypothesis="The user narrows scope first, then checks for exceptions."
       )
       print(report)
       FINAL(report["next_action"] + "|" + str(len(report["suggested_reads"])))
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

defmodule Rlm.TestFollowupEvidenceProvider do
  @behaviour Rlm.Providers.Provider

  def generate_code(_history, _system_prompt, _settings) do
    {:ok,
     %{
       text: """
       ```python
       path = list_files()[0]
       behavior_hits = grep_files("start with|first", limit=1)
       contradiction_hits = grep_files("however|instead", limit=1)
       behavior = behavior_hits[0]
       print(peek_hit(behavior, before=0, after=1))
       print(read_file(behavior.path, offset=behavior.line, limit=2))
       if contradiction_hits:
           contradiction = contradiction_hits[0]
           print(read_file(contradiction.path, offset=contradiction.line, limit=1))
       FINAL("followed matched passages")
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

defmodule Rlm.PartialThenErrorProvider do
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
