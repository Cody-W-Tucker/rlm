defmodule Rlm.Engine.Response.Extractor do
  @moduledoc false

  alias Rlm.Engine.Response.FencedBlocks
  alias Rlm.Engine.Response.Salvage

  def extract_code_blocks(text) do
    fenced_blocks = FencedBlocks.extract(text)

    cond do
      fenced_blocks != [] ->
        {:ok, fenced_blocks}

      true ->
        trimmed =
          text
          |> Salvage.first_likely_fenced_block()
          |> Salvage.strip_fence_lines()
          |> Salvage.salvage_python_tail()
          |> String.trim()

        cond do
          trimmed == "" ->
            {:error, "Could not extract Python code from provider response."}

          Salvage.looks_like_python?(trimmed) ->
            {:ok, [trimmed]}

          true ->
            {:error, "Could not extract Python code from provider response."}
        end
    end
  end
end
