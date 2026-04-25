defmodule Rlm.Engine.Execution.Diagnostics do
  @moduledoc false

  def annotate_exec_result(exec_result, block_index, code, total_blocks) do
    details = Map.get(exec_result, :details, %{}) || %{}

    details =
      details
      |> Map.put_new("block_index", block_index)
      |> Map.put_new("block_count", total_blocks)
      |> Map.put_new("block_code", code)

    if exec_result.status == :error do
      %{
        exec_result
        | details:
            Map.put(details, "failed_block_index", block_index)
            |> Map.put("failed_block_code", code)
      }
    else
      %{exec_result | details: details}
    end
  end

  def merge_exec_results(left, right) do
    %{
      stdout: left.stdout <> right.stdout,
      stderr: left.stderr <> right.stderr,
      has_final: left.has_final or right.has_final,
      final_value: right.final_value || left.final_value,
      status: merge_exec_status(left.status, right.status),
      error_kind: right.error_kind || left.error_kind,
      recovery_kind: right.recovery_kind || left.recovery_kind,
      details: Map.merge(left.details || %{}, right.details || %{})
    }
  end

  defp merge_exec_status(:error, _), do: :error
  defp merge_exec_status(_, :error), do: :error
  defp merge_exec_status(:recovered, _), do: :recovered
  defp merge_exec_status(_, :recovered), do: :recovered
  defp merge_exec_status(_, _), do: :ok
end
