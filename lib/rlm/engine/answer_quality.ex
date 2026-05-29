defmodule Rlm.Engine.AnswerQuality do
  @moduledoc false

  @instrumentation_pattern ~r/^(===|PAT\b|CHALLENGE\b|CHALLENGE_READ\b|TARGET_READ\b|SCOUT\b|SAMPLE\b|schema\b|context_len\b|files\b|support_summary\b|suggested_reads\b|next_action\b|READ \d+\b)/
  @excerpt_pattern ~r/^(\d+:\s|\/?[^\s]+:\d+:\s)/
  @path_pattern ~r/(^\/|\.jsonl?(?::\d+)?\b|\.md:\d+\b|\.txt:\d+\b)/
  @json_dump_markers [
    "'record':",
    "\"record\":",
    "{'line':",
    "\"support_summary\"",
    "\"suggested_reads\"",
    "\"next_action\"",
    "\"working_hypothesis\"",
    "\"search_count\""
  ]

  def presentable?(text), do: rejection_reason(text) == nil

  def rejection_reason(text) when not is_binary(text), do: "answer is not text"

  def rejection_reason(text) do
    trimmed = String.trim(text)

    cond do
      trimmed == "" ->
        "answer is empty"

      true ->
        lines = String.split(trimmed, "\n", trim: true)
        instrumentation = Enum.count(lines, &Regex.match?(@instrumentation_pattern, &1))
        excerpts = Enum.count(lines, &Regex.match?(@excerpt_pattern, &1))
        path_lines = Enum.count(lines, &Regex.match?(@path_pattern, &1))

        json_dump_markers =
          Enum.count(@json_dump_markers, fn marker -> String.contains?(trimmed, marker) end)

        line_record_dump? =
          (String.contains?(trimmed, "{'line':") and String.contains?(trimmed, "'record':")) or
            (String.contains?(trimmed, "\"line\":") and String.contains?(trimmed, "\"record\":"))

        cond do
          line_record_dump? ->
            "answer looks like a structured evidence dump"

          json_dump_markers >= 2 and String.length(trimmed) >= 180 ->
            "answer looks like a structured evidence dump"

          String.contains?(trimmed, "{'question':") or
              String.contains?(trimmed, "\"question\":") ->
            "answer looks like a diagnostic payload"

          instrumentation >= 2 and String.length(trimmed) >= 120 ->
            "answer looks like instrumentation output"

          excerpts >= 6 ->
            "answer is mostly raw excerpts"

          excerpts >= 3 and path_lines >= 2 and length(lines) >= 6 ->
            "answer is mostly file-backed evidence"

          path_lines >= 5 and String.length(trimmed) >= 240 ->
            "answer is dominated by source paths"

          true ->
            nil
        end
    end
  end
end
