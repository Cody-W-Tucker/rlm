defmodule Rlm.Providers.RequestManager.Events do
  @moduledoc false

  alias Rlm.Providers.RequestManager.Error

  def apply_chunk(data, state) do
    next_state = %{state | got_data?: true, buffer: state.buffer <> data}
    parse_events(next_state)
  end

  def parse_events(state) do
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

  def apply_event("", state), do: {:cont, state}

  def apply_event(event, state) do
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

  def next_event(buffer) do
    normalized = String.replace(buffer, "\r\n", "\n")

    case String.split(normalized, "\n\n", parts: 2) do
      [event, rest] -> {:ok, event, rest}
      [_incomplete] -> :more
    end
  end

  def extract_stream_text(%{"choices" => choices}) when is_list(choices) do
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

  def extract_stream_text(_payload), do: ""

  def extract_content_parts(parts) do
    Enum.map_join(parts, "", fn
      %{"text" => text} -> text
      %{"type" => "text", "text" => text} -> text
      _ -> ""
    end)
  end
end
