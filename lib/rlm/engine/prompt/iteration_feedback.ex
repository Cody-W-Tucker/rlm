defmodule Rlm.Engine.Prompt.IterationFeedback do
  @moduledoc false

  def build(exec_result, settings, iteration, run_state) do
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

  defp truncate_output(text, truncate_length) do
    if String.length(text) <= truncate_length do
      if text == "", do: "[EMPTY OUTPUT]", else: text
    else
      "[TRUNCATED: Last #{truncate_length} chars shown].. " <>
        String.slice(text, -truncate_length, truncate_length)
    end
  end
end
