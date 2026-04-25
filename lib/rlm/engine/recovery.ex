defmodule Rlm.Engine.Recovery do
  @moduledoc "Recovery policy that constrains the next move after a classified failure."

  alias Rlm.Engine.Failure
  alias Rlm.Engine.Recovery.Feedback
  alias Rlm.Engine.Recovery.Strategy

  def allowed?(%Failure{} = failure, run_state, settings, iteration) do
    failure.recoverable and not run_state.recovery_attempted? and
      iteration < settings.max_iterations
  end

  def flags_for(%Failure{class: class}) do
    Strategy.flags_for(%Failure{class: class})
  end

  def feedback(%Failure{} = failure, run_state) do
    Feedback.build(failure, run_state)
  end
end
