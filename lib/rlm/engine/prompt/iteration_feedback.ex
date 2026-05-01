defmodule Rlm.Engine.Prompt.IterationFeedback do
  @moduledoc false

  alias Rlm.Engine.Grounding.Grade
  alias Rlm.Engine.Grounding.Policy, as: GroundingPolicy

  def build(exec_result, settings, iteration, run_state, context_bundle) do
    parts = []
    remaining_iterations = settings.max_iterations - iteration

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

    consolidation_note = consolidation_note(exec_result)
    grounding_note = grounding_note(exec_result, context_bundle)
    no_output_note = no_output_note(exec_result)
    endgame_note = endgame_note(exec_result, run_state, remaining_iterations)

    (parts ++
       [
         "Iteration #{iteration}/#{settings.max_iterations}. Sub-queries used: #{run_state.total_sub_queries}/#{settings.max_sub_queries}.",
         best_answer_note,
         grounding_note,
         consolidation_note,
         no_output_note,
         endgame_note,
         subquery_candidate_note,
         "Continue processing or call FINAL() when you have the answer."
       ])
    |> Enum.reject(&is_nil/1)
    |> Enum.join("\n\n")
  end

  defp truncate_output(text, truncate_length) do
    if String.length(text) <= truncate_length do
      if text == "", do: "[EMPTY OUTPUT]", else: text
    else
      "[TRUNCATED: Last #{truncate_length} chars shown].. " <>
        String.slice(text, -truncate_length, truncate_length)
    end
  end

  defp consolidation_note(exec_result) do
    evidence = GroundingPolicy.evidence(exec_result.details || %{})
    read_units = max(length(evidence.read_files), length(evidence.read_windows))

    cond do
      evidence.search_count >= 6 and read_units < 2 ->
        "You are still scouting after #{evidence.search_count} search rounds with only #{read_units} promoted read(s). Stop searching. Pick the two strongest hit-backed passages, inspect them directly with `read_file()` or `read_jsonl()`, update `working_claim`, then decide whether one more read or `FINAL(...)` is justified."

      evidence.search_count >= 3 and evidence.read_followups == [] ->
        "You have already done multiple search rounds. Stop expanding search; promote the strongest hit lines into targeted `read_file()` or `read_jsonl()` windows, draft a tentative claim from those passages, derive expected-nearby and weakening patterns from that claim, call `assess_evidence()` if you need a convergence check, then run one challenge pass before finalizing."

      evidence.search_count >= 3 ->
        "You already have search hits and at least one read tied to them. Use those passages to refine `supporting_passages`, write a tentative claim, derive one set of weakening patterns that would make the claim too strong, call `assess_evidence()` if you need the next best move, then finalize from the narrowed claim rather than the first claim."

      true ->
        nil
    end
  end

  defp grounding_note(exec_result, context_bundle) do
    case Grade.assess(context_bundle, [%{details: exec_result.details || %{}}]) do
      %{grade: grade, level: :scout_only} ->
        "Current grounding grade: #{grade} (scout-only). The previews and grep hits are useful for high-value introspection, but promote the strongest neutral or counterexample candidates to targeted `read_file()` windows and read at least 3 relevant files before finalizing an evidence-heavy answer."

      %{grade: grade, level: :search_only} ->
        "Current grounding grade: #{grade} (search-only). You have searched for patterns but haven't directly inspected what the files actually contain. Stop searching. Pick the most promising neutral or counterexample hits, preview them with `peek_hit()` or `peek_file()`, then promote at least 3 to targeted `read_file()` windows before finalizing."

      %{
        grade: grade,
        level: :read_backed,
        metrics: %{read_files: read_files, read_windows: windows}
      } ->
        deficit = max(0, 3 - max(read_files, windows))

        "Current grounding grade: #{grade} (limited read-backed). You have read #{read_files} file(s) and #{windows} targeted window(s). You still need #{deficit} more promoted read(s)/window(s) before a multi-file answer is well-grounded. Keep the working set small, but make sure the next reads follow strong hits or nearby examples, update your hypothesis, and check one competing interpretation before finalizing."

      %{grade: grade, label: label, summary: summary, semantic: semantic} ->
        "Current grounding grade: #{grade} (#{label}). #{summary} Semantic grounding: #{semantic.grade} (#{semantic.label}). #{semantic.summary}"

      nil ->
        nil
    end
  end

  defp no_output_note(exec_result) do
    evidence = GroundingPolicy.evidence(exec_result.details || %{})

    if exec_result.stdout == "" and exec_result.stderr == "" and
         (evidence.read_files != [] or evidence.read_windows != [] or
            evidence.read_followups != []) do
      "The last step inspected file content but produced no visible output. `read_file()` returns text but does not print by itself; assign the result, then `print(...)` it for inspection or synthesize and call `FINAL(...)`."
    end
  end

  defp endgame_note(exec_result, run_state, remaining_iterations) do
    cond do
      remaining_iterations <= 0 ->
        "No iterations remain after this one. Do not gather more evidence now. Synthesize from what you already inspected and call `FINAL(...)`."

      remaining_iterations == 1 and ready_to_finalize?(exec_result, run_state) ->
        "One iteration remains. Do not gather more evidence on the next turn unless fixing a specific contradiction. Synthesize from the current evidence and call `FINAL(...)` next."

      remaining_iterations == 1 ->
        "One iteration remains. Avoid broad search expansion. On the next turn, prefer synthesis and `FINAL(...)` over more evidence gathering unless a single contradiction still needs checking."

      remaining_iterations == 2 and ready_to_finalize?(exec_result, run_state) ->
        "Two iterations remain. You already have enough material to converge. Use at most one consolidation pass, then call `FINAL(...)`; do not keep expanding the search space."

      true ->
        nil
    end
  end

  defp ready_to_finalize?(exec_result, run_state) do
    evidence = GroundingPolicy.evidence(exec_result.details || %{})

    is_binary(run_state.best_answer_so_far) or evidence.read_followups != [] or
      evidence.read_files != []
  end
end
