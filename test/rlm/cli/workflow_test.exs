defmodule Rlm.CLI.WorkflowTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  alias Rlm.CLI
  alias Rlm.TestHelpers

  test "cli workflow prints a final answer" do
    output =
      capture_io(fn ->
        assert :ok =
                 CLI.dispatch([
                   "--provider",
                   "mock",
                   "--text",
                   "workflow context",
                   "what is loaded?"
                 ])
      end)

    assert output =~ "Observed context"
    assert output =~ "workflow context"
  end

  test "cli loads file context" do
    tmp = TestHelpers.temp_dir("rlm-session")
    on_exit(fn -> File.rm_rf!(tmp) end)

    file_path = Path.join(tmp, "context.txt")
    File.write!(file_path, "session context")

    output =
      capture_io(fn ->
        assert :ok = CLI.dispatch(["--provider", "mock", "--file", file_path, "What is loaded?"])
      end)

    assert output =~ "Observed file context"
    assert output =~ "session context"
  end

  test "verbose cli prints iteration step descriptions" do
    stderr =
      capture_io(:stderr, fn ->
        assert :ok =
                 CLI.dispatch([
                   "--provider",
                   "mock",
                   "--verbose",
                   "--text",
                   "workflow context",
                   "what is loaded?"
                 ])
      end)

    assert stderr =~ "iteration 1: what is loaded?"
    assert stderr =~ "iteration 1 stdout:"
    assert stderr =~ "workflow context"
  end
end
