defmodule Rlm.Engine.Execution.BlockRunner do
  @moduledoc false

  alias Rlm.Engine.Execution.Diagnostics
  alias Rlm.Runtime.PythonRepl

  def execute_code_blocks(repl, code_blocks) do
    total_blocks = length(code_blocks)

    case code_blocks do
      [first | rest] ->
        with {:ok, initial_result} <- PythonRepl.execute(repl, first) do
          initial_result =
            Diagnostics.annotate_exec_result(initial_result, 1, first, total_blocks)

          continue_code_blocks(repl, rest, initial_result, 2, total_blocks)
        end

      [] ->
        {:error, "No code blocks to execute."}
    end
  end

  defp continue_code_blocks(_repl, [], exec_result, _index, _total_blocks), do: {:ok, exec_result}

  defp continue_code_blocks(_repl, _remaining, exec_result, _index, _total_blocks)
       when exec_result.has_final or exec_result.status == :error do
    {:ok, exec_result}
  end

  defp continue_code_blocks(repl, [code | rest], aggregate, index, total_blocks) do
    case PythonRepl.execute(repl, code) do
      {:ok, next_result} ->
        next_result = Diagnostics.annotate_exec_result(next_result, index, code, total_blocks)
        merged = Diagnostics.merge_exec_results(aggregate, next_result)

        if merged.has_final or merged.status == :error do
          {:ok, merged}
        else
          continue_code_blocks(repl, rest, merged, index + 1, total_blocks)
        end

      {:error, reason} ->
        {:error, reason}
    end
  end
end
