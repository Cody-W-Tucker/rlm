defmodule Rlm.Runtime.PythonRepl.SubqueryTasks do
  @moduledoc false

  alias Rlm.Runtime.PythonRepl.RuntimePort
  alias Rlm.Runtime.PythonRepl.State

  def handle_task_result(ref, result, %State{} = state) do
    case Map.pop(state.task_refs, ref) do
      {{request_id, _pid}, task_refs} ->
        Process.demonitor(ref, [:flush])

        RuntimePort.send_payload(state.port, %{
          type: "llm_result",
          id: request_id,
          result: normalize_task_result(result)
        })

        {:noreply, %{state | task_refs: task_refs}}

      {nil, _task_refs} ->
        {:noreply, state}
    end
  end

  def handle_task_down(ref, reason, %State{} = state) do
    case Map.pop(state.task_refs, ref) do
      {{request_id, _pid}, task_refs} ->
        RuntimePort.send_payload(state.port, %{
          type: "llm_result",
          id: request_id,
          result: "[ERROR] LLM query failed: #{inspect(reason)}"
        })

        {:noreply, %{state | task_refs: task_refs}}

      {nil, _task_refs} ->
        {:noreply, state}
    end
  end

  def start_llm_query_task(%State{shutting_down: true} = state, request_id, _sub_context, _instruction) do
    RuntimePort.send_payload(state.port, %{
      type: "llm_result",
      id: request_id,
      result: %{status: "error", message: "Python runtime is shutting down; sub-query aborted."}
    })

    state
  end

  def start_llm_query_task(%State{} = state, request_id, sub_context, instruction) do
    case Process.whereis(Rlm.TaskSupervisor) do
      nil ->
        RuntimePort.send_payload(state.port, %{
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
            RuntimePort.send_payload(state.port, %{
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

  def normalize_task_result({:ok, %{text: text}}), do: %{status: "ok", text: text}

  def normalize_task_result({:error, message}) when is_binary(message),
    do: %{status: "error", message: message}

  def normalize_task_result({:error, message}),
    do: %{status: "error", message: inspect(message)}

  def normalize_task_result(other), do: %{status: "error", message: inspect(other)}
end
