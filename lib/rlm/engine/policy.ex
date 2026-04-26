defmodule Rlm.Engine.Policy do
  @moduledoc "Prompt and iteration policy for the RLM engine."

  alias Rlm.Engine.Prompt

  def context_metadata(context_bundle, settings, prompt),
    do: Prompt.context_metadata(context_bundle, settings, prompt)

  def system_prompt(settings, iteration, run_state),
    do: Prompt.system_prompt(settings, iteration, run_state)

  def iteration_feedback(exec_result, settings, iteration, run_state, context_bundle),
    do: Prompt.iteration_feedback(exec_result, settings, iteration, run_state, context_bundle)
end
