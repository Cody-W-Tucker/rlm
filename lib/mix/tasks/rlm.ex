defmodule Mix.Tasks.Rlm do
  @moduledoc "Run the RLM CLI."
  use Mix.Task

  @shortdoc "Run the RLM CLI"

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")
    Rlm.CLI.main(args)
  end
end
