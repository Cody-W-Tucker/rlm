defmodule Rlm.Storage.RunStore do
  @moduledoc "Persist completed runs, iteration data, and sub-query metadata to local JSON files."

  def persist(result, context_bundle, settings, opts \\ []) do
    File.mkdir_p(settings.storage_dir)

    timestamp =
      DateTime.utc_now()
      |> DateTime.truncate(:second)
      |> DateTime.to_iso8601()
      |> String.replace(~r/[^0-9]/, "")

    path =
      Path.join(
        settings.storage_dir,
        "run-#{timestamp}-#{System.unique_integer([:positive])}.json"
      )

    payload = %{
      prompt: result.prompt,
      status: result.status,
      completed: result.completed?,
      answer: result.answer,
      iterations: result.iterations,
      total_sub_queries: result.total_sub_queries,
      input_tokens: result[:input_tokens],
      output_tokens: result[:output_tokens],
      depth: result.depth,
      best_answer_reason: result[:best_answer_reason],
      recovery_flags: result[:recovery_flags],
      failure_history: result[:failure_history],
      last_successful_subquery: result[:last_successful_subquery],
      last_successful_subquery_result: result[:last_successful_subquery_result],
      mode: Keyword.get(opts, :mode, :interactive),
      context_sources: Enum.map(context_bundle.entries, & &1.label),
      context_bytes: context_bundle.bytes,
      recorded_at: DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601(),
      iteration_records: result.iteration_records
    }

    with {:ok, encoded} <- Jason.encode(payload, pretty: true),
         :ok <- File.write(path, encoded) do
      {:ok, path}
    end
  end

  def list_runs(storage_dir) do
    case File.ls(storage_dir) do
      {:ok, files} ->
        files
        |> Enum.filter(&String.ends_with?(&1, ".json"))
        |> Enum.sort(:desc)
        |> Enum.map(&Path.join(storage_dir, &1))

      {:error, :enoent} ->
        []
    end
  end
end
