defmodule Rlm.CLI do
  @moduledoc "CLI entrypoint for one-shot RLM runs."

  alias Rlm.CLI.Context
  alias Rlm.CLI.Events
  alias Rlm.CLI.Runner
  alias Rlm.Providers
  alias Rlm.Settings

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
         {:ok, context_bundle} <- Context.load_cli_bundle(parsed.options, settings),
         {:ok, result} <-
           Runner.run_with_bundle(
             prompt,
             context_bundle,
             settings,
             provider_module(opts, settings),
             mode: :cli,
             on_event: Events.stderr_reporter(parsed.options[:verbose])
           ) do
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
end
