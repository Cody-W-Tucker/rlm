defmodule Rlm.CLI.Events do
  @moduledoc false

  def stderr_reporter(false), do: nil
  def stderr_reporter(nil), do: nil

  def stderr_reporter(_true) do
    fn event ->
      if message = stderr_message(event) do
        IO.puts(:stderr, message)
      end
    end
  end

  def interactive_reporter(puts_fun) do
    fn event ->
      if message = interactive_message(event) do
        puts_fun.(message)
      end
    end
  end

  def stderr_message(%{type: :iteration_start, iteration: iteration, prompt: prompt}) do
    "iteration #{iteration}: #{prompt}"
  end

  def stderr_message(%{type: :generated_code, iteration: iteration, code: code}) do
    "iteration #{iteration} generated code (#{String.length(code)} chars)"
  end

  def stderr_message(%{type: :iteration_output, iteration: iteration, stream: stream, text: text}) do
    "iteration #{iteration} #{stream}:\n#{String.trim_trailing(text)}"
  end

  def stderr_message(_event), do: nil

  def interactive_message(%{type: :emit_progress, message: message}) do
    "[progress] #{message}"
  end

  def interactive_message(%{type: :inspect_context, label: label}) do
    "[inspect] #{label}"
  end

  def interactive_message(%{type: :sub_query_start, label: label, prompt: prompt}) do
    "[sub-query] #{label}: #{prompt}"
  end

  def interactive_message(%{type: :iteration_output, iteration: iteration, stream: stream, text: text}) do
    "[iteration #{iteration} #{stream}]\n#{String.trim_trailing(text)}"
  end

  def interactive_message(_event), do: nil
end
