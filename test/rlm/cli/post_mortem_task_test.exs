defmodule Rlm.CLI.PostMortemTaskTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  alias Rlm.PostMortem.State
  alias Rlm.TestHelpers

  test "non-incremental task emits JSON for a single run path" do
    storage_dir = TestHelpers.temp_dir("rlm-postmortem-single")
    on_exit(fn -> File.rm_rf!(storage_dir) end)

    run_path = Path.join(storage_dir, "run-20260429151957-1000.json")

    write_run(storage_dir, "run-20260429151957-1000.json", %{
      prompt: "single run prompt",
      recorded_at: "2026-04-29T15:19:57Z"
    })

    Mix.Task.reenable("rlm.post_mortem")

    output =
      capture_io(fn ->
        Mix.Tasks.Rlm.PostMortem.run(["--json", run_path])
      end)

    report = Jason.decode!(output)
    assert report["summary"]["runs_analyzed"] == 1
    assert hd(report["runs"])["prompt"] == "single run prompt"
  end

  test "incremental task only analyzes runs after the checkpoint" do
    storage_dir = TestHelpers.temp_dir("rlm-postmortem-runs")
    on_exit(fn -> File.rm_rf!(storage_dir) end)

    write_run(storage_dir, "run-20260429151957-1000.json", %{prompt: "old prompt", recorded_at: "2026-04-29T15:19:57Z"})

    write_run(storage_dir, "run-20260429151958-1001.json", %{
      prompt: "new prompt",
      recorded_at: "2026-04-29T15:19:58Z",
      failure_history: [
        %{
          class: "total_timeout",
          source: "provider",
          message: "provider exceeded the total request deadline",
          recoverable: true
        }
      ]
    })

    assert {:ok, _state_path} = State.save_processed(storage_dir, "run-20260429151957-1000.json")
    Mix.Task.reenable("rlm.post_mortem")

    output =
      capture_io(fn ->
        Mix.Tasks.Rlm.PostMortem.run(["--json", "--incremental", storage_dir])
      end)

    report = Jason.decode!(output)
    assert report["summary"]["runs_analyzed"] == 1
    assert hd(report["runs"])["prompt"] == "new prompt"

    assert {:ok, state, _path} = State.load(storage_dir)
    assert get_in(state, ["processing", "last_processed_run"]) == "run-20260429151958-1001.json"
  end

  test "incremental task refuses stale checkpoint versions" do
    storage_dir = TestHelpers.temp_dir("rlm-postmortem-stale")
    on_exit(fn -> File.rm_rf!(storage_dir) end)

    state_path = State.path(storage_dir)
    File.mkdir_p!(Path.dirname(state_path))

    File.write!(
      state_path,
      Jason.encode!(%{
        version: 1,
        postmortem_version: 1,
        run_schema_version: 0,
        processing: %{last_processed_run: "run-20260429151957-1000.json"}
      })
    )

    Mix.Task.reenable("rlm.post_mortem")

    assert_raise RuntimeError, ~r/checkpoint is stale/, fn ->
      Mix.Tasks.Rlm.PostMortem.run(["--incremental", storage_dir])
    end
  end

  defp write_run(storage_dir, file_name, overrides) do
    payload =
      Map.merge(
        %{
          run_schema_version: Rlm.Storage.RunStore.run_schema_version(),
          status: "completed",
          completed: true,
          prompt: "prompt",
          answer: "answer",
          iterations: 1,
          total_sub_queries: 0,
          input_tokens: 0,
          output_tokens: 0,
          depth: 0,
          best_answer_reason: "final_value",
          grounding: %{grade: "A", metrics: %{search_count: 0, read_files: 3}},
          recovery_flags: %{},
          failure_history: [],
          last_successful_subquery: nil,
          last_successful_subquery_result: nil,
          mode: "cli",
          context_sources: [],
          context_bytes: 0,
          context_lazy_bytes: 0,
          recorded_at: "2026-04-29T15:19:57Z",
          iteration_records: []
        },
        overrides
      )

    File.write!(Path.join(storage_dir, file_name), Jason.encode!(payload, pretty: true))
  end
end
