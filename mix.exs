defmodule Rlm.MixProject do
  use Mix.Project

  def project do
    [
      app: :rlm,
      version: "0.1.0",
      elixir: "~> 1.17",
      elixirc_paths: elixirc_paths(Mix.env()),
      escript: [main_module: Rlm.CLI],
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger, :inets, :ssl],
      mod: {Rlm.Application, []}
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:jason, "~> 1.4"},
      {:nimble_options, "~> 1.1"},
      {:req, "~> 0.5"},
      {:bypass, "~> 2.1", only: :test},
      {:mox, "~> 1.2", only: :test}
    ]
  end
end
