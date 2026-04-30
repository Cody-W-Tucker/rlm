defmodule Mix.Tasks.Rlm.PostMortem do
  @moduledoc "Analyze saved run traces into issue categories and regression ideas."
  use Mix.Task

  alias Rlm.PostMortem
  alias Rlm.PostMortem.State
  alias Rlm.Storage.RunStore

  @shortdoc "Post-mortem saved run traces"

  @switches [json: :boolean, incremental: :boolean, since: :string, reset_checkpoint: :boolean]

  @impl Mix.Task
  def run(args) do
    {opts, paths, invalid} = OptionParser.parse(args, strict: @switches)

    start_app(opts)

    cond do
      invalid != [] -> Mix.raise("unknown option #{inspect(hd(invalid))}")
      length(paths) > 1 -> Mix.raise("expected at most one path")
      true -> dispatch(List.first(paths) || default_runs_path(), opts)
    end
  end

  defp start_app(opts) do
    if opts[:json] do
      previous_shell = Mix.shell()

      try do
        Mix.shell(Mix.Shell.Quiet)
        Mix.Task.run("app.start")
      after
        Mix.shell(previous_shell)
      end
    else
      Mix.Task.run("app.start")
    end
  end

  defp dispatch(path, opts) do
    if opts[:reset_checkpoint] do
      storage_dir = ensure_directory!(path)
      {:ok, _state_path} = State.reset(storage_dir)

      if not opts[:incremental] and is_nil(opts[:since]) do
        Mix.shell().info("Reset post-mortem checkpoint for #{storage_dir}")
        :ok
      else
        run_incremental(storage_dir, opts)
      end
    else
      if opts[:incremental] || opts[:since] do
        run_incremental(ensure_directory!(path), opts)
      else
        print_report(PostMortem.analyze_path(path), opts)
      end
    end
  end

  defp run_incremental(storage_dir, opts) do
    {:ok, state, _state_path} = State.load(storage_dir)
    State.assert_version_match!(state)

    runs = storage_dir |> RunStore.list_runs() |> Enum.sort()
    since_run = opts[:since] || get_in(state, ["processing", "last_processed_run"])
    pending_runs = pending_runs(runs, since_run)

    report_result = PostMortem.analyze_paths(pending_runs, storage_dir)

    last_processed_run =
      case List.last(pending_runs) do
        nil -> since_run
        path -> Path.basename(path)
      end

    {:ok, _state_path} = State.save_processed(storage_dir, last_processed_run)
    print_report(report_result, opts)
  end

  defp print_report(result, opts) do
    case result do
      {:ok, report} ->
        if opts[:json] do
          IO.write(Jason.encode!(report, pretty: true) <> "\n")
        else
          Mix.shell().info(Rlm.PostMortem.render(report))
        end

      {:error, message} ->
        Mix.raise(message)
    end
  end

  defp pending_runs(runs, nil), do: runs

  defp pending_runs(runs, since_run) do
    Enum.drop_while(runs, &(Path.basename(&1) <= since_run))
  end

  defp ensure_directory!(path) do
    expanded = Path.expand(path)

    if File.dir?(expanded) do
      expanded
    else
      Mix.raise("incremental post-mortem expects a runs directory, got: #{path}")
    end
  end

  defp default_runs_path do
    :rlm
    |> Application.get_env(Rlm.Settings, [])
    |> Keyword.get(:storage_dir, Path.expand("~/.local/state/rlm/runs"))
  end
end
