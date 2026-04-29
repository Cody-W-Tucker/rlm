defmodule Rlm.CLI.Session do
  @moduledoc "Interactive CLI session with persistent context and slash commands."

  alias Rlm.CLI.Context
  alias Rlm.CLI.Events
  alias Rlm.CLI.Runner
  alias Rlm.Settings
  alias Rlm.Storage.RunStore

  defstruct [:settings, :provider_module, :io, context_bundle: Context.empty_bundle()]

  @type t :: %__MODULE__{}

  def new(%Settings{} = settings, provider_module, opts \\ []) do
    io = %{gets: Keyword.get(opts, :gets, &IO.gets/1), puts: Keyword.get(opts, :puts, &IO.puts/1)}
    {:ok, %__MODULE__{settings: settings, provider_module: provider_module, io: io}}
  end

  def merge_context(%__MODULE__{} = state, bundle) do
    with {:ok, merged} <- Context.append(state.context_bundle, bundle, state.settings) do
      {:ok, %{state | context_bundle: merged}}
    end
  end

  def loop(%__MODULE__{} = state) do
    state.io.puts.("RLM interactive mode. Type /help for commands.")
    do_loop(state)
  end

  defp do_loop(state) do
    case state.io.gets.("> ") do
      nil ->
        :ok

      input ->
        case handle_line(state, input) do
          {:continue, next_state} ->
            do_loop(next_state)

          {:halt, _next_state} ->
            :ok

          {:error, message, next_state} ->
            state.io.puts.(message)
            do_loop(next_state)
        end
    end
  end

  def handle_line(%__MODULE__{} = state, input) do
    trimmed = String.trim(input)

    cond do
      trimmed == "" -> {:continue, state}
      String.starts_with?(trimmed, "/") -> handle_command(state, trimmed)
      true -> handle_prompt(state, trimmed)
    end
  end

  defp handle_command(state, "/help") do
    state.io.puts.(help_text())
    {:continue, state}
  end

  defp handle_command(state, "/quit"), do: {:halt, state}

  defp handle_command(state, "/context") do
    describe_context(state)
    {:continue, state}
  end

  defp handle_command(state, "/clear-context") do
    state.io.puts.("Context cleared.")
    {:continue, %{state | context_bundle: Context.empty_bundle()}}
  end

  defp handle_command(state, "/runs") do
    runs = RunStore.list_runs(state.settings.storage_dir)

    if runs == [] do
      state.io.puts.("No saved runs yet.")
    else
      Enum.each(runs, &state.io.puts.(&1))
    end

    {:continue, state}
  end

  defp handle_command(state, "/paste") do
    state.io.puts.("Paste context. Type EOF on its own line to finish.")

    pasted = read_paste_lines(state, [])

    with {:ok, bundle} <- Context.from_text(pasted, "paste", state.settings),
         {:ok, merged} <- Context.append(state.context_bundle, bundle, state.settings) do
      state.io.puts.("Pasted text loaded.")
      {:continue, %{state | context_bundle: merged}}
    else
      {:error, message} -> {:error, message, state}
    end
  end

  defp handle_command(state, command) do
    cond do
      String.starts_with?(command, "/provider") -> handle_provider_command(state, command)
      String.starts_with?(command, "/model") -> handle_model_command(state, command)
      String.starts_with?(command, "/file ") -> handle_file_command(state, command)
      String.starts_with?(command, "/url ") -> handle_url_command(state, command)
      true -> {:error, "Unknown command: #{command}", state}
    end
  end

  defp handle_prompt(state, trimmed) do
    {context_sources, prompt} = Context.inline_context_prompt(trimmed)

    with {:ok, state} <- maybe_inline_load(state, context_sources),
         {:ok, result} <- maybe_run_prompt(state, prompt) do
      case result do
        :no_prompt ->
          state.io.puts.("Context loaded.")
          {:continue, state}

        result ->
          state.io.puts.(result.answer)
          {:continue, state}
      end
    else
      {:error, message} -> {:error, message, state}
    end
  end

  defp maybe_inline_load(state, []), do: {:ok, state}

  defp maybe_inline_load(state, sources) do
    with {:ok, merged, _bundle} <- Context.append_sources(state.context_bundle, sources, state.settings) do
      {:ok, %{state | context_bundle: merged}}
    end
  end

  defp maybe_run_prompt(_state, ""), do: {:ok, :no_prompt}

  defp maybe_run_prompt(state, prompt) do
    with {:ok, result} <-
           Runner.run_with_bundle(prompt, state.context_bundle, state.settings, state.provider_module,
             mode: :interactive,
             on_event: Events.interactive_reporter(state.io.puts)
           ) do
      {:ok, result}
    end
  end

  defp describe_context(state) do
    Enum.each(Context.describe_context(state.context_bundle), &state.io.puts.(&1))
  end

  defp help_text do
    """
    /file <path...>       Load files, directories, or globs as context
    /url <url>            Load a URL as context
    /paste                Paste multi-line text until EOF
    /context              Show loaded context
    /clear-context        Remove all loaded context
    /provider [name]      Show or set the provider
    /model [id]           Show or set the model
    /runs                 List saved runs
    /help                 Show this help
    /quit                 Exit the session
    """
  end

  defp read_paste_lines(state, acc) do
    case state.io.gets.("") do
      nil -> Enum.reverse(acc) |> Enum.join("\n")
      "EOF\n" -> Enum.reverse(acc) |> Enum.join("\n")
      line -> read_paste_lines(state, [String.trim_trailing(line, "\n") | acc])
    end
  end

  defp handle_provider_command(state, command) do
    case String.split(command, ~r/\s+/, parts: 2) do
      ["/provider"] ->
        state.io.puts.("Current provider: #{state.settings.provider}")
        {:continue, state}

      ["/provider", provider] ->
        with {:ok, settings} <- Settings.load(%{provider: provider, model: state.settings.model}) do
          state.io.puts.("Provider set to #{settings.provider}.")
          {:continue, %{state | settings: settings}}
        else
          {:error, message} -> {:error, message, state}
        end
    end
  end

  defp handle_model_command(state, command) do
    case String.split(command, ~r/\s+/, parts: 2) do
      ["/model"] ->
        state.io.puts.("Current model: #{state.settings.model}")
        {:continue, state}

      ["/model", model] ->
        with {:ok, settings} <- Settings.load(%{provider: state.settings.provider, model: model}) do
          state.io.puts.("Model set to #{settings.model}.")
          {:continue, %{state | settings: settings}}
        else
          {:error, message} -> {:error, message, state}
        end
    end
  end

  defp handle_file_command(state, command) do
    sources =
      command
      |> String.replace_prefix("/file ", "")
      |> String.split(~r/\s+/, trim: true)
      |> Enum.map(&{:path, &1})

    with {:ok, merged, bundle} <- Context.append_sources(state.context_bundle, sources, state.settings) do
      state.io.puts.("Loaded #{length(bundle.entries)} context source(s).")
      {:continue, %{state | context_bundle: merged}}
    else
      {:error, message} -> {:error, message, state}
    end
  end

  defp handle_url_command(state, command) do
    url = String.replace_prefix(command, "/url ", "")

    with {:ok, merged, _bundle} <- Context.append_source(state.context_bundle, {:url, url}, state.settings) do
      state.io.puts.("Loaded #{url}.")
      {:continue, %{state | context_bundle: merged}}
    else
      {:error, message} -> {:error, message, state}
    end
  end
end
