defmodule Rlm.CLI do
  @moduledoc "CLI entrypoint for one-shot RLM runs."

  alias Rlm.Context.Loader
  alias Rlm.Providers
  alias Rlm.Engine
  alias Rlm.Settings
  alias Rlm.Storage.RunStore

  @switches [
    file: :keep,
    url: :keep,
    text: :keep,
    stdin: :boolean,
    model: :string,
    sub_model: :string,
    provider: :string,
    help: :boolean,
    verbose: :boolean
  ]

  @aliases [h: :help]

  @help """
  rlm - Recursive Language Model CLI

  Usage:
    mix rlm [options] QUERY
    mix rlm run [options] QUERY
    mix rlm help

  Options:
    --file PATH        Load a file, directory, or glob as context
    --url URL          Load a URL as context
    --text TEXT        Add inline text as context
    --stdin            Read context from standard input
    --model ID         Override the configured root model
    --sub-model ID     Override the configured sub-query model
    --provider NAME    Override the configured provider
    --verbose          Print progress events to stderr
  """

  def main(args) do
    case dispatch(args) do
      :ok ->
        :ok

      {:error, message} ->
        IO.puts(:stderr, message)
        System.halt(1)
    end
  end

  def dispatch(args, opts \\ []) do
    Application.ensure_all_started(:rlm)

    case args do
      ["help" | _] -> print_help()
      ["--help" | _] -> print_help()
      ["-h" | _] -> print_help()
      ["run" | rest] -> one_shot(rest, opts)
      _ -> one_shot(args, opts)
    end
  end

  defp print_help do
    IO.puts(@help)
    :ok
  end

  defp one_shot(args, opts) do
    with {:ok, parsed} <- parse_args(args),
         prompt when is_binary(prompt) and prompt != "" <- Enum.join(parsed.positionals, " "),
         {:ok, settings} <- build_settings(parsed.options),
         {:ok, context_bundle} <- context_bundle(parsed.options, settings),
         {:ok, result} <-
           Engine.run(
             prompt,
             context_bundle,
             settings,
             provider_module(opts, settings),
             on_event: stderr_reporter(parsed.options[:verbose])
           ),
         {:ok, _path} <- RunStore.persist(result, context_bundle, settings, mode: :cli) do
      IO.puts(result.answer)
      :ok
    else
      {:halt, :ok} -> :ok
      "" -> {:error, "A query is required."}
      {:error, _} = error -> error
    end
  end

  defp parse_args(args) do
    {options, positionals, invalid} =
      OptionParser.parse(args, strict: @switches, aliases: @aliases)

    cond do
      invalid != [] -> {:error, "Unknown option #{inspect(hd(invalid))}.\n\n#{@help}"}
      options[:help] -> {:halt, print_help()}
      true -> {:ok, %{options: options, positionals: positionals}}
    end
  end

  defp build_settings(options) do
    overrides =
      options
      |> Enum.filter(fn {key, _value} -> key in [:model, :sub_model, :provider] end)
      |> Enum.into(%{})

    Settings.load(overrides)
  end

  defp provider_module(opts, settings) do
    Keyword.get(opts, :provider_module, Providers.for(settings.provider))
  end

  defp context_bundle(options, settings) do
    sources =
      options
      |> Keyword.get_values(:file)
      |> Enum.map(&{:path, &1})
      |> Kernel.++(Enum.map(Keyword.get_values(options, :url), &{:url, &1}))
      |> Kernel.++(Enum.map(Keyword.get_values(options, :text), &{:text, &1}))

    with {:ok, bundle} <- Loader.load_many(sources, settings),
         {:ok, bundle} <- maybe_read_stdin(bundle, options, settings) do
      {:ok, bundle}
    end
  end

  defp maybe_read_stdin(bundle, options, settings) do
    if options[:stdin] do
      stdin_text = IO.read(:stdio, :all)

      with {:ok, stdin_bundle} <- Loader.from_text(stdin_text, "stdin", settings) do
        Loader.append(bundle, stdin_bundle, settings)
      end
    else
      {:ok, bundle}
    end
  end

  defp stderr_reporter(false), do: nil
  defp stderr_reporter(nil), do: nil

  defp stderr_reporter(_true) do
    fn event ->
      message =
        case event do
          %{type: :iteration_start, iteration: iteration, prompt: prompt} ->
            "iteration #{iteration}: #{prompt}"

          %{type: :generated_code, iteration: iteration, code: code} ->
            "iteration #{iteration} generated code (#{String.length(code)} chars)"

          %{type: :iteration_output, iteration: iteration, stream: stream, text: text} ->
            "iteration #{iteration} #{stream}:\n#{String.trim_trailing(text)}"

          _ ->
            nil
        end

      if message, do: IO.puts(:stderr, message)
    end
  end
end
