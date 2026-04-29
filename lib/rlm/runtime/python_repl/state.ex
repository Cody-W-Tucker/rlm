defmodule Rlm.Runtime.PythonRepl.State do
  @moduledoc false

  defstruct [:port, :buffer, :awaiting, :handler, :task_refs, :received, :shutting_down]
end
