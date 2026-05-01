defmodule Rlm.Engine.Response.FencedBlocks do
  @moduledoc false

  alias Rlm.Engine.Response.Salvage

  def extract(text) do
    {blocks, current_language, current_lines} =
      text
      |> String.split("\n")
      |> Enum.reduce({[], nil, []}, fn line, {blocks, current_language, current_lines} ->
        case Regex.run(~r/^```\s*([a-zA-Z0-9_-]*)\s*$/, line, capture: :all_but_first) do
          [language] when current_language == nil ->
            {blocks, language, []}

          [_language] ->
            block = maybe_build_block(current_language, current_lines)
            next_blocks = if block, do: blocks ++ [block], else: blocks
            {next_blocks, nil, []}

          nil when current_language == nil ->
            {blocks, nil, []}

          nil ->
            {blocks, current_language, current_lines ++ [line]}
        end
      end)

    blocks =
      case maybe_build_block(current_language, current_lines) do
        nil -> blocks
        block -> blocks ++ [block]
      end

    Enum.reduce(blocks, [], fn {language, code}, acc ->
      trimmed = Salvage.sanitize_code_block(code)

      if trimmed != "" and
           (language in ["python", "py", "repl"] or Salvage.looks_like_python?(trimmed)) do
        acc ++ [trimmed]
      else
        acc
      end
    end)
  end

  defp maybe_build_block(nil, _lines), do: nil

  defp maybe_build_block(language, lines) do
    {language, Enum.join(lines, "\n")}
  end
end
