defmodule Rlm.Providers.RequestManager.Stream do
  @moduledoc false

  alias Rlm.Providers.RequestManager.Error
  alias Rlm.Providers.RequestManager.Events
  alias Rlm.Providers.RequestManager.Timeouts

  def collect_stream(task, request_ref, started_at, settings, state) do
    timeout = Timeouts.next_timeout(state, started_at, settings)

    receive do
      {:provider_stream_chunk, ^request_ref, data} ->
        case Events.apply_chunk(data, state) do
          {:cont, next_state} ->
            collect_stream(task, request_ref, started_at, settings, next_state)

          {:done, next_state} ->
            finish_success(task, request_ref, next_state)

          {:error, error} ->
            shutdown_with_error(task, request_ref, error)
        end

      {task_ref, {:ok, %Req.Response{status: status}}}
      when task_ref == task.ref and status in 200..299 ->
        finish_success(task, request_ref, state)

      {task_ref, {:ok, %Req.Response{status: status}}} when task_ref == task.ref ->
        shutdown_with_error(
          task,
          request_ref,
          %Error{
            class: :provider_http_error,
            message: "provider request failed with HTTP #{status}",
            partial_text: state.text
          }
        )

      {task_ref, {:error, %Req.TransportError{} = error}} when task_ref == task.ref ->
        shutdown_with_error(
          task,
          request_ref,
          Timeouts.classify_transport_error(error, Timeouts.default_timeout_class(state), state.text)
        )

      {task_ref, {:error, reason}} when task_ref == task.ref ->
        shutdown_with_error(task, request_ref, %Error{
          class: :provider_error,
          message: inspect(reason),
          partial_text: state.text
        })

      {:DOWN, task_ref, :process, _pid, :normal} when task_ref == task.ref ->
        finish_success(task, request_ref, state)

      {:DOWN, task_ref, :process, _pid, reason} when task_ref == task.ref ->
        shutdown_with_error(task, request_ref, %Error{
          class: :provider_error,
          message: inspect(reason),
          partial_text: state.text
        })
    after
      timeout ->
        class = Timeouts.timeout_class(started_at, settings, state)

        shutdown_with_error(
          task,
          request_ref,
          %Error{class: class, message: Timeouts.timeout_message(class), partial_text: state.text}
        )
    end
  end

  def finish_success(task, request_ref, state) do
    Process.demonitor(task.ref, [:flush])
    flush_task_messages(task.ref, request_ref)
    {:ok, %{text: state.text, raw: state.text}}
  end

  def shutdown_with_error(task, request_ref, error) do
    Task.shutdown(task, :brutal_kill)
    Process.demonitor(task.ref, [:flush])
    flush_task_messages(task.ref, request_ref)
    {:error, error}
  end

  def flush_task_messages(task_ref, request_ref) do
    receive do
      {^task_ref, _result} -> flush_task_messages(task_ref, request_ref)
      {:DOWN, ^task_ref, :process, _pid, _reason} -> flush_task_messages(task_ref, request_ref)
      {:provider_stream_chunk, ^request_ref, _data} -> flush_task_messages(task_ref, request_ref)
    after
      0 -> :ok
    end
  end
end
