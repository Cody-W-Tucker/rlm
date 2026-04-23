defmodule Rlm.TestHelpers do
  alias Rlm.RLM.Settings

  def temp_dir(prefix \\ "rlm-test") do
    path = Path.join(System.tmp_dir!(), "#{prefix}-#{System.unique_integer([:positive])}")
    File.mkdir_p!(path)
    path
  end

  def settings(overrides \\ %{}) do
    storage_dir = Map.get(overrides, :storage_dir, temp_dir("rlm-runs"))

    runtime_command =
      Map.get(overrides, :runtime_command, [System.find_executable("python3") || "python3"])

    {:ok, settings} =
      Settings.load(
        Map.merge(
          %{provider: :mock, storage_dir: storage_dir, runtime_command: runtime_command},
          overrides
        )
      )

    settings
  end
end
