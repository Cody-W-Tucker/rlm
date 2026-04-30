defmodule Rlm.PostMortem.State do
  @moduledoc false

  alias Rlm.PostMortem
  alias Rlm.Storage.RunStore

  @state_version 1
  @default_state %{
    "version" => @state_version,
    "postmortem_version" => nil,
    "run_schema_version" => nil,
    "processing" => %{"last_processed_run" => nil}
  }

  def path(storage_dir) do
    storage_dir
    |> Path.expand()
    |> Path.dirname()
    |> Path.join("postmortem-state.json")
  end

  def load(storage_dir) do
    state_path = path(storage_dir)

    case File.read(state_path) do
      {:ok, contents} ->
        case Jason.decode(contents) do
          {:ok, %{} = state} -> {:ok, Map.merge(@default_state, state), state_path}
          {:ok, _other} -> {:error, "expected a JSON object in #{state_path}"}
          {:error, error} -> {:error, "failed to decode #{state_path}: #{Exception.message(error)}"}
        end

      {:error, :enoent} ->
        {:ok, @default_state, state_path}

      {:error, reason} ->
        {:error, "failed to read #{state_path}: #{inspect(reason)}"}
    end
  end

  def reset(storage_dir) do
    state_path = path(storage_dir)
    File.mkdir_p!(Path.dirname(state_path))
    File.write!(state_path, Jason.encode!(fresh_state(), pretty: true))
    {:ok, state_path}
  end

  def save_processed(storage_dir, last_processed_run) do
    state_path = path(storage_dir)
    state =
      fresh_state()
      |> put_in(["processing", "last_processed_run"], last_processed_run)

    File.mkdir_p!(Path.dirname(state_path))
    File.write!(state_path, Jason.encode!(state, pretty: true))
    {:ok, state_path}
  end

  def assert_version_match!(state) do
    state_postmortem_version = state["postmortem_version"]
    state_run_schema_version = state["run_schema_version"]

    cond do
      is_nil(state_postmortem_version) and is_nil(state_run_schema_version) ->
        :ok

      state_postmortem_version == PostMortem.postmortem_version() and
          state_run_schema_version == RunStore.run_schema_version() ->
        :ok

      true ->
        raise version_error(state_postmortem_version, state_run_schema_version)
    end
  end

  def fresh_state do
    %{
      "version" => @state_version,
      "postmortem_version" => PostMortem.postmortem_version(),
      "run_schema_version" => RunStore.run_schema_version(),
      "processing" => %{"last_processed_run" => nil}
    }
  end

  defp version_error(state_postmortem_version, state_run_schema_version) do
    "post-mortem checkpoint is stale: checkpoint has postmortem_version=#{inspect(state_postmortem_version)} and run_schema_version=#{inspect(state_run_schema_version)}, current values are postmortem_version=#{PostMortem.postmortem_version()} and run_schema_version=#{RunStore.run_schema_version()}. Run with --reset-checkpoint before using --incremental."
  end
end
