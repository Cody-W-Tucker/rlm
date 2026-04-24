defmodule Rlm.Engine.Policy do
  @moduledoc "Prompt and iteration policy for the RLM engine."

  def context_metadata(context_bundle, settings, prompt) do
    context = context_bundle.text
    lines = String.split(context, "\n")
    source_count = length(context_bundle.entries)
    structure_hint = structure_hint(context_bundle, context)

    source_types =
      context_bundle.entries
      |> Enum.frequencies_by(& &1.type)
      |> Enum.map_join(", ", fn {type, count} -> "#{count} #{type}" end)

    source_preview =
      context_bundle.entries
      |> Enum.take(8)
      |> Enum.map_join("\n", &"  - #{&1.label}")

    source_preview =
      if source_count > 8 do
        source_preview <> "\n  - ... (#{source_count - 8} more sources)"
      else
        source_preview
      end

    source_types_display = if source_types == "", do: "none", else: source_types

    strategy_hint =
      cond do
        context_bundle.bytes <= 20_000 and source_count <= 20 ->
          "This looks small-to-medium. Prefer direct reasoning over the whole context or one small number of sub-queries."

        context_bundle.bytes <= 80_000 ->
          "This looks medium-sized. Start with direct synthesis, then one narrow sub-query if needed, and only then consider small sequential chunking."

        true ->
          "This looks large. Structure the work carefully, keep chunk counts low, and maintain a best-so-far answer."
      end

    [
      "Context Header:",
      "  - Query: #{prompt}",
      "  - Size: #{String.length(context)} characters, #{length(lines)} lines, #{source_count} source(s)",
      "  - Source types: #{source_types_display}",
      "  - Structure hint: #{structure_hint}",
      "  - Strategy hint: #{strategy_hint}",
      "",
      "Source preview:",
      if(source_preview == "", do: "  - (inline or empty context)", else: source_preview),
      "",
      "First #{settings.metadata_preview_lines} lines:",
      Enum.take(lines, settings.metadata_preview_lines) |> Enum.join("\n"),
      "",
      "Last #{settings.metadata_preview_lines} lines:",
      Enum.take(lines, -settings.metadata_preview_lines) |> Enum.join("\n")
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
    1. `context`: the full input text as a Python string.
    2. `llm_query(sub_context, instruction)`: ask a sub-query over a chunk.
    3. `async_llm_query(sub_context, instruction)`: async wrapper for parallel chunk work.
    4. `FINAL(answer)` and `FINAL_VAR(value)`: finish with the final answer.
    5. `SubqueryError`: exception raised when a sub-query fails.

    Rules:
    - Respond with ONLY a Python code block.
    - Use print() for intermediate output.
    - Treat iterations, sub-queries, tokens, and latency as a strict budget.
    - Always start with a scouting pass: `print(len(context))`, inspect a small slice, and identify the likely structure before deeper analysis.
    - During scouting, explicitly test simple heuristics such as file/path boundaries, week/day/date markers, repeated markdown headers, and other obvious separators.
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
      if run_state.best_answer_so_far do
        "Best answer so far is available. Finalize if the next step does not add material value."
      else
        "No best-so-far answer has been captured yet."
      end

    (parts ++
       [
         "Iteration #{iteration}/#{settings.max_iterations}. Sub-queries used: #{run_state.total_sub_queries}/#{settings.max_sub_queries}.",
         best_answer_note,
         "Continue processing or call FINAL() when you have the answer."
       ])
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
