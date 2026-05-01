defmodule Rlm.Engine.Grounding.Grade do
  @moduledoc false

  alias Rlm.Engine.Grounding.Policy

  def assess(context_bundle, iteration_records) do
    if Policy.file_backed?(context_bundle) do
      metrics = metrics(iteration_records)
      level = level(context_bundle, metrics)

      %{
        grade: grade(level),
        level: level,
        label: label(level),
        summary: summary(level, metrics),
        metrics: metrics,
        semantic: semantic(level, metrics)
      }
    else
      nil
    end
  end

  defp metrics(iteration_records) do
    Enum.reduce(
      iteration_records,
        %{
          search_count: 0,
          hit_paths: MapSet.new(),
          previewed_files: MapSet.new(),
          read_files: MapSet.new(),
          read_windows: MapSet.new(),
          search_queries: MapSet.new(),
          read_followups: MapSet.new()
        },
        fn record, acc ->
          evidence = Policy.evidence(Map.get(record, :details) || %{})

          %{
            search_count: max(acc.search_count, evidence.search_count),
            hit_paths: merge_paths(acc.hit_paths, evidence.hit_paths),
            previewed_files: merge_paths(acc.previewed_files, evidence.previewed_files),
            read_files: merge_paths(acc.read_files, evidence.read_files),
            read_windows: merge_paths(acc.read_windows, evidence.read_windows),
            search_queries: merge_items(acc.search_queries, evidence.search_queries),
            read_followups: merge_items(acc.read_followups, evidence.read_followups)
          }
        end
      )
    |> then(fn aggregate ->
      search_queries = MapSet.to_list(aggregate.search_queries)
      read_followups = MapSet.to_list(aggregate.read_followups)

        %{
          search_count: aggregate.search_count,
          hit_paths: MapSet.size(aggregate.hit_paths),
          previewed_files: MapSet.size(aggregate.previewed_files),
          read_files: MapSet.size(aggregate.read_files),
          read_windows: MapSet.size(aggregate.read_windows),
          behavioral_searches: count_kind(search_queries, "behavioral"),
          expected_support_searches: count_kind(search_queries, "expected_support"),
          counterexample_searches: count_kind(search_queries, "counterexample"),
          theory_loaded_searches: count_kind(search_queries, "theory_loaded"),
          read_followups: length(read_followups),
          behavioral_followups: count_kind(read_followups, "behavioral", :query_kind),
          expected_support_followups: count_kind(read_followups, "expected_support", :query_kind),
          counterexample_followups: count_kind(read_followups, "counterexample", :query_kind),
          theory_loaded_followups: count_kind(read_followups, "theory_loaded", :query_kind)
        }
      end)
  end

  defp merge_paths(existing, paths) do
    Enum.reduce(paths, existing, &MapSet.put(&2, &1))
  end

  defp merge_items(existing, items) do
    Enum.reduce(items, existing, &MapSet.put(&2, &1))
  end

  defp count_kind(items, kind, key \\ :kind) do
    Enum.count(items, fn item -> Map.get(item, key) == kind end)
  end

  defp level(context_bundle, metrics) do
    metrics
    |> Map.put(:read_units, Policy.read_units(context_bundle, metrics))
    |> level()
  end

  defp level(%{read_units: read_units}) when read_units >= 3,
    do: :read_backed_multi

  defp level(%{read_units: read_units}) when read_units >= 1,
    do: :read_backed

  defp level(%{previewed_files: previewed_files}) when previewed_files >= 1, do: :scout_only
  defp level(%{search_count: search_count}) when search_count >= 1, do: :search_only
  defp level(_metrics), do: :ungrounded

  defp grade(:read_backed_multi), do: "A"
  defp grade(:read_backed), do: "B"
  defp grade(:scout_only), do: "C"
  defp grade(:search_only), do: "D"
  defp grade(:ungrounded), do: "F"

  defp label(:read_backed_multi), do: "read-backed"
  defp label(:read_backed), do: "limited read-backed"
  defp label(:scout_only), do: "scout-only"
  defp label(:search_only), do: "search-only"
  defp label(:ungrounded), do: "ungrounded"

  defp summary(:read_backed_multi, metrics) do
    "Strong file grounding: read #{metrics.read_files} file(s) and #{metrics.read_windows} targeted window(s) after scouting #{metrics.previewed_files} previews and #{metrics.search_count} search rounds, with #{metrics.read_followups} read(s) tied back to matched passages."
  end

  defp summary(:read_backed, metrics) do
    "Limited file grounding: read #{metrics.read_files} file(s) and #{metrics.read_windows} targeted window(s) after scouting #{metrics.previewed_files} previews and #{metrics.search_count} search rounds, with #{metrics.read_followups} read(s) tied back to matched passages."
  end

  defp summary(:scout_only, _metrics) do
    "Scout-only grounding: previews and grep hits informed the answer, but no file was promoted to a direct read."
  end

  defp summary(:search_only, _metrics) do
    "Search-only grounding: the run searched file contents but never inspected a concrete file window or direct read."
  end

  defp summary(:ungrounded, _metrics) do
    "Ungrounded file-backed run: no search, preview, or direct file read was recorded."
  end

  defp semantic(level, metrics) do
    semantic_level = semantic_level(level, metrics)

    %{
      grade: semantic_grade(semantic_level),
      level: semantic_level,
      label: semantic_label(semantic_level),
      summary: semantic_summary(semantic_level, metrics)
    }
  end

  defp semantic_level(_level, %{counterexample_followups: counterexamples, behavioral_followups: behavioral})
       when counterexamples >= 1 and behavioral >= 1,
        do: :verified_with_challenge

  defp semantic_level(
         _level,
         %{counterexample_followups: counterexamples, expected_support_followups: supports}
       )
       when counterexamples >= 1 and supports >= 1,
       do: :verified_with_challenge

  defp semantic_level(_level, %{read_followups: followups, behavioral_followups: behavioral})
        when followups >= 1 and behavioral >= 1,
        do: :behaviorally_supported

  defp semantic_level(_level, %{read_followups: followups, expected_support_followups: supports})
       when followups >= 1 and supports >= 1,
       do: :behaviorally_supported

  defp semantic_level(:read_backed_multi, %{read_followups: 0, theory_loaded_searches: theory_loaded})
       when theory_loaded >= 1,
       do: :structural_only

  defp semantic_level(level, %{read_followups: followups})
       when level in [:read_backed_multi, :read_backed] and followups == 0,
       do: :structural_only

  defp semantic_level(_level, %{read_followups: followups}) when followups >= 1,
    do: :partially_supported

  defp semantic_level(_level, _metrics), do: :unverified

  defp semantic_grade(:verified_with_challenge), do: "A"
  defp semantic_grade(:behaviorally_supported), do: "B"
  defp semantic_grade(:partially_supported), do: "C"
  defp semantic_grade(:structural_only), do: "D"
  defp semantic_grade(:unverified), do: "F"

  defp semantic_label(:verified_with_challenge), do: "verified-with-challenge"
  defp semantic_label(:behaviorally_supported), do: "behaviorally-supported"
  defp semantic_label(:partially_supported), do: "partially-supported"
  defp semantic_label(:structural_only), do: "structural-only"
  defp semantic_label(:unverified), do: "unverified"

  defp semantic_summary(:verified_with_challenge, metrics) do
    "Reads followed both supporting passages and at least one read-backed counterexample or surprise-check passage (#{metrics.counterexample_followups})."
  end

  defp semantic_summary(:behaviorally_supported, metrics) do
    "Reads followed matched behavioral or expected-support passages (#{metrics.behavioral_followups + metrics.expected_support_followups}) instead of relying on generic file starts alone."
  end

  defp semantic_summary(:partially_supported, metrics) do
    "Some reads followed matched passages (#{metrics.read_followups}), but the run did not record a read-backed counterexample or surprise-check yet."
  end

  defp semantic_summary(:structural_only, _metrics) do
    "The run satisfied structural read counts, but the recorded reads do not show enough hit-followup evidence to justify abstract synthesis."
  end

  defp semantic_summary(:unverified, _metrics) do
    "The run did not record enough read-backed followup to show that the conclusion updated from inspected passages."
  end
end
