defmodule Rlm.Engine do
  @moduledoc "RLM orchestration loop over a persistent Python REPL."

  alias Rlm.Engine.Failure
  alias Rlm.Engine.Finalizer
  alias Rlm.Engine.Iteration
  alias Rlm.Engine.RunState
  alias Rlm.Runtime.PythonRepl
  alias Rlm.Settings

  def run(prompt, context_bundle, %Settings{} = settings, provider_module, opts \\ []) do
    {:ok, run_state} = RunState.start_link()

    result =
      case PythonRepl.start(settings, opts) do
        {:ok, repl} ->
          run_with_repl(prompt, context_bundle, settings, provider_module, repl, run_state, opts)

        {:error, reason} ->
          {:ok,
           Finalizer.error_result(
             prompt,
             context_bundle,
             Failure.from_stage(:startup, reason),
             run_state
           )}
      end

    RunState.stop(run_state)
    result
  end

  defp run_with_repl(prompt, context_bundle, settings, provider_module, repl, run_state, opts) do
    file_sources =
      context_bundle
      |> Map.get(:lazy_entries, [])
      |> Enum.map(& &1.label)

    try do
      with :ok <-
             PythonRepl.set_handler(
               repl,
               Iteration.llm_query_handler(provider_module, settings, run_state)
             ),
           :ok <- PythonRepl.set_context(repl, context_bundle.text),
           :ok <- PythonRepl.set_file_sources(repl, file_sources),
           :ok <- PythonRepl.reset_final(repl) do
        Iteration.run(prompt, context_bundle, settings, provider_module, repl, run_state, opts)
      else
        {:error, reason} ->
          {:ok,
           Finalizer.error_result(
             prompt,
             context_bundle,
             Failure.from_stage(:startup, reason),
             run_state
           )}
      end
    after
      PythonRepl.stop(repl)
    end
  end
end
