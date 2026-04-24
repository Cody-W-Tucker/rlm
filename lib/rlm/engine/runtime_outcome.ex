defmodule Rlm.Engine.RuntimeOutcome do
  @moduledoc "Classifies Python runtime results before policy decides what to do next."

  alias Rlm.Engine.Failure

  def classify(exec_result) do
    cond do
      exec_result.has_final and is_binary(exec_result.final_value) and
          String.trim(exec_result.final_value) != "" ->
        {:finalized, String.trim(exec_result.final_value)}

      failure = Failure.from_exec_result(exec_result) ->
        if failure.recoverable do
          {:recoverable_failure, failure}
        else
          {:unrecoverable_failure, failure}
        end

      true ->
        :continue
    end
  end
end
