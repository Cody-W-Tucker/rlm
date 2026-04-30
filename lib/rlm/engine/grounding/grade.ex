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
        metrics: metrics
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
        read_windows: MapSet.new()
      },
      fn record, acc ->
        evidence = Policy.evidence(Map.get(record, :details) || %{})

        %{
          search_count: max(acc.search_count, evidence.search_count),
          hit_paths: merge_paths(acc.hit_paths, evidence.hit_paths),
          previewed_files: merge_paths(acc.previewed_files, evidence.previewed_files),
          read_files: merge_paths(acc.read_files, evidence.read_files),
          read_windows: merge_paths(acc.read_windows, evidence.read_windows)
        }
      end
    )
    |> then(fn aggregate ->
      %{
        search_count: aggregate.search_count,
        hit_paths: MapSet.size(aggregate.hit_paths),
        previewed_files: MapSet.size(aggregate.previewed_files),
        read_files: MapSet.size(aggregate.read_files),
        read_windows: MapSet.size(aggregate.read_windows)
      }
    end)
  end

  defp merge_paths(existing, paths) do
    Enum.reduce(paths, existing, &MapSet.put(&2, &1))
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
    "Strong file grounding: read #{metrics.read_files} file(s) and #{metrics.read_windows} targeted window(s) after scouting #{metrics.previewed_files} previews and #{metrics.search_count} search rounds."
  end

  defp summary(:read_backed, metrics) do
    "Limited file grounding: read #{metrics.read_files} file(s) and #{metrics.read_windows} targeted window(s) after scouting #{metrics.previewed_files} previews and #{metrics.search_count} search rounds."
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
end
