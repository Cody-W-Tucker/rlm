defmodule Rlm.Runtime.PythonRepl do
  @moduledoc "Persistent Python runtime for model-authored code execution."

  use GenServer

  alias Rlm.Runtime.PythonRepl.Protocol
  alias Rlm.Runtime.PythonRepl.RuntimePort
  alias Rlm.Runtime.PythonRepl.State
  alias Rlm.Runtime.PythonRepl.SubqueryTasks

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

  def set_file_sources(pid, paths),
    do:
      GenServer.call(
        pid,
        {:await, "file_sources_set", %{type: "set_file_sources", paths: paths}},
        :infinity
      )

  def reset_final(pid),
    do: GenServer.call(pid, {:await, "final_reset", %{type: "reset_final"}}, :infinity)

  def execute(pid, code),
    do: GenServer.call(pid, {:await, "exec_done", %{type: "exec", code: code}}, :infinity)

  def await_ready(pid), do: GenServer.call(pid, {:await_existing, "ready"}, :infinity)
  def stop(pid), do: GenServer.stop(pid, :normal)

  @impl true
  def init({settings, opts}) do
    port = RuntimePort.open(settings, opts)

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
    RuntimePort.send_payload(state.port, payload)
    {:noreply, put_in(state.awaiting[type], from)}
  end

  @impl true
  def handle_info({port, {:data, packet}}, %State{port: port} = state) do
    state = Protocol.process_packet(packet, state, &SubqueryTasks.start_llm_query_task/4)
    {:noreply, state}
  end

  def handle_info({ref, result}, state) when is_reference(ref) do
    SubqueryTasks.handle_task_result(ref, result, state)
  end

  def handle_info({:DOWN, ref, :process, _pid, reason}, state) do
    SubqueryTasks.handle_task_down(ref, reason, state)
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
      RuntimePort.send_payload(state.port, %{type: "shutdown"})
      Port.close(state.port)
    end

    :ok
  end
end
