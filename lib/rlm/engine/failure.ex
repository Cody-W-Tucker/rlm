defmodule Rlm.Engine.Failure do
  @moduledoc "Structured failure classification for provider, runtime, and budget errors."

  alias Rlm.Providers.RequestManager

  defstruct [:class, :source, :message, :recoverable, :advice]

  @type t :: %__MODULE__{}

  def from_stage(stage, reason) do
    case reason do
      %RequestManager.Error{} = error ->
        build(error.class, stage_source(stage), error.message, true)

      _ ->
        message = normalize_reason(reason)

        case stage do
          :startup -> build(:runtime_shutdown, :startup, message, false)
          :provider -> classify_provider(message)
          :subquery -> classify_subquery(message)
          :response_format -> build(:provider_response_error, :response_format, message, true)
          :runtime -> classify_runtime(message)
        end
    end
  end

  def from_exec_result(exec_result) do
    status = Map.get(exec_result, :status, :ok)
    error_kind = Map.get(exec_result, :error_kind)
    stderr = String.trim(exec_result.stderr || "")

    cond do
      status == :error and is_atom(error_kind) ->
        classify_runtime_exec(exec_result)

      stderr == "" ->
        nil

      String.contains?(stderr, "SubqueryError") ->
        classify_subquery(stderr)

      String.contains?(stderr, "Traceback") ->
        classify_runtime(stderr)

      true ->
        nil
    end
  end

  defp classify_runtime_exec(exec_result) do
    message =
      exec_result.stderr
      |> to_string()
      |> String.trim()
      |> case do
        "" -> format_runtime_exec_message(exec_result)
        stderr -> stderr
      end

    case exec_result.error_kind do
      :subquery_error ->
        classify_subquery(message)

      :async_wrapper_syntax_error ->
        build(:async_failed, :runtime, message, true)

      :syntax_unterminated_triple_quote ->
        build(:runtime_finalization_error, :runtime, message, true)

      :syntax_error ->
        build(:runtime_syntax_error, :runtime, message, true)

      :runtime_exception ->
        classify_runtime(message)

      _ ->
        classify_runtime(message)
    end
  end

  def diagnosis(%__MODULE__{advice: advice}), do: advice

  def status(%__MODULE__{class: class}), do: class

  defp classify_provider(message) do
    cond do
      timeout_message?(message) ->
        build(:provider_timeout, :provider, message, true)

      String.contains?(message, "HTTP 429") or String.contains?(message, "HTTP 500") or
        String.contains?(message, "HTTP 502") or String.contains?(message, "HTTP 503") ->
        build(:provider_unavailable, :provider, message, true)

      true ->
        build(:provider_error, :provider, message, true)
    end
  end

  defp classify_subquery(message) do
    cond do
      String.contains?(message, "Maximum sub-query limit") ->
        build(:subquery_budget_exhausted, :subquery, message, true)

      timeout_message?(message) ->
        build(:provider_timeout, :subquery, message, true)

      String.contains?(message, "Task supervisor") or String.contains?(message, "shutting down") ->
        build(:runtime_shutdown, :subquery, message, true)

      true ->
        build(:subquery_failed, :subquery, message, true)
    end
  end

  defp classify_runtime(message) do
    cond do
      String.contains?(message, "Task supervisor") or String.contains?(message, "shutting down") or
          String.contains?(message, "exited with status") ->
        build(:runtime_shutdown, :runtime, message, true)

      String.contains?(message, "SyntaxError") and String.contains?(message, "```") ->
        build(:python_exec_error, :runtime, message, true)

      String.contains?(message, "async") or String.contains?(message, "AwaitableString") ->
        build(:async_failed, :runtime, message, true)

      true ->
        build(:python_exec_error, :runtime, message, true)
    end
  end

  defp format_runtime_exec_message(exec_result) do
    detail_message =
      get_in(exec_result, [:details, "message"]) || get_in(exec_result, [:details, :message])

    base =
      case exec_result.error_kind do
        nil -> "Runtime execution failed."
        kind -> "Runtime execution failed with #{kind}."
      end

    if is_binary(detail_message) and detail_message != "" do
      base <> " " <> detail_message
    else
      base
    end
  end

  defp build(class, source, message, recoverable) do
    %__MODULE__{
      class: class,
      source: source,
      message: message,
      recoverable: recoverable,
      advice: advice_for(class)
    }
  end

  defp advice_for(:provider_timeout),
    do: "the provider timed out. Retry with a narrower question or a simpler strategy."

  defp advice_for(:first_byte_timeout),
    do:
      "the provider never started responding before the first-byte deadline. Retry with a simpler or narrower request."

  defp advice_for(:idle_timeout),
    do:
      "the provider started responding but then went silent too long. Reuse any partial answer and switch to a simpler strategy."

  defp advice_for(:total_timeout),
    do:
      "the provider exceeded the total request deadline. Finalize from the best partial answer already collected."

  defp advice_for(:connect_error),
    do:
      "the provider connection failed before a response could start. Retry after checking provider availability."

  defp advice_for(:provider_http_error),
    do:
      "the provider returned an HTTP error response. Retry or inspect provider availability and credentials."

  defp advice_for(:provider_unavailable),
    do: "the provider was temporarily unavailable. Retry after a short delay."

  defp advice_for(:provider_response_error),
    do:
      "the provider returned a response the runtime could not execute. Retry the run or adjust the provider configuration."

  defp advice_for(:subquery_budget_exhausted),
    do: "the run exhausted its sub-query budget. Finalize from the best answer collected so far."

  defp advice_for(:runtime_shutdown),
    do:
      "the runtime became unavailable during execution. Retry the run; if it persists, inspect the runtime startup path."

  defp advice_for(:async_failed),
    do:
      "the async strategy failed. Fall back to direct reasoning or one narrow sequential sub-query."

  defp advice_for(:runtime_finalization_error),
    do:
      "the finalization step was malformed. Reuse the best available answer text and emit a simpler FINAL() call."

  defp advice_for(:runtime_syntax_error),
    do:
      "the generated Python had a syntax problem before it could run. Simplify the code and avoid repeating the same structure."

  defp advice_for(:python_exec_error),
    do:
      "the generated Python failed during execution. Simplify the code path and avoid repeating the same pattern."

  defp advice_for(:subquery_failed),
    do:
      "a sub-query failed. Use a narrower question or finalize from the best evidence already collected."

  defp advice_for(:provider_error),
    do: "the provider failed before the run could complete. Retry with a simpler strategy."

  defp normalize_reason(reason) when is_binary(reason), do: reason
  defp normalize_reason(reason), do: inspect(reason)

  defp stage_source(:provider), do: :provider
  defp stage_source(:subquery), do: :subquery
  defp stage_source(:response_format), do: :response_format
  defp stage_source(:runtime), do: :runtime
  defp stage_source(:startup), do: :startup

  defp timeout_message?(message) do
    String.contains?(message, ["timeout", ":timeout", "timed out"])
  end
end
