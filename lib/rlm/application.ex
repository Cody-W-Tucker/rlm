defmodule Rlm.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      {Finch, name: Rlm.Finch},
      {Task.Supervisor, name: Rlm.TaskSupervisor}
    ]

    opts = [strategy: :one_for_one, name: Rlm.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
