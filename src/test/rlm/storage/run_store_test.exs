defmodule Rlm.Storage.RunStoreTest do
  use ExUnit.Case, async: false

  alias Rlm.Storage.RunStore
  alias Rlm.TestHelpers

  test "persists runs as json" do
    storage_dir = TestHelpers.temp_dir("rlm-runs")
    on_exit(fn -> File.rm_rf!(storage_dir) end)

    settings = TestHelpers.settings(%{storage_dir: storage_dir})

    result = %{
      prompt: "What happened?",
      status: :completed,
      completed?: true,
      answer: "A concise answer",
      iterations: 2,
      total_sub_queries: 1,
      depth: 0,
      iteration_records: [%{iteration: 1, events: [], actions: []}]
    }

    bundle = %{entries: [%{label: "inline text"}], bytes: 42}

    assert {:ok, path} = RunStore.persist(result, bundle, settings, mode: :one_shot)
    assert File.exists?(path)

    saved = path |> File.read!() |> Jason.decode!()
    assert saved["prompt"] == "What happened?"
    assert saved["mode"] == "one_shot"
    assert saved["context_sources"] == ["inline text"]
  end
end
