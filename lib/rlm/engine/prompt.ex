defmodule Rlm.Engine.Prompt do
  @moduledoc false

  alias Rlm.Engine.Prompt.Base
  alias Rlm.Engine.Prompt.ContextStrategy
  alias Rlm.Engine.Prompt.IterationFeedback
  alias Rlm.Engine.Prompt.RecoveryConstraints

  def context_metadata(context_bundle, _settings, prompt) do
    ContextStrategy.context_metadata(context_bundle, prompt)
  end

  def system_prompt(settings, iteration, run_state) do
    strategy_constraints = RecoveryConstraints.build(run_state.recovery_flags)
    Base.system_prompt(settings, iteration, run_state, strategy_constraints)
  end

  def iteration_feedback(exec_result, settings, iteration, run_state) do
    IterationFeedback.build(exec_result, settings, iteration, run_state)
  end
end
