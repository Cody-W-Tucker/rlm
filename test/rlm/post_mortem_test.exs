defmodule Rlm.PostMortemTest do
  use ExUnit.Case, async: true

  alias Rlm.PostMortem
  alias Rlm.TestHelpers

  test "extracts timeout, grounding, test, and improvement signals from a recovered run" do
    tmp = TestHelpers.temp_dir("rlm-post-mortem")
    on_exit(fn -> File.rm_rf!(tmp) end)

    path = Path.join(tmp, "run-timeout.json")

    File.write!(
      path,
      Jason.encode!(%{
        status: "completed",
        completed: true,
        prompt: "What aspects of the user's work style appear unusually salient or repeated?",
        failure_history: [
          %{
            class: "provider_timeout",
            source: "provider",
            message: "provider exceeded the total request deadline",
            recoverable: true
          }
        ],
        grounding: %{
          grade: "B",
          metrics: %{
            search_count: 9,
            read_files: 1
          }
        },
        context_sources: ["/tmp/alpha.md", "/tmp/beta.md"],
        context_lazy_bytes: 2048,
        iteration_records: [
          %{
            iteration: 2,
            status: "ok",
            stderr: "",
            details: %{}
          }
        ],
        recorded_at: "2026-04-29T15:19:57Z"
      })
    )

    assert {:ok, report} = PostMortem.analyze_path(path)
    assert report.postmortem_version == 2
    assert report.total_runs == 1
    assert report.recovered_runs == 1
    assert report.summary.runs_analyzed == 1
    assert report.candidate_tests == report.test_candidates
    assert report.improvement_opportunities == report.improvement_ideas

    run = hd(report.runs)
    provider_timeout = Enum.find(run.categories, &(&1.key == "provider_timeout"))
    weak_read_coverage = Enum.find(run.categories, &(&1.key == "weak_read_coverage"))

    assert provider_timeout
    assert weak_read_coverage
    assert Enum.any?(provider_timeout.pointers, &(&1.json_path == "failure_history[0].class"))
    assert Enum.any?(provider_timeout.pointers, &(is_integer(&1.line_hint)))
    assert Enum.any?(weak_read_coverage.pointers, &(&1.json_path == "grounding.metrics.read_files"))

    provider_test = Enum.find(run.tests, &(&1.category == "provider_timeout"))
    grounding_test = Enum.find(run.tests, &(&1.category == "weak_read_coverage"))
    timeout_idea = Enum.find(run.improvements, &(&1.key == "early_timeout_finalization"))
    read_idea = Enum.find(run.improvements, &(&1.key == "force_read_promotion"))

    assert provider_test
    assert grounding_test
    assert timeout_idea
    assert read_idea
    assert provider_test.pointers != []
    assert timeout_idea.pointers != []

    [queue_item | _] = report.review_queue
    assert queue_item.id in ["grounding/weak_read_coverage", "reliability/provider_timeout"]
    assert queue_item.representative_runs != []
    assert hd(queue_item.representative_runs).pointers != []

    rendered = PostMortem.render(report)
    assert rendered =~ "Issue categories"
    assert rendered =~ "reliability/provider_timeout"
    assert rendered =~ "grounding/weak_read_coverage"
  end

  test "does not flag weak read coverage for single-file runs" do
    tmp = TestHelpers.temp_dir("rlm-post-mortem-single-file")
    on_exit(fn -> File.rm_rf!(tmp) end)

    path = Path.join(tmp, "run-single-file.json")

    File.write!(
      path,
      Jason.encode!(%{
        status: "completed",
        completed: true,
        prompt: "Explain the coding style of the user",
        grounding: %{
          grade: "C",
          metrics: %{
            search_count: 6,
            read_files: 0
          }
        },
        context_sources: ["/tmp/chat-history.jsonl"],
        context_lazy_bytes: 4096,
        failure_history: [],
        iteration_records: [],
        recorded_at: "2026-04-29T15:19:57Z"
      })
    )

    assert {:ok, report} = PostMortem.analyze_path(path)
    run = hd(report.runs)

    refute Enum.any?(run.categories, &(&1.key == "weak_read_coverage"))
    refute Enum.any?(run.tests, &(&1.category == "weak_read_coverage"))
    refute Enum.any?(run.improvements, &(&1.key == "force_read_promotion"))
  end

  test "extracts runtime recovery candidates from failing block details" do
    tmp = TestHelpers.temp_dir("rlm-post-mortem-runtime")
    on_exit(fn -> File.rm_rf!(tmp) end)

    path = Path.join(tmp, "run-runtime.json")

    File.write!(
      path,
      Jason.encode!(%{
        status: "completed",
        completed: true,
        prompt: "summarize",
        failure_history: [
          %{
            class: "python_exec_error",
            source: "runtime",
            message: "NameError in later block",
            recoverable: true
          }
        ],
        grounding: %{
          grade: "A",
          metrics: %{
            search_count: 2,
            read_files: 3
          }
        },
        iteration_records: [
          %{
            iteration: 1,
            status: "recovered",
            error_kind: "runtime_exception",
            recovery_kind: "async_wrapper",
            stderr: "Traceback...",
            details: %{
              failed_block_code: "print(contemporary_haits)",
              failed_block_index: 6,
              block_count: 6
            }
          }
        ],
        recorded_at: "2026-04-29T15:19:57Z"
      })
    )

    assert {:ok, report} = PostMortem.analyze_path(path)
    run = hd(report.runs)

    assert Enum.any?(run.categories, &(&1.key == "python_exec_error"))

    runtime_exception = Enum.find(run.categories, &(&1.key == "runtime_exception"))
    async_wrapper = Enum.find(run.categories, &(&1.key == "async_wrapper"))
    runtime_test = Enum.find(run.tests, &(&1.category == "python_exec_error"))
    runtime_idea = Enum.find(run.improvements, &(&1.key == "fixture_failed_block_code"))

    assert runtime_exception
    assert async_wrapper
    assert Enum.any?(runtime_exception.pointers, &(&1.json_path == "iteration_records[0].error_kind"))
    assert Enum.any?(async_wrapper.pointers, &(&1.json_path == "iteration_records[0].recovery_kind"))
    assert Enum.any?(async_wrapper.pointers, &(&1.json_path == "iteration_records[0].details.failed_block_code"))
    assert runtime_test
    assert runtime_test.pointers != []
    assert runtime_idea
    assert runtime_idea.pointers != []
  end
end
