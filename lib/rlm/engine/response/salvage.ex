defmodule Rlm.Engine.Response.Salvage do
  @moduledoc false

  def strip_fence_lines(text) do
    text
    |> String.replace(~r/^```[a-zA-Z0-9_-]*\s*\n?/, "")
    |> String.replace(~r/\n?```\s*$/, "")
  end

  def normalize_interleaved_fences(text) do
    Regex.replace(
      ~r/^`{6,}([a-zA-Z0-9_-]+)\s*$/m,
      text,
      "```\n```\\1"
    )
  end

  def first_likely_fenced_block(text) do
    case Regex.scan(~r/```([a-zA-Z0-9_-]*)\s*\n([\s\S]*?)```/, text, capture: :all_but_first) do
      [] ->
        text

      blocks ->
        Enum.find_value(blocks, text, fn [language, code] ->
          cond do
            language in ["python", "py", "repl"] -> code
            looks_like_python?(String.trim(code)) -> code
            true -> nil
          end
        end)
    end
  end

  def salvage_python_tail(text) do
    lines = String.split(text, "\n")

    case Enum.find_index(lines, &python_line?/1) do
      nil -> text
      index -> lines |> Enum.drop(index) |> Enum.join("\n")
    end
  end

  def looks_like_python?(text) do
    trimmed = String.trim(text)

    trimmed != "" and
      (String.contains?(trimmed, [
         "print(",
         "FINAL(",
         "FINAL_VAR(",
         "llm_query(",
         "async_llm_query("
       ]) or
         python_line?(trimmed))
  end

  def python_line?(line) do
    trimmed = String.trim_leading(line)

    trimmed != "" and
      not String.starts_with?(trimmed, ["```", "Here ", "I ", "Let me", "I'll", "We "]) and
      Regex.match?(
        ~r/^(#|import\s+|from\s+|print\(|FINAL\(|FINAL_VAR\(|[A-Za-z_][A-Za-z0-9_]*\s*=|for\s+|while\s+|if\s+|with\s+|try:|except\b|def\s+|class\s+|async\s+def\s+|await\s+|return\b|pass\b)/,
        trimmed
      )
  end
end
