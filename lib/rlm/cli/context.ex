defmodule Rlm.CLI.Context do
  @moduledoc false

  alias Rlm.Context.Loader

  def empty_bundle do
    Loader.empty_bundle()
  end

  def append(current_bundle, loaded_bundle, settings) do
    Loader.append(current_bundle, loaded_bundle, settings)
  end

  def load_many(sources, settings) do
    Loader.load_many(sources, settings)
  end

  def load(source, settings) do
    Loader.load(source, settings)
  end

  def from_text(text, label, settings) do
    Loader.from_text(text, label, settings)
  end

  def from_cli_options(options) do
    Keyword.get_values(options, :file)
    |> Enum.map(&{:path, &1})
    |> Kernel.++(Enum.map(Keyword.get_values(options, :url), &{:url, &1}))
    |> Kernel.++(Enum.map(Keyword.get_values(options, :text), &{:text, &1}))
  end

  def load_cli_bundle(options, settings, read_stdin_fun \\ fn -> IO.read(:stdio, :all) end) do
    with {:ok, bundle} <- load_many(from_cli_options(options), settings),
         {:ok, bundle} <- maybe_read_stdin(bundle, options, settings, read_stdin_fun) do
      {:ok, bundle}
    end
  end

  def append_sources(current_bundle, sources, settings) do
    with {:ok, bundle} <- load_many(sources, settings),
         {:ok, merged} <- append(current_bundle, bundle, settings) do
      {:ok, merged, bundle}
    end
  end

  def append_source(current_bundle, source, settings) do
    with {:ok, bundle} <- load(source, settings),
         {:ok, merged} <- append(current_bundle, bundle, settings) do
      {:ok, merged, bundle}
    end
  end

  def inline_context_prompt(line) do
    tokens = String.split(line, ~r/\s+/, trim: true)
    {sources, rest} = Enum.split_while(tokens, &String.starts_with?(&1, "@"))
    {Enum.map(sources, &{:path, String.trim_leading(&1, "@")}), Enum.join(rest, " ")}
  end

  def describe_context(context_bundle) do
    if context_bundle.entries == [] do
      ["No context loaded."]
    else
      [
        "Loaded #{length(context_bundle.entries)} source(s), #{context_bundle.bytes} preloaded bytes, #{Map.get(context_bundle, :lazy_bytes, 0)} lazy file-backed bytes."
        | Enum.map(context_bundle.entries, fn entry -> "- #{entry.label}" end)
      ]
    end
  end

  defp maybe_read_stdin(bundle, options, settings, read_stdin_fun) do
    if options[:stdin] do
      stdin_text = read_stdin_fun.()

      with {:ok, stdin_bundle} <- from_text(stdin_text, "stdin", settings) do
        append(bundle, stdin_bundle, settings)
      end
    else
      {:ok, bundle}
    end
  end
end
