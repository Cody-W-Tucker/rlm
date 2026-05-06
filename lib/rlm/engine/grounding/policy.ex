defmodule Rlm.Engine.Grounding.Policy do
  @moduledoc false

  alias Rlm.Engine.Grounding.Grade

  @minimum_multi_file_reads 3
  @minimum_promoted_read_windows 3
  @early_search_round_threshold 3
  @late_search_round_threshold 6
  def hint(context_bundle) do
    lazy_file_count = length(Map.get(context_bundle, :lazy_entries, []))

    cond do
      lazy_file_count > 0 ->
        "Grounding hint: Base the final answer on direct inspection of the files. Prefer verified claims from inspected files over path-heavy attribution. Search for concrete behavioral markers, local examples, and contradictions rather than abstract theory labels. Name a file only when the claim comes directly from that inspected file and the attribution materially helps the answer. For large line-delimited files, targeted `read_file()` windows count as inspected evidence; you do not need a whole-file read unless the task requires it. Do not introduce unsupported concepts as if they came from the corpus."

      true ->
        "Grounding hint: Base the final answer on the observed context and avoid introducing unsupported claims as if they were present in the input."
    end
  end

  def validate_final_answer(
        context_bundle,
        final_answer,
        details,
        iteration_records \\ [],
        settings \\ nil
      ) do
    if file_backed?(context_bundle) do
      with :ok <- validate_cited_paths(final_answer, details),
           :ok <- validate_judgment_style(final_answer, details, settings),
           :ok <- validate_grounding_grade(context_bundle, iteration_records) do
        :ok
      end
    else
      :ok
    end
  end

  def validate_search_progress(context_bundle, iteration_records) do
    case Grade.assess(context_bundle, iteration_records) do
      %{grade: grade, metrics: %{search_count: search_count} = metrics}
      when search_count >= @early_search_round_threshold ->
        promoted_reads = read_units(context_bundle, metrics)
        target = promoted_read_target(context_bundle)

        cond do
          search_count >= @late_search_round_threshold and
              promoted_reads < target ->
            {:error,
             "Grounding grade #{grade} is still too weak after #{search_count} search rounds. Stop searching now and promote at least #{target} strongest hits into targeted `read_file()` or `read_jsonl()` windows before taking another broad retrieval step."}

          promoted_reads < target ->
            {:error,
             "Grounding grade #{grade} is drifting after #{search_count} search rounds with only #{promoted_reads} promoted read(s). Stop expanding the search space and promote at least #{target} strongest hits into targeted `read_file()` or `read_jsonl()` windows before continuing."}

          true ->
            :ok
        end

      _ ->
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

  def annotate_details(context_bundle, details, settings) do
    details = details || %{}

    if settings && Map.get(settings, :judgment_style) == :compass do
      Map.put(
        details,
        "compass_verification",
        build_compass_verification_report(context_bundle, details)
      )
    else
      details
    end
  end

  def read_units(context_bundle, metrics) do
    if line_delimited_corpus?(context_bundle) do
      max(Map.get(metrics, :read_files, 0), Map.get(metrics, :read_windows, 0))
    else
      Map.get(metrics, :read_files, 0)
    end
  end

  def promoted_read_target(context_bundle) do
    if line_delimited_corpus?(context_bundle) do
      @minimum_promoted_read_windows
    else
      required_file_reads(context_bundle)
    end
  end

  def cited_paths(text) when is_binary(text) do
    Regex.scan(~r|`(/[^`\n]+)`|, text, capture: :all_but_first)
    |> List.flatten()
    |> Enum.uniq()
  end

  def cited_paths(_), do: []

  defp validate_judgment_style(_final_answer, _details, nil), do: :ok
  defp validate_judgment_style(_final_answer, _details, %{judgment_style: :default}), do: :ok

  defp validate_judgment_style(_final_answer, details, %{judgment_style: :compass}) do
    report =
      details["compass_verification"] || details[:compass_verification] ||
        build_compass_verification_report(%{}, details)

    case report do
      %{"status" => "ok"} -> :ok
      %{} = report -> compass_validation_error(report)
    end
  end

  defp validate_judgment_style(_final_answer, _details, _settings), do: :ok

  defp compass_validation_error(report) do
    missing = Map.get(report, "missing_quadrants", [])
    weak = Map.get(report, "weak_quadrants", [])
    unsupported = Map.get(report, "unsupported_entries", [])

    parts =
      []
      |> maybe_append_report("missing quadrant(s): #{Enum.join(missing, ", ")}", missing != [])
      |> maybe_append_report(
        "weak quadrant(s): " <>
          Enum.map_join(weak, "; ", fn item ->
            "#{item["quadrant"]} (#{item["reason"]})"
          end),
        weak != []
      )
      |> maybe_append_report(
        "unsupported entries: " <>
          Enum.map_join(unsupported, "; ", fn item ->
            "#{item["quadrant"]} (#{item["reason"]})"
          end),
        unsupported != []
      )

    {:error,
     "Compass knowledge map is incomplete: #{Enum.join(parts, ". ")}. Fill the missing or weak directions with explicit Compass entries before finalizing."}
  end

  defp build_compass_verification_report(context_bundle, details) do
    compass = details["compass"] || details[:compass]
    quadrants = compass_quadrants(compass)
    missing = Enum.filter(["north", "west", "east", "south"], &(quadrants[&1] == []))
    weak = weak_compass_quadrants(quadrants)
    unsupported = unsupported_compass_entries(quadrants)
    evidence_backed = compass_evidence_backed?(quadrants)

    weak =
      if file_backed?(context_bundle || %{}) and not evidence_backed do
        weak ++
          [%{"quadrant" => "map", "reason" => "no evidence-backed Compass entries recorded"}]
      else
        weak
      end

    %{
      "status" =>
        if(missing == [] and weak == [] and unsupported == [], do: "ok", else: "incomplete"),
      "missing_quadrants" => missing,
      "weak_quadrants" => weak,
      "unsupported_entries" => unsupported,
      "quadrant_counts" =>
        Enum.into(quadrants, %{}, fn {name, entries} -> {name, length(entries)} end),
      "evidence_backed" => evidence_backed,
      "confidence" => compass_confidence(compass)
    }
  end

  defp compass_quadrants(compass) when is_map(compass) do
    %{
      "north" => normalize_compass_entries(compass["north"] || compass[:north]),
      "west" => normalize_compass_entries(compass["west"] || compass[:west]),
      "east" => normalize_compass_entries(compass["east"] || compass[:east]),
      "south" => normalize_compass_entries(compass["south"] || compass[:south])
    }
  end

  defp compass_quadrants(_), do: %{"north" => [], "west" => [], "east" => [], "south" => []}

  defp normalize_compass_entries(entries) when is_list(entries) do
    Enum.map(entries, fn
      %{} = entry ->
        %{
          "kind" => to_string(entry["kind"] || entry[:kind] || ""),
          "text" => to_string(entry["text"] || entry[:text] || ""),
          "evidence" => normalize_evidence_list(entry["evidence"] || entry[:evidence] || [])
        }

      other ->
        %{"kind" => "", "text" => to_string(other), "evidence" => []}
    end)
  end

  defp normalize_compass_entries(_), do: []

  defp normalize_evidence_list(entries) when is_list(entries), do: Enum.map(entries, &to_string/1)
  defp normalize_evidence_list(entry) when is_binary(entry), do: [entry]
  defp normalize_evidence_list(_), do: []

  defp weak_compass_quadrants(quadrants) do
    allowed = compass_kind_families()

    Enum.flat_map(quadrants, fn {quadrant, entries} ->
      cond do
        entries == [] ->
          []

        Enum.all?(entries, &(String.trim(&1["text"]) == "")) ->
          [%{"quadrant" => quadrant, "reason" => "entries have no substantive text"}]

        Enum.all?(entries, &(not compass_kind_allowed?(quadrant, &1["kind"], allowed))) ->
          [
            %{
              "quadrant" => quadrant,
              "reason" => "entries do not use #{quadrant}-appropriate kinds"
            }
          ]

        true ->
          []
      end
    end)
  end

  defp unsupported_compass_entries(quadrants) do
    allowed = compass_kind_families()

    Enum.flat_map(quadrants, fn {quadrant, entries} ->
      Enum.flat_map(entries, fn entry ->
        cond do
          String.trim(entry["text"]) == "" ->
            [%{"quadrant" => quadrant, "reason" => "entry text is blank"}]

          not compass_kind_allowed?(quadrant, entry["kind"], allowed) ->
            [
              %{
                "quadrant" => quadrant,
                "reason" => "kind `#{entry["kind"]}` does not match #{quadrant}"
              }
            ]

          true ->
            []
        end
      end)
    end)
  end

  defp compass_kind_families do
    %{
      "north" => MapSet.new(["origin", "context", "dependency", "genealogy"]),
      "west" => MapSet.new(["adjacent", "similarity", "analogy", "family"]),
      "east" => MapSet.new(["contradiction", "missing", "alternative", "boundary", "critique"]),
      "south" =>
        MapSet.new(["implication", "application", "downstream", "trajectory", "next_step"])
    }
  end

  defp compass_kind_allowed?(quadrant, kind, allowed) do
    MapSet.member?(allowed[quadrant], String.trim(to_string(kind)))
  end

  defp compass_evidence_backed?(quadrants) do
    Enum.any?(quadrants, fn {_quadrant, entries} ->
      Enum.any?(entries, &(&1["evidence"] != []))
    end)
  end

  defp compass_confidence(compass) when is_map(compass) do
    to_string(compass["confidence"] || compass[:confidence] || "")
  end

  defp compass_confidence(_), do: ""

  defp maybe_append_report(parts, text, true), do: parts ++ [text]
  defp maybe_append_report(parts, _text, false), do: parts

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
      not line_delimited_corpus?(context_bundle) and
          read_files >= required_file_reads(context_bundle) ->
        true

      read_files >= @minimum_multi_file_reads ->
        true

      multi_line_delimited_corpus?(context_bundle) ->
        read_units(context_bundle, metrics) >= @minimum_multi_file_reads and
          semantic.level in [
            :verified_with_challenge,
            :behaviorally_supported,
            :partially_supported
          ]

      true ->
        false
    end
  end

  defp multi_file_grounding_message(context_bundle, grade) do
    if multi_line_delimited_corpus?(context_bundle) do
      "Grounding grade #{grade} is too weak for a multi-file line-delimited final answer. Search, preview, then promote either at least #{@minimum_multi_file_reads} relevant files or at least #{@minimum_multi_file_reads} targeted `read_file()`/`read_jsonl()` windows with at least one hit-followup read before finalizing from that smaller inspected set."
    else
      target = required_file_reads(context_bundle)

      "Grounding grade #{grade} is too weak for a multi-file file-backed final answer. Search, preview, then promote at least #{target} relevant files to targeted `read_file()` inspection before finalizing from that smaller inspected set."
    end
  end

  defp validate_search_promotion(context_bundle, iteration_records) do
    case Grade.assess(context_bundle, iteration_records) do
      %{grade: grade, metrics: %{search_count: search_count} = metrics}
      when search_count >= @minimum_promoted_read_windows ->
        read_units = read_units(context_bundle, metrics)
        target = promoted_read_target(context_bundle)

        cond do
          read_units < target ->
            {:error,
             "Grounding grade #{grade} is too weak after #{search_count} search rounds. Stop expanding search and promote at least #{target} strongest hits into targeted `read_file()` or `read_jsonl()` windows before finalizing."}

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

  defp required_file_reads(context_bundle) do
    context_bundle
    |> Map.get(:lazy_entries, [])
    |> length()
    |> min(@minimum_multi_file_reads)
    |> max(1)
  end

  defp line_delimited_entry?(entry) do
    label = to_string(Map.get(entry, :label) || Map.get(entry, "label") || "")
    Enum.any?(~w(.jsonl .ndjson .log .csv .tsv), &String.ends_with?(label, &1))
  end
end
