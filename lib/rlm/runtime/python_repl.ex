defmodule Rlm.Runtime.PythonRepl do
  @moduledoc "Persistent Python runtime for model-authored code execution."

  use GenServer

  defmodule State do
    @moduledoc false
    defstruct [:port, :buffer, :awaiting, :handler, :task_refs, :received, :shutting_down]
  end

  def start(settings, opts \\ []) do
    with {:ok, pid} <- start_link(settings, opts),
         :ok <- await_ready(pid) do
      {:ok, pid}
    end
  end

  def start_link(settings, opts \\ []) do
    GenServer.start_link(__MODULE__, {settings, opts})
  end

  def set_handler(pid, handler), do: GenServer.call(pid, {:set_handler, handler})

  def set_context(pid, text),
    do:
      GenServer.call(pid, {:await, "context_set", %{type: "set_context", value: text}}, :infinity)

  def reset_final(pid),
    do: GenServer.call(pid, {:await, "final_reset", %{type: "reset_final"}}, :infinity)

  def execute(pid, code),
    do: GenServer.call(pid, {:await, "exec_done", %{type: "exec", code: code}}, :infinity)

  def await_ready(pid), do: GenServer.call(pid, {:await_existing, "ready"}, :infinity)
  def stop(pid), do: GenServer.stop(pid, :normal)

  @impl true
  def init({settings, opts}) do
    runtime_path = Keyword.get(opts, :runtime_path, default_runtime_path())
    command = settings.runtime_command ++ [runtime_path]
    {executable, args} = split_command(command)

    resolved =
      if String.contains?(executable, "/") do
        executable
      else
        System.find_executable(executable) || executable
      end

    port =
      Port.open({:spawn_executable, resolved}, [
        :binary,
        :exit_status,
        :hide,
        args: args
      ])

    {:ok,
     %State{
       port: port,
       buffer: "",
       awaiting: %{},
       handler: fn _sub_context, _instruction -> {:error, "No sub-query handler registered"} end,
       task_refs: %{},
       received: MapSet.new(),
       shutting_down: false
     }}
  end

  @impl true
  def handle_call({:set_handler, handler}, _from, state) do
    {:reply, :ok, %{state | handler: handler}}
  end

  def handle_call({:await_existing, type}, from, state) do
    if MapSet.member?(state.received, type) do
      {:reply, :ok, %{state | received: MapSet.delete(state.received, type)}}
    else
      {:noreply, put_in(state.awaiting[type], from)}
    end
  end

  def handle_call({:await, type, payload}, from, state) do
    send_payload(state.port, payload)
    {:noreply, put_in(state.awaiting[type], from)}
  end

  @impl true
  def handle_info({port, {:data, packet}}, %State{port: port} = state) do
    state = process_packet(packet, state)
    {:noreply, state}
  end

  def handle_info({ref, result}, state) when is_reference(ref) do
    case Map.pop(state.task_refs, ref) do
      {{request_id, _pid}, task_refs} ->
        Process.demonitor(ref, [:flush])

        send_payload(state.port, %{
          type: "llm_result",
          id: request_id,
          result: normalize_task_result(result)
        })

        {:noreply, %{state | task_refs: task_refs}}

      {nil, _task_refs} ->
        {:noreply, state}
    end
  end

  def handle_info({:DOWN, ref, :process, _pid, reason}, state) do
    case Map.pop(state.task_refs, ref) do
      {{request_id, _pid}, task_refs} ->
        send_payload(state.port, %{
          type: "llm_result",
          id: request_id,
          result: "[ERROR] LLM query failed: #{inspect(reason)}"
        })

        {:noreply, %{state | task_refs: task_refs}}

      {nil, _task_refs} ->
        {:noreply, state}
    end
  end

  def handle_info({_port, {:exit_status, status}}, state) do
    error = RuntimeError.exception("Python runtime exited with status #{status}")

    Enum.each(state.awaiting, fn {_type, from} ->
      GenServer.reply(from, {:error, error.message})
    end)

    {:stop, :normal, %{state | awaiting: %{}, shutting_down: true}}
  end

  @impl true
  def terminate(_reason, state) do
    if state.port do
      send_payload(state.port, %{type: "shutdown"})
      Port.close(state.port)
    end

    :ok
  end

  defp default_runtime_path do
    :rlm
    |> :code.priv_dir()
    |> List.to_string()
    |> Path.join("runtime.py")
  end

  defp split_command([executable | args]), do: {executable, args}

  defp send_payload(port, payload) do
    Port.command(port, Jason.encode!(payload) <> "\n")
  end

  defp process_packet(packet, state) when is_binary(packet) do
    {lines, buffer} = split_lines(state.buffer <> packet)

    Enum.reduce(lines, %{state | buffer: buffer}, fn line, acc ->
      case Jason.decode(line) do
        {:ok,
         %{
           "type" => "llm_query",
           "sub_context" => sub_context,
           "instruction" => instruction,
           "id" => request_id
         }} ->
          start_llm_query_task(acc, request_id, sub_context, instruction)

        {:ok, %{"type" => type} = message} ->
          case Map.pop(acc.awaiting, type) do
            {nil, awaiting} ->
              %{acc | awaiting: awaiting, received: MapSet.put(acc.received, type)}

            {from, awaiting} ->
              GenServer.reply(from, normalize_message(type, message))
              %{acc | awaiting: awaiting}
          end

        _ ->
          acc
      end
    end)
  end

  defp split_lines(data) do
    parts = :binary.split(data, "\n", [:global])
    buffer = List.last(parts) || ""
    complete = parts |> Enum.drop(-1) |> Enum.reject(&(&1 == ""))
    {complete, buffer}
  end

  defp normalize_message("ready", _message), do: :ok
  defp normalize_message("context_set", _message), do: :ok
  defp normalize_message("final_reset", _message), do: :ok

  defp normalize_message("exec_done", message) do
    {:ok,
     %{
       stdout: Map.get(message, "stdout", ""),
       stderr: Map.get(message, "stderr", ""),
       has_final: Map.get(message, "has_final", false),
       final_value: Map.get(message, "final_value")
     }}
  end

  defp normalize_message(_type, message), do: {:ok, message}

  defp normalize_task_result({:ok, %{text: text}}), do: %{status: "ok", text: text}

  defp normalize_task_result({:error, message}) when is_binary(message),
    do: %{status: "error", message: message}

  defp normalize_task_result({:error, message}),
    do: %{status: "error", message: inspect(message)}

  defp normalize_task_result(other), do: %{status: "error", message: inspect(other)}

  defp start_llm_query_task(
         %State{shutting_down: true} = state,
         request_id,
         _sub_context,
         _instruction
       ) do
    send_payload(state.port, %{
      type: "llm_result",
      id: request_id,
      result: %{status: "error", message: "Python runtime is shutting down; sub-query aborted."}
    })

    state
  end

  defp start_llm_query_task(state, request_id, sub_context, instruction) do
    case Process.whereis(Rlm.TaskSupervisor) do
      nil ->
        send_payload(state.port, %{
          type: "llm_result",
          id: request_id,
          result: %{
            status: "error",
            message: "Task supervisor is unavailable; sub-query aborted."
          }
        })

        %{state | shutting_down: true}

      _pid ->
        try do
          task =
            Task.Supervisor.async_nolink(Rlm.TaskSupervisor, fn ->
              state.handler.(sub_context, instruction)
            end)

          %{state | task_refs: Map.put(state.task_refs, task.ref, {request_id, task.pid})}
        catch
          :exit, {:noproc, _} ->
            send_payload(state.port, %{
              type: "llm_result",
              id: request_id,
              result: %{
                status: "error",
                message: "Task supervisor exited before sub-query start."
              }
            })

            %{state | shutting_down: true}
        end
    end
  end
end
