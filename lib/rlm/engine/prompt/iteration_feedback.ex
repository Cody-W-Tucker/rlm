defmodule Rlm.Engine.Prompt.IterationFeedback do
  @moduledoc false

  alias Rlm.Engine.Grounding.Grade
  alias Rlm.Engine.Grounding.Policy, as: GroundingPolicy

  def build(exec_result, settings, iteration, run_state, context_bundle) do
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

    consolidation_note = consolidation_note(exec_result)
    grounding_note = grounding_note(exec_result, context_bundle)

    (parts ++
       [
         "Iteration #{iteration}/#{settings.max_iterations}. Sub-queries used: #{run_state.total_sub_queries}/#{settings.max_sub_queries}.",
         best_answer_note,
         grounding_note,
         consolidation_note,
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

    if evidence.search_count >= 3 do
      "You have already done multiple search rounds. Stop expanding search, choose the strongest inspected evidence, and finalize from that small working set."
    else
      nil
    end
  end

  defp grounding_note(exec_result, context_bundle) do
    case Grade.assess(context_bundle, [%{details: exec_result.details || %{}}]) do
      %{grade: grade, level: :scout_only} ->
        "Current grounding grade: #{grade} (scout-only). The previews and grep hits are useful for high-value introspection, but promote the strongest candidates to `read_file()` and read at least 3 relevant files before finalizing an evidence-heavy answer."

      %{grade: grade, level: :search_only} ->
        "Current grounding grade: #{grade} (search-only). Search narrowed the corpus, but inspect concrete file windows with `peek_hit()`, `open_hit()`, or `peek_file()`, then read at least 3 relevant files before finalizing."

      %{grade: grade, level: :read_backed, metrics: %{read_files: read_files}} ->
        "Current grounding grade: #{grade} (limited read-backed). You have only read #{read_files} file(s). For a multi-file corpus, keep the working set small, but read at least 3 relevant files before finalizing."

      %{grade: grade, label: label, summary: summary} ->
        "Current grounding grade: #{grade} (#{label}). #{summary}"

      nil ->
        nil
    end
  end
end
