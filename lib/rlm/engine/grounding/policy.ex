defmodule Rlm.Engine.Grounding.Policy do
  @moduledoc false

  def hint(context_bundle) do
    lazy_file_count = length(Map.get(context_bundle, :lazy_entries, []))

    cond do
      lazy_file_count > 0 ->
        "Grounding hint: Base the final answer on retrieved evidence from the available files. Prefer naming the most relevant files, hits, or observed excerpts. Do not introduce unsupported concepts as if they came from the corpus."

      true ->
        "Grounding hint: Base the final answer on the observed context and avoid introducing unsupported claims as if they were present in the input."
    end
  end
end
