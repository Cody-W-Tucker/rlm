defmodule Rlm.Engine.Policy do
  @moduledoc "Prompt and iteration policy for the RLM engine."

  def context_metadata(context_bundle, _settings, prompt) do
    context = context_bundle.text
    source_count = length(context_bundle.entries)
    lazy_entries = Map.get(context_bundle, :lazy_entries, [])
    lazy_file_count = length(lazy_entries)
    inline_chars = String.length(context)
    structure_hint = structure_hint(context_bundle, context)

    source_types =
      context_bundle.entries
      |> Enum.frequencies_by(& &1.type)
      |> Enum.map_join(", ", fn {type, count} -> "#{count} #{type}" end)

    source_types_display = if source_types == "", do: "none", else: source_types

    access_hint =
      cond do
        lazy_file_count > 0 and inline_chars > 0 ->
          "Inline text is available in `context`. Use `list_files()`, `read_file(path)`, and `grep_files(pattern)` for file-backed sources."

        lazy_file_count > 0 ->
          "Context is file-backed. Use `list_files()`, `read_file(path)`, and `grep_files(pattern)` instead of assuming `context` contains the corpus."

        true ->
          "Context is preloaded in `context`."
      end

    strategy_hint =
      cond do
        context_bundle.bytes <= 20_000 and source_count <= 20 and lazy_file_count == 0 ->
          "This looks small-to-medium. Prefer direct reasoning over the whole context or one small number of sub-queries."

        context_bundle.bytes <= 80_000 and lazy_file_count == 0 ->
          "This looks medium-sized. Start with direct synthesis, then one narrow sub-query if needed, and only then consider small sequential chunking."

        lazy_file_count > 0 ->
          "This looks file-backed. Scout by listing files, grep for high-signal terms from the query, read only the most promising files, and keep the working set small."

        true ->
          "This looks large. Structure the work carefully, keep chunk counts low, and maintain a best-so-far answer."
      end

    [
      "Context Header:",
      "  - Query: #{prompt}",
      "  - Aggregate size: #{context_bundle.bytes} bytes across #{source_count} source(s)",
      "  - Preloaded context chars: #{inline_chars}",
      "  - File-backed sources: #{lazy_file_count}",
      "  - Source types: #{source_types_display}",
      "  - Structure hint: #{structure_hint}",
      "  - Access hint: #{access_hint}",
      "  - Strategy hint: #{strategy_hint}",
      "  - Metadata budget: constant-size summary only; inspect content via REPL tools."
    ]
    |> Enum.join("\n")
  end

  def system_prompt(settings, iteration, run_state) do
    remaining_iterations = settings.max_iterations - iteration + 1
    remaining_sub_queries = settings.max_sub_queries - run_state.total_sub_queries

    sub_model_note =
      if settings.sub_model,
        do: "Sub-queries use #{settings.sub_model}.",
        else: "Sub-queries use the root model."

    strategy_constraints = strategy_constraints(run_state.recovery_flags)

    """
    You are a Recursive Language Model (RLM) agent. You process arbitrarily large contexts by writing Python code in a persistent REPL.

    Budget:
    - #{remaining_iterations} iteration(s) remaining out of #{settings.max_iterations}
    - #{remaining_sub_queries} sub-query call(s) remaining out of #{settings.max_sub_queries}
    - #{sub_model_note}

     Available in the REPL:
    1. `context`: preloaded inline context as a Python string. It may be empty when the input is file-backed.
    2. `list_files(limit=200, offset=0)`: list file-backed sources available to inspect.
    3. `read_file(path, offset=1, limit=200)`: read a specific allowed file with line numbers.
    4. `grep_files(pattern, limit=50)`: regex search across allowed files and return matching file/line pairs.
    5. `llm_query(sub_context, instruction)`: ask a sub-query over a chunk.
    6. `async_llm_query(sub_context, instruction)`: async wrapper for parallel chunk work.
    7. `FINAL(answer)` and `FINAL_VAR(value)`: finish with the final answer.
    8. `SubqueryError`: exception raised when a sub-query fails.

    Rules:
    - Respond with ONLY a Python code block.
    - Use print() for intermediate output.
    - Treat iterations, sub-queries, tokens, and latency as a strict budget.
    - Always start with a scouting pass: inspect the context header, then use `print(len(context))` for preloaded text or `print(list_files())` for file-backed inputs before reading deeply.
    - Make scouting goal-directed: look for the content patterns most likely to answer the prompt, such as repeated themes, reflective passages, summaries, decision logs, section headers, or recurring motifs.
    - Do not spend iterations re-deriving filenames or source layout unless the task specifically depends on source structure.
    - Treat file/path boundaries, week/day/date markers, and other separators as optional signals, not the main retrieval strategy.
    - For file-backed inputs, avoid broad reads. Use `grep_files()` to narrow candidates, then `read_file()` only on the best matches.
    - Every `llm_query()` call is expensive. Minimize calls and prefer direct reasoning when the context header says the input is small or medium.
    - Do not chunk by default. Start with direct synthesis or a single targeted sub-query unless the context is clearly too large.
    - If you chunk, use the fewest chunks that could work and keep the code simple.
    - After scouting, if you find a small set of independent high-value candidates, prefer parallel sub-queries with `asyncio.gather(async_llm_query(...), ...)` over slow sequential fan-out.
    - Do not use parallel fan-out before scouting, and keep it focused on the top candidates instead of broad shotgun chunking.
    - If a sub-query raises `SubqueryError`, catch it only to change strategy or finalize from the best available answer.
    - Keep a best-so-far answer in a variable and finalize early when it is good enough.
    - Filter and slice context with Python before calling llm_query().
    - Store intermediate results in variables because the REPL is persistent.
    - Call FINAL() as soon as you have a useful answer; do not spend budget polishing unnecessarily.
    #{strategy_constraints}
    """
  end

  def iteration_feedback(exec_result, settings, iteration, run_state) do
    parts = []

    parts =
      if exec_result.stdout != "",
        do:
          parts ++ ["Output:\n#{truncate_output(exec_result.stdout, settings.truncate_length)}"],
        else: parts

    parts =
      if exec_result.stderr != "",
        do: parts ++ ["Stderr:\n#{String.slice(exec_result.stderr, 0, 5_000)}"],
        else: parts

    parts =
      if parts == [],
        do: ["(No output produced. The code ran without printing anything.)"],
        else: parts

    best_answer_note =
      cond do
        run_state.best_answer_reason == :subquery_success ->
          "A sub-query already returned candidate answer text. Reuse it directly and finalize unless one cleanup pass adds clear value."

        run_state.best_answer_so_far ->
          "Best answer so far is available. Finalize if the next step does not add material value."

        true ->
          "No best-so-far answer has been captured yet."
      end

    subquery_candidate_note =
      if exec_result.stdout == "" and exec_result.stderr == "" and not exec_result.has_final and
           is_binary(run_state.last_successful_subquery_result) do
        [
          "The previous code made a successful sub-query but did not print or finalize its result.",
          "Candidate answer text from that sub-query:",
          truncate_output(run_state.last_successful_subquery_result, settings.truncate_length)
        ]
        |> Enum.join("\n")
      else
        nil
      end

    (parts ++
       [
         "Iteration #{iteration}/#{settings.max_iterations}. Sub-queries used: #{run_state.total_sub_queries}/#{settings.max_sub_queries}.",
         best_answer_note,
         subquery_candidate_note,
         "Continue processing or call FINAL() when you have the answer."
       ])
    |> Enum.reject(&is_nil/1)
    |> Enum.join("\n\n")
  end

  defp strategy_constraints(recovery_flags) do
    [
      if(recovery_flags.recovery_mode,
        do:
          "- Recovery mode is active. Prefer direct reasoning or one narrow sub-query, then finalize with the best available answer.",
        else: nil
      ),
      if(recovery_flags.async_disabled,
        do: "- Async is disabled for this run because a previous async-style attempt failed.",
        else: nil
      ),
      if(recovery_flags.broad_subqueries_disabled,
        do:
          "- Broad chunking and parallel fan-out are disabled for this run because a previous broad strategy failed.",
        else: nil
      )
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.join("\n")
  end

  defp truncate_output(text, truncate_length) do
    if String.length(text) <= truncate_length do
      if text == "", do: "[EMPTY OUTPUT]", else: text
    else
      "[TRUNCATED: Last #{truncate_length} chars shown].. " <>
        String.slice(text, -truncate_length, truncate_length)
    end
  end

  defp structure_hint(context_bundle, context) do
    labels = Enum.map(context_bundle.entries, & &1.label)

    cond do
      labels != [] and mostly_weekly?(labels) ->
        "Likely weekly or dated notes grouped by week-like source names."

      labels != [] ->
        "Likely file-based context assembled from source paths."

      Regex.match?(~r/(^|\n)#+\s*Week[-\s_]?[0-9]+/i, context) ->
        "Likely weekly notes split by markdown week headings."

      Regex.match?(~r{(^|\n)/[^\n]+\.[A-Za-z0-9]+($|\n)}, context) ->
        "Likely file-based context with inline path boundaries."

      true ->
        "No strong structure detected yet; scout a sample before chunking."
    end
  end

  defp mostly_weekly?(labels) do
    weekly_count = Enum.count(labels, &Regex.match?(~r/week[-\s_]?[0-9]+/i, Path.basename(&1)))
    weekly_count * 2 >= length(labels)
  end
end
