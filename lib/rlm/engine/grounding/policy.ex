defmodule Rlm.Engine.Grounding.Policy do
  @moduledoc false

  alias Rlm.Engine.Grounding.Grade

  @minimum_multi_file_reads 3
  @minimum_promoted_read_windows 3

  def hint(context_bundle) do
    lazy_file_count = length(Map.get(context_bundle, :lazy_entries, []))

    cond do
      lazy_file_count > 0 ->
        "Grounding hint: Base the final answer on direct inspection of the files. Prefer verified claims from inspected files over path-heavy attribution. Name a file only when the claim comes directly from that inspected file and the attribution materially helps the answer. For large line-delimited files, targeted `read_file()` windows count as inspected evidence; you do not need a whole-file read unless the task requires it. Do not introduce unsupported concepts as if they came from the corpus."

      true ->
        "Grounding hint: Base the final answer on the observed context and avoid introducing unsupported claims as if they were present in the input."
    end
  end

  def validate_final_answer(context_bundle, final_answer, details, iteration_records \\ []) do
    if file_backed?(context_bundle) do
      with :ok <- validate_cited_paths(final_answer, details),
           :ok <- validate_grounding_grade(context_bundle, iteration_records) do
        :ok
      end
    else
      :ok
    end
  end

  def validate_search_progress(context_bundle, iteration_records) do
    if file_backed?(context_bundle) do
      validate_search_promotion(context_bundle, iteration_records)
    else
      :ok
    end
  end

  def file_backed?(context_bundle), do: length(Map.get(context_bundle, :lazy_entries, [])) > 0

  def multi_file_backed?(context_bundle),
    do: length(Map.get(context_bundle, :lazy_entries, [])) > 1

  def evidence(details) do
    evidence = details["evidence"] || details[:evidence] || %{}

    %{
      search_count: evidence["search_count"] || evidence[:search_count] || 0,
      search_patterns: evidence["search_patterns"] || evidence[:search_patterns] || [],
      hit_paths: evidence["hit_paths"] || evidence[:hit_paths] || [],
      previewed_files: evidence["previewed_files"] || evidence[:previewed_files] || [],
      read_files: evidence["read_files"] || evidence[:read_files] || [],
      read_windows: evidence["read_windows"] || evidence[:read_windows] || []
    }
  end

  def read_units(context_bundle, metrics) do
    if single_line_delimited_source?(context_bundle) do
      max(Map.get(metrics, :read_files, 0), Map.get(metrics, :read_windows, 0))
    else
      Map.get(metrics, :read_files, 0)
    end
  end

  def cited_paths(text) when is_binary(text) do
    Regex.scan(~r|`(/[^`\n]+)`|, text, capture: :all_but_first)
    |> List.flatten()
    |> Enum.uniq()
  end

  def cited_paths(_), do: []

  defp validate_cited_paths(final_answer, details) do
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
  end

  defp validate_grounding_grade(context_bundle, iteration_records) do
    with :ok <- validate_multi_file_grounding(context_bundle, iteration_records),
         :ok <- validate_search_promotion(context_bundle, iteration_records) do
      :ok
    end
  end

  defp validate_multi_file_grounding(context_bundle, iteration_records) do
    if multi_file_backed?(context_bundle) do
      case Grade.assess(context_bundle, iteration_records) do
        %{grade: grade, metrics: %{read_files: read_files, search_count: search_count}}
        when read_files < @minimum_multi_file_reads and search_count >= 1 ->
          {:error,
           "Grounding grade #{grade} is too weak for a multi-file file-backed final answer. Search, preview, then promote at least #{@minimum_multi_file_reads} relevant files to targeted `read_file()` inspection before finalizing from that smaller inspected set."}

        _ ->
          :ok
      end
    else
      :ok
    end
  end

  defp validate_search_promotion(context_bundle, iteration_records) do
    case Grade.assess(context_bundle, iteration_records) do
      %{grade: grade, metrics: %{search_count: search_count} = metrics}
      when search_count >= @minimum_promoted_read_windows ->
        read_units = read_units(context_bundle, metrics)

        if read_units < @minimum_promoted_read_windows do
          {:error,
           "Grounding grade #{grade} is too weak after #{search_count} search rounds. Stop expanding search and promote at least #{@minimum_promoted_read_windows} strongest hits into targeted `read_file()` or `read_jsonl()` windows before finalizing."}
        else
          :ok
        end

      _ ->
        :ok
    end
  end

  defp single_line_delimited_source?(context_bundle) do
    case Map.get(context_bundle, :lazy_entries, []) do
      [entry] ->
        label = to_string(Map.get(entry, :label) || Map.get(entry, "label") || "")
        Enum.any?(~w(.jsonl .ndjson .log .csv .tsv), &String.ends_with?(label, &1))

      _ ->
        false
    end
  end
end
