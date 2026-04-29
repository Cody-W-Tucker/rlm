defmodule Rlm.Runtime.PythonRepl.Protocol do
  @moduledoc false

  alias Rlm.Runtime.PythonRepl.State

  def process_packet(packet, %State{} = state, start_llm_query_task) when is_binary(packet) do
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
          start_llm_query_task.(acc, request_id, sub_context, instruction)

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

  def split_lines(data) do
    parts = :binary.split(data, "\n", [:global])
    buffer = List.last(parts) || ""
    complete = parts |> Enum.drop(-1) |> Enum.reject(&(&1 == ""))
    {complete, buffer}
  end

  def normalize_message("ready", _message), do: :ok
  def normalize_message("context_set", _message), do: :ok
  def normalize_message("file_sources_set", _message), do: :ok
  def normalize_message("final_reset", _message), do: :ok

  def normalize_message("exec_done", message) do
    {:ok,
     %{
       stdout: Map.get(message, "stdout", ""),
       stderr: Map.get(message, "stderr", ""),
       has_final: Map.get(message, "has_final", false),
       final_value: Map.get(message, "final_value"),
       status: normalize_exec_status(Map.get(message, "status")),
       error_kind: normalize_exec_kind(Map.get(message, "error_kind")),
       recovery_kind: normalize_exec_kind(Map.get(message, "recovery_kind")),
       details: Map.get(message, "details", %{})
     }}
  end

  def normalize_message(_type, message), do: {:ok, message}

  def normalize_exec_status("recovered"), do: :recovered
  def normalize_exec_status("error"), do: :error
  def normalize_exec_status(_), do: :ok

  def normalize_exec_kind(nil), do: nil

  def normalize_exec_kind(kind) when is_binary(kind) do
    kind
    |> String.replace("-", "_")
    |> String.to_atom()
  end

  def normalize_exec_kind(kind), do: kind
end
