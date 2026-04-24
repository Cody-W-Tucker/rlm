defmodule Rlm.Providers.Provider do
  @moduledoc "Behavior for model providers used by the RLM loop."

  alias Rlm.Settings

  @type completion :: %{
          required(:text) => String.t(),
          optional(:input_tokens) => non_neg_integer(),
          optional(:output_tokens) => non_neg_integer(),
          optional(:raw) => String.t()
        }

  @callback generate_code([map()], String.t(), Settings.t()) ::
              {:ok, completion()} | {:error, term()}
  @callback complete_subquery(String.t(), String.t(), Settings.t()) ::
              {:ok, completion()} | {:error, term()}
end
