defmodule Rlm.Engine.Grounding.Policy do
  @moduledoc false

  alias Rlm.Engine.Grounding.Grade

  @minimum_multi_file_reads 3
  @minimum_promoted_read_windows 3
  @abstract_terms [
    "iterative",
    "incremental",
    "mvp",
    "minimum viable",
    "thin slice",
    "vertical slice",
    "progressive elaboration",
    "learning-by-doing",
    "decomposition strategy"
  ]

  def hint(context_bundle) do
    lazy_file_count = length(Map.get(context_bundle, :lazy_entries, []))

    cond do
      lazy_file_count > 0 ->
        "Grounding hint: Base the final answer on direct inspection of the files. Prefer verified claims from inspected files over path-heavy attribution. Search for concrete behavioral markers, local examples, and contradictions rather than abstract theory labels. Name a file only when the claim comes directly from that inspected file and the attribution materially helps the answer. For large line-delimited files, targeted `read_file()` windows count as inspected evidence; you do not need a whole-file read unless the task requires it. Do not introduce unsupported concepts as if they came from the corpus."

      true ->
        "Grounding hint: Base the final answer on the observed context and avoid introducing unsupported claims as if they were present in the input."
    end
  end

  def validate_final_answer(context_bundle, final_answer, details, iteration_records \\ []) do
    if file_backed?(context_bundle) do
      with :ok <- validate_cited_paths(final_answer, details),
           :ok <- validate_grounding_grade(context_bundle, iteration_records),
           :ok <- validate_semantic_answer(final_answer, iteration_records) do
        :ok
      end
    else
      :ok
    end
  end

  def validate_search_progress(_context_bundle, _iteration_records) do
    # Search-promotion checks now run only during validate_final_answer (via
    # validate_grounding_grade).  Blocking :continue was counterproductive:
    # the model needs further iterations to act on the feedback nudge that
    # tells it to stop searching and start reading.
    :ok
  end

  def file_backed?(context_bundle), do: length(Map.get(context_bundle, :lazy_entries, [])) > 0

  def multi_file_backed?(context_bundle),
    do: length(Map.get(context_bundle, :lazy_entries, [])) > 1

  def evidence(details) do
    evidence = details["evidence"] || details[:evidence] || %{}

    %{
      search_count: evidence["search_count"] || evidence[:search_count] || 0,
      search_patterns: evidence["search_patterns"] || evidence[:search_patterns] || [],
      search_queries:
        normalize_entries(evidence["search_queries"] || evidence[:search_queries] || []),
      hit_paths: evidence["hit_paths"] || evidence[:hit_paths] || [],
      previewed_files: evidence["previewed_files"] || evidence[:previewed_files] || [],
      read_files: evidence["read_files"] || evidence[:read_files] || [],
      read_windows: evidence["read_windows"] || evidence[:read_windows] || [],
      read_followups:
        normalize_entries(evidence["read_followups"] || evidence[:read_followups] || [])
    }
  end

  def read_units(context_bundle, metrics) do
    if line_delimited_corpus?(context_bundle) do
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
        %{grade: grade, metrics: metrics, semantic: semantic} ->
          if sufficient_multi_file_grounding?(context_bundle, metrics, semantic) do
            :ok
          else
            search_count = Map.get(metrics, :search_count, 0)

            if search_count >= 1 do
              {:error, multi_file_grounding_message(context_bundle, grade)}
            else
              :ok
            end
          end

        _ ->
          :ok
      end
    else
      :ok
    end
  end

  defp sufficient_multi_file_grounding?(context_bundle, metrics, semantic) do
    read_files = Map.get(metrics, :read_files, 0)

    cond do
      read_files >= @minimum_multi_file_reads ->
        true

      multi_line_delimited_corpus?(context_bundle) ->
        read_units(context_bundle, metrics) >= @minimum_multi_file_reads and
          semantic.level in [:verified_with_challenge, :behaviorally_supported, :partially_supported]

      true ->
        false
    end
  end

  defp multi_file_grounding_message(context_bundle, grade) do
    if multi_line_delimited_corpus?(context_bundle) do
      "Grounding grade #{grade} is too weak for a multi-file line-delimited final answer. Search, preview, then promote either at least #{@minimum_multi_file_reads} relevant files or at least #{@minimum_multi_file_reads} targeted `read_file()`/`read_jsonl()` windows with at least one hit-followup read before finalizing from that smaller inspected set."
    else
      "Grounding grade #{grade} is too weak for a multi-file file-backed final answer. Search, preview, then promote at least #{@minimum_multi_file_reads} relevant files to targeted `read_file()` inspection before finalizing from that smaller inspected set."
    end
  end

  defp validate_search_promotion(context_bundle, iteration_records) do
    case Grade.assess(context_bundle, iteration_records) do
      %{grade: grade, metrics: %{search_count: search_count} = metrics}
      when search_count >= @minimum_promoted_read_windows ->
        read_units = read_units(context_bundle, metrics)

        cond do
          read_units < @minimum_promoted_read_windows ->
            {:error,
             "Grounding grade #{grade} is too weak after #{search_count} search rounds. Stop expanding search and promote at least #{@minimum_promoted_read_windows} strongest hits into targeted `read_file()` or `read_jsonl()` windows before finalizing."}

          metrics.hit_paths >= 1 and Map.get(metrics, :read_followups, 0) < 1 ->
            {:error,
             "Grounding grade #{grade} is still too shallow after #{search_count} search rounds. Do not satisfy the read requirement with generic file-start reads. Follow the strongest hit lines or local passages with targeted `read_file()` or `read_jsonl()` windows before finalizing."}

          true ->
            :ok
        end
      _ ->
        :ok
    end
  end

  defp validate_semantic_answer(final_answer, iteration_records) do
    terms = unsupported_abstract_terms(final_answer)

    if terms == [] do
      :ok
    else
      followups = read_followups(iteration_records)

      unsupported =
        Enum.reject(terms, fn term ->
          Enum.any?(followups, &followup_supports_term?(&1, term))
        end)

      if unsupported == [] do
        :ok
      else
        {:error,
         "Final answer used unsupported abstract labels (#{Enum.join(unsupported, ", ")}). Only use theory-laden labels when inspected passages support them directly; otherwise describe the observed behavior in plainer terms."}
      end
    end
  end

  defp normalize_entries(entries) do
    Enum.map(entries, &normalize_entry/1)
  end

  defp normalize_entry(entry) when is_map(entry) do
    Enum.reduce(entry, %{}, fn {key, value}, acc ->
      Map.put(acc, normalize_key(key), value)
    end)
  end

  defp normalize_entry(entry), do: entry

  defp normalize_key(key) when is_atom(key), do: key

  defp normalize_key(key) when is_binary(key) do
    case key do
      "id" -> :id
      "kind" -> :kind
      "line" -> :line
      "path" -> :path
      "text" -> :text
      "field" -> :field
      "value" -> :value
      "source" -> :source
      "window" -> :window
      "pattern" -> :pattern
      "query_id" -> :query_id
      "query_kind" -> :query_kind
      _ -> key
    end
  end

  defp read_followups(iteration_records) do
    iteration_records
    |> Enum.flat_map(fn record ->
      record
      |> Map.get(:details, %{})
      |> evidence()
      |> Map.get(:read_followups, [])
    end)
  end

  defp unsupported_abstract_terms(text) do
    lowered = String.downcase(text)

    Enum.filter(@abstract_terms, fn term ->
      String.contains?(lowered, term)
    end)
  end

  defp followup_supports_term?(followup, term) do
    followup_text = String.downcase(to_string(Map.get(followup, :text, "")))
    pattern_text = String.downcase(to_string(Map.get(followup, :pattern, "")))

    String.contains?(followup_text, term) or String.contains?(pattern_text, term)
  end

  defp single_line_delimited_source?(context_bundle) do
    case Map.get(context_bundle, :lazy_entries, []) do
      [entry] ->
        line_delimited_entry?(entry)

      _ ->
        false
    end
  end

  defp multi_line_delimited_corpus?(context_bundle) do
    lazy_entries = Map.get(context_bundle, :lazy_entries, [])

    length(lazy_entries) > 1 and Enum.all?(lazy_entries, &line_delimited_entry?/1)
  end

  defp line_delimited_corpus?(context_bundle) do
    single_line_delimited_source?(context_bundle) or multi_line_delimited_corpus?(context_bundle)
  end

  defp line_delimited_entry?(entry) do
    label = to_string(Map.get(entry, :label) || Map.get(entry, "label") || "")
    Enum.any?(~w(.jsonl .ndjson .log .csv .tsv), &String.ends_with?(label, &1))
  end
end
