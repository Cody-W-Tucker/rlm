defmodule Rlm.Engine.Prompt.ContextStrategy do
  @moduledoc false

  alias Rlm.Engine.Grounding.Policy, as: GroundingPolicy

  def context_metadata(context_bundle, prompt) do
    context = context_bundle.text
    source_count = length(context_bundle.entries)
    lazy_entries = Map.get(context_bundle, :lazy_entries, [])
    lazy_file_count = length(lazy_entries)
    inline_chars = String.length(context)
    structure_hint = structure_hint(context_bundle, context)

    source_types =
      context_bundle.entries
      |> Enum.frequencies_by(& &1.type)
      |> Enum.map_join(", ", fn {type, count} -> "#{count} #{type}" end)

    source_types_display = if source_types == "", do: "none", else: source_types

    access_hint =
      cond do
        lazy_file_count > 0 and inline_chars > 0 ->
          "Inline text is available in `context`. For file-backed sources, use `list_files()` or `sample_files()` to inspect file shape, `peek_file(path)` for light inspection, `read_file(path)` for deeper reads, `grep_files(pattern)` for reusable hits, and `grep_open(pattern)` for search-plus-preview."

        lazy_file_count > 0 ->
          "Context is file-backed. Use `list_files()` or `sample_files()` to inspect file shape, `peek_file(path)` for light inspection, `read_file(path)` for deeper reads, `grep_files(pattern)` for reusable hits, and `grep_open(pattern)` for search-plus-preview instead of assuming `context` contains the corpus."

        true ->
          "Context is preloaded in `context`."
      end

    strategy_hint =
      cond do
        context_bundle.bytes <= 20_000 and source_count <= 20 and lazy_file_count == 0 ->
          "This looks small-to-medium. Prefer direct reasoning over the whole context or one small number of sub-queries."

        context_bundle.bytes <= 80_000 and lazy_file_count == 0 ->
          "This looks medium-sized. Start with direct synthesis, then one narrow sub-query if needed, and only then consider small sequential chunking."

        lazy_file_count > 0 ->
          "This looks file-backed. First decide whether filename or path structure is informative. If it is, derive candidates from file shape. If it is not, derive candidates from content matches. Then recurse only on the top candidates and keep the working set small."

        true ->
          "This looks large. Structure the work carefully, keep chunk counts low, and maintain a best-so-far answer."
      end

    [
      "Context Header:",
      "  - Query: #{prompt}",
      "  - Aggregate size: #{context_bundle.bytes} bytes across #{source_count} source(s)",
      "  - Preloaded context chars: #{inline_chars}",
      "  - File-backed sources: #{lazy_file_count}",
      "  - Source types: #{source_types_display}",
      "  - Structure hint: #{structure_hint}",
      "  - Access hint: #{access_hint}",
      "  - Strategy hint: #{strategy_hint}",
      "  - #{GroundingPolicy.hint(context_bundle)}",
      "  - Metadata budget: constant-size summary only; inspect content via REPL tools."
    ]
    |> Enum.join("\n")
  end

  defp structure_hint(context_bundle, context) do
    labels = Enum.map(context_bundle.entries, & &1.label)

    cond do
      labels != [] and mostly_weekly?(labels) ->
        "Likely weekly or dated notes grouped by week-like source names."

      labels != [] ->
        "Likely file-based context assembled from source paths."

      Regex.match?(~r/(^|\n)#+\s*Week[-\s_]?[0-9]+/i, context) ->
        "Likely weekly notes split by markdown week headings."

      Regex.match?(~r{(^|\n)/[^\n]+\.[A-Za-z0-9]+($|\n)}, context) ->
        "Likely file-based context with inline path boundaries."

      true ->
        "No strong structure detected yet; scout a sample before chunking."
    end
  end

  defp mostly_weekly?(labels) do
    weekly_count = Enum.count(labels, &Regex.match?(~r/week[-\s_]?[0-9]+/i, Path.basename(&1)))
    weekly_count * 2 >= length(labels)
  end
end
