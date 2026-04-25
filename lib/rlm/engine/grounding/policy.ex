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

  def validate_final_answer(context_bundle, final_answer, details) do
    if file_backed?(context_bundle) do
      cited_paths = cited_paths(final_answer)

      if cited_paths == [] do
        :ok
      else
        evidence = evidence(details)
        inspected_paths = MapSet.new(evidence.previewed_files ++ evidence.read_files)

        missing_paths = Enum.reject(cited_paths, &MapSet.member?(inspected_paths, &1))

        if missing_paths == [] do
          :ok
        else
          {:error,
           "Final answer cited file paths without inspecting them in this run: #{Enum.join(missing_paths, ", ")}. Read or preview those files before finalizing, or remove the unsupported citations."}
        end
      end
    else
      :ok
    end
  end

  def file_backed?(context_bundle), do: length(Map.get(context_bundle, :lazy_entries, [])) > 0

  def evidence(details) do
    evidence = details["evidence"] || details[:evidence] || %{}

    %{
      search_count: evidence["search_count"] || evidence[:search_count] || 0,
      search_patterns: evidence["search_patterns"] || evidence[:search_patterns] || [],
      hit_paths: evidence["hit_paths"] || evidence[:hit_paths] || [],
      previewed_files: evidence["previewed_files"] || evidence[:previewed_files] || [],
      read_files: evidence["read_files"] || evidence[:read_files] || []
    }
  end

  def cited_paths(text) when is_binary(text) do
    Regex.scan(~r|`(/[^`\n]+)`|, text, capture: :all_but_first)
    |> List.flatten()
    |> Enum.uniq()
  end

  def cited_paths(_), do: []
end
