defmodule Rlm.Providers.RequestManager do
  @moduledoc "Streaming request manager for provider calls with liveness-aware deadlines."

  alias Rlm.Providers.RequestManager.Stream
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

    Stream.collect_stream(task, request_ref, started_at, settings, %{
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
end
