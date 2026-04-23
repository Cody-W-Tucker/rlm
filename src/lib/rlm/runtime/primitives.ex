defmodule Rlm.Runtime.Primitives do
  @moduledoc "Helpers for inspecting context and executing normalized runtime actions."

  alias Rlm.RLM.Settings

  def preview(text, lines) do
    split = String.split(text, "\n")

    %{
      first: Enum.take(split, lines),
      last: Enum.take(split, -lines),
      lines: length(split),
      chars: String.length(text)
    }
  end

  def slice_context(text, start, length, %Settings{} = settings) do
    safe_start = max(start || 0, 0)
    safe_length = min(length || settings.max_slice_chars, settings.max_slice_chars)
    excerpt = text |> String.slice(safe_start, safe_length) |> Kernel.||("")

    %{
      start: safe_start,
      length: safe_length,
      excerpt: excerpt
    }
  end

  def execute_actions(actions, context_text, settings, opts) do
    state = %{observations: [], action_results: [], final_answer: nil}

    Enum.reduce_while(actions, {:ok, state}, fn action, {:ok, acc} ->
      case execute_action(action, context_text, settings, opts) do
        {:ok, result, :continue} ->
          next = %{
            acc
            | observations: acc.observations ++ result.observations,
              action_results: acc.action_results ++ [result.event]
          }

          {:cont, {:ok, next}}

        {:ok, result, :halt} ->
          next = %{
            acc
            | observations: acc.observations ++ result.observations,
              action_results: acc.action_results ++ [result.event],
              final_answer: result.final_answer
          }

          {:halt, {:ok, next}}

        {:error, _} = error ->
          {:halt, error}
      end
    end)
  end

  defp execute_action(%{"type" => "inspect_context"} = action, context_text, settings, opts) do
    slice = slice_context(context_text, action["start"], action["length"], settings)
    label = Map.get(action, "label", "context")

    event = %{
      type: :inspect_context,
      label: label,
      excerpt: slice.excerpt,
      start: slice.start,
      length: slice.length
    }

    emit(opts[:on_event], event)

    observation = %{
      kind: "inspect_context",
      label: label,
      excerpt: slice.excerpt,
      start: slice.start,
      length: slice.length
    }

    {:ok, %{event: event, observations: [observation], final_answer: nil}, :continue}
  end

  defp execute_action(
         %{"type" => "emit_progress", "message" => message},
         _context_text,
         _settings,
         opts
       ) do
    event = %{type: :emit_progress, message: message}
    emit(opts[:on_event], event)

    {:ok,
     %{
       event: event,
       observations: [%{kind: "emit_progress", message: message}],
       final_answer: nil
     }, :continue}
  end

  defp execute_action(
         %{"type" => "sub_query", "prompt" => prompt} = action,
         context_text,
         settings,
         opts
       ) do
    label = Map.get(action, "label", "sub-query")

    sub_context =
      cond do
        is_binary(action["context"]) -> action["context"]
        true -> slice_context(context_text, action["start"], action["length"], settings).excerpt
      end

    emit(opts[:on_event], %{type: :sub_query_start, label: label, prompt: prompt})

    case opts[:run_sub_query].(prompt, sub_context, label) do
      {:ok, result} ->
        event = %{
          type: :sub_query_complete,
          label: label,
          status: result.status,
          answer: result.answer
        }

        emit(opts[:on_event], event)

        observation = %{
          kind: "sub_query",
          label: label,
          prompt: prompt,
          answer: result.answer,
          status: result.status,
          iterations: result.iterations,
          total_sub_queries: result.total_sub_queries
        }

        {:ok, %{event: event, observations: [observation], final_answer: nil}, :continue}

      {:error, _} = error ->
        error
    end
  end

  defp execute_action(
         %{"type" => "final_answer", "answer" => answer},
         _context_text,
         _settings,
         opts
       ) do
    event = %{type: :final_answer, answer: answer}
    emit(opts[:on_event], event)

    {:ok,
     %{
       event: event,
       observations: [%{kind: "final_answer", answer: answer}],
       final_answer: answer
     }, :halt}
  end

  defp execute_action(action, _context_text, _settings, _opts) do
    {:error, "unsupported runtime action #{inspect(action)}"}
  end

  defp emit(nil, _event), do: :ok
  defp emit(fun, event), do: fun.(event)
end
