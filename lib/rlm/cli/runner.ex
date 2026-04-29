defmodule Rlm.CLI.Runner do
  @moduledoc false

  alias Rlm.Engine
  alias Rlm.Storage.RunStore

  def run_once(prompt, sources, settings, provider_module, opts \\ []) do
    context_module = Keyword.get(opts, :context_module, Rlm.CLI.Context)

    with {:ok, context_bundle} <- context_module.load_many(sources, settings),
         {:ok, result} <- run_with_bundle(prompt, context_bundle, settings, provider_module, opts) do
      {:ok, result, context_bundle}
    end
  end

  def run_with_bundle(prompt, context_bundle, settings, provider_module, opts \\ []) do
    engine_opts =
      opts
      |> Keyword.take([:on_event])
      |> Keyword.put(:mode, Keyword.get(opts, :mode, :interactive))

    with {:ok, result} <- Engine.run(prompt, context_bundle, settings, provider_module, engine_opts),
         {:ok, _path} <-
           RunStore.persist(result, context_bundle, settings, mode: Keyword.get(opts, :mode, :interactive)) do
      {:ok, result}
    end
  end
end
