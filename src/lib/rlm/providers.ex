defmodule Rlm.Providers do
  @moduledoc "Provider registry helpers."

  alias Rlm.Providers.Mock
  alias Rlm.Providers.OpenAI

  def for(:mock), do: Mock
  def for("mock"), do: Mock
  def for(:openai), do: OpenAI
  def for("openai"), do: OpenAI
  def for(provider), do: raise(ArgumentError, "unsupported provider #{inspect(provider)}")
end
