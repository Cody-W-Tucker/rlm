defmodule Rlm.Context.Entry do
  @moduledoc "A single loaded context source."

  @enforce_keys [:id, :type, :label, :text, :bytes]
  defstruct [:id, :type, :label, :text, :bytes, metadata: %{}]
end
