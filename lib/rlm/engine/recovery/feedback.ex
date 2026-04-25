defmodule Rlm.Engine.Recovery.Feedback do
  @moduledoc false

  alias Rlm.Engine.Failure
  alias Rlm.Engine.Recovery.Strategy

  def build(%Failure{} = failure, run_state) do
    [
      "Recovery mode: the previous iteration failed with #{failure.class}.",
      "Failure detail: #{failure.message}",
      failing_block_feedback(failure),
      runtime_suggestion(failure),
      Strategy.recovery_instruction(failure),
      best_answer_instruction(run_state)
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.join("\n")
  end

  defp failing_block_feedback(%Failure{message: message}) do
    index = capture(~r/Failure occurred in block (\d+) of (\d+)\./, message, 1)
    total = capture(~r/Failure occurred in block (\d+) of (\d+)\./, message, 2)
    code = capture(~r/Failing block code:\n([\s\S]*)$/, message, 1)

    if index && total && code do
      "The failure happened in block #{index}/#{total}. Fix or avoid only this block:\n#{code}"
    else
      nil
    end
  end

  defp runtime_suggestion(%Failure{message: message}) do
    case Regex.run(~r/Did you mean: '([^']+)'\?/, message, capture: :all_but_first) do
      [suggestion] ->
        "Python suggested this likely fix: use `#{suggestion}` if that matches your intended variable name."

      _ ->
        nil
    end
  end

  defp capture(regex, text, group) do
    case Regex.run(regex, text, capture: :all_but_first) do
      captures when is_list(captures) and length(captures) >= group ->
        Enum.at(captures, group - 1)

      _ ->
        nil
    end
  end

  defp best_answer_instruction(%{best_answer_so_far: nil}) do
    "If you can answer directly from the context already in memory, do that now."
  end

  defp best_answer_instruction(_run_state) do
    "A best-so-far answer exists. Reuse it, add only high-value evidence, and finalize."
  end
end
