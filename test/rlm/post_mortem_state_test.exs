defmodule Rlm.PostMortemStateTest do
  use ExUnit.Case, async: false

  alias Rlm.PostMortem.State
  alias Rlm.TestHelpers

  test "saves and loads checkpoint state with current versions" do
    storage_dir = TestHelpers.temp_dir("rlm-postmortem-state")
    on_exit(fn -> File.rm_rf!(storage_dir) end)

    assert {:ok, state_path} = State.save_processed(storage_dir, "run-20260429151957-8582.json")
    assert File.exists?(state_path)

    assert {:ok, state, ^state_path} = State.load(storage_dir)
    assert state["postmortem_version"] == Rlm.PostMortem.postmortem_version()
    assert state["run_schema_version"] == Rlm.Storage.RunStore.run_schema_version()
    assert get_in(state, ["processing", "last_processed_run"]) == "run-20260429151957-8582.json"
    assert :ok = State.assert_version_match!(state)
  end

  test "raises when checkpoint versions no longer match current versions" do
    stale_state = %{
      "postmortem_version" => 1,
      "run_schema_version" => 0,
      "processing" => %{"last_processed_run" => "run-20260429151957-8582.json"}
    }

    assert_raise RuntimeError, ~r/checkpoint is stale/, fn ->
      State.assert_version_match!(stale_state)
    end
  end
end
