defmodule Rlm.Engine.Prompt.RecoveryConstraints do
  @moduledoc false

  def build(recovery_flags) do
    [
      if(recovery_flags.recovery_mode,
        do:
          "- Recovery mode is active. Prefer direct reasoning or one narrow sub-query. If you have already searched or read, call `assess_evidence()` to choose the next best move before deciding whether to read more or finalize.",
        else: nil
      ),
      if(recovery_flags.async_disabled,
        do: "- Async is disabled for this run because a previous async-style attempt failed.",
        else: nil
      ),
      if(recovery_flags.broad_subqueries_disabled,
        do:
          "- Broad chunking and parallel fan-out are disabled for this run because a previous broad strategy failed.",
        else: nil
      )
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.join("\n")
  end
end
