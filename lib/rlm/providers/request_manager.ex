defmodule Rlm.Providers.RequestManager do
  @moduledoc "Streaming request manager for provider calls with liveness-aware deadlines."

  alias Rlm.Settings

  defmodule Error do
    @moduledoc false

    defstruct [:class, :message, partial_text: ""]

    @type t :: %__MODULE__{class: atom(), message: String.t(), partial_text: String.t()}
  end

  def request_openai_chat(url, headers, body, %Settings{} = settings, request_fun \\ &Req.post/2) do
    started_at = System.monotonic_time(:millisecond)
    request_ref = make_ref()
    parent = self()

    task =
      Task.Supervisor.async_nolink(Rlm.TaskSupervisor, fn ->
        request_fun.(url,
          headers: headers,
          json: Map.put(body, :stream, true),
          raw: true,
          retry: false,
          receive_timeout: max(settings.first_byte_timeout, settings.idle_timeout),
          connect_options: [timeout: settings.connect_timeout],
          into: fn {:data, data}, {req, resp} ->
            send(parent, {:provider_stream_chunk, request_ref, IO.iodata_to_binary(data)})
            {:cont, {req, resp}}
          end
        )
      end)

    collect_stream(task, request_ref, started_at, settings, %{
      buffer: "",
      text: "",
      got_data?: false
    })
  end

  def format_error_for_runtime(%Error{class: class, message: message, partial_text: partial_text}) do
    suffix =
      if String.trim(partial_text) == "" do
        ""
      else
        " Partial output was retained for recovery."
      end

    "#{class}: #{message}.#{suffix}"
  end

  defp collect_stream(task, request_ref, started_at, settings, state) do
    timeout = next_timeout(state, started_at, settings)

    receive do
      {:provider_stream_chunk, ^request_ref, data} ->
        case apply_chunk(data, state) do
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
          classify_transport_error(error, default_timeout_class(state), state.text)
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
        class = timeout_class(started_at, settings, state)

        shutdown_with_error(
          task,
          request_ref,
          %Error{class: class, message: timeout_message(class), partial_text: state.text}
        )
    end
  end

  defp finish_success(task, request_ref, state) do
    Process.demonitor(task.ref, [:flush])
    flush_task_messages(task.ref, request_ref)
    {:ok, %{text: state.text, raw: state.text}}
  end

  defp shutdown_with_error(task, request_ref, error) do
    Task.shutdown(task, :brutal_kill)
    Process.demonitor(task.ref, [:flush])
    flush_task_messages(task.ref, request_ref)
    {:error, error}
  end

  defp flush_task_messages(task_ref, request_ref) do
    receive do
      {^task_ref, _result} -> flush_task_messages(task_ref, request_ref)
      {:DOWN, ^task_ref, :process, _pid, _reason} -> flush_task_messages(task_ref, request_ref)
      {:provider_stream_chunk, ^request_ref, _data} -> flush_task_messages(task_ref, request_ref)
    after
      0 -> :ok
    end
  end

  defp apply_chunk(data, state) do
    next_state = %{state | got_data?: true, buffer: state.buffer <> data}
    parse_events(next_state)
  end

  defp parse_events(state) do
    case next_event(state.buffer) do
      {:ok, event, rest} ->
        case apply_event(event, %{state | buffer: rest}) do
          {:cont, next_state} -> parse_events(next_state)
          other -> other
        end

      :more ->
        {:cont, state}
    end
  end

  defp apply_event("", state), do: {:cont, state}

  defp apply_event(event, state) do
    data =
      event
      |> String.split("\n")
      |> Enum.map(&String.trim_trailing(&1, "\r"))
      |> Enum.filter(&String.starts_with?(&1, "data:"))
      |> Enum.map_join("\n", &(String.trim_leading(&1, "data:") |> String.trim_leading()))

    cond do
      data == "" ->
        {:cont, state}

      data == "[DONE]" ->
        {:done, state}

      true ->
        case Jason.decode(data) do
          {:ok, payload} ->
            {:cont, %{state | text: state.text <> extract_stream_text(payload)}}

          {:error, reason} ->
            {:error,
             %Error{
               class: :provider_response_error,
               message: "invalid streamed JSON: #{inspect(reason)}",
               partial_text: state.text
             }}
        end
    end
  end

  defp next_event(buffer) do
    normalized = String.replace(buffer, "\r\n", "\n")

    case String.split(normalized, "\n\n", parts: 2) do
      [event, rest] -> {:ok, event, rest}
      [_incomplete] -> :more
    end
  end

  defp extract_stream_text(%{"choices" => choices}) when is_list(choices) do
    Enum.map_join(choices, "", fn
      %{"delta" => %{"content" => content}} when is_binary(content) ->
        content

      %{"delta" => %{"content" => content}} when is_list(content) ->
        extract_content_parts(content)

      %{"message" => %{"content" => content}} when is_binary(content) ->
        content

      %{"message" => %{"content" => content}} when is_list(content) ->
        extract_content_parts(content)

      _ ->
        ""
    end)
  end

  defp extract_stream_text(_payload), do: ""

  defp extract_content_parts(parts) do
    Enum.map_join(parts, "", fn
      %{"text" => text} -> text
      %{"type" => "text", "text" => text} -> text
      _ -> ""
    end)
  end

  defp classify_transport_error(
         %Req.TransportError{reason: :timeout},
         fallback_class,
         partial_text
       ) do
    %Error{
      class: fallback_class,
      message: "%Req.TransportError{reason: :timeout}",
      partial_text: partial_text
    }
  end

  defp classify_transport_error(%Req.TransportError{} = error, fallback_class, partial_text) do
    class = if fallback_class == :first_byte_timeout, do: :connect_error, else: :provider_error
    %Error{class: class, message: inspect(error), partial_text: partial_text}
  end

  defp next_timeout(state, started_at, settings) do
    elapsed = System.monotonic_time(:millisecond) - started_at
    remaining_total = max(1, settings.total_timeout - elapsed)
    preferred = if state.got_data?, do: settings.idle_timeout, else: settings.first_byte_timeout
    max(1, min(preferred, remaining_total))
  end

  defp timeout_class(started_at, settings, state) do
    elapsed = System.monotonic_time(:millisecond) - started_at

    if elapsed >= settings.total_timeout do
      :total_timeout
    else
      default_timeout_class(state)
    end
  end

  defp default_timeout_class(state) do
    if state.got_data?, do: :idle_timeout, else: :first_byte_timeout
  end

  defp timeout_message(:first_byte_timeout),
    do: "provider did not produce response bytes before the first-byte deadline"

  defp timeout_message(:idle_timeout),
    do: "provider stream went silent past the idle timeout"

  defp timeout_message(:total_timeout),
    do: "provider exceeded the total request deadline"
end
