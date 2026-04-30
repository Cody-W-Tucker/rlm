defmodule Rlm.PostMortem do
  @moduledoc "Analyze persisted run traces into issue categories, test candidates, and improvement ideas."

  @minimum_multi_file_reads 3
  @postmortem_version 2

  def postmortem_version, do: @postmortem_version

  def analyze_path(path) do
    with {:ok, run_paths} <- expand_paths(path),
         {:ok, runs} <- load_runs(run_paths) do
      {:ok, build_report(path, runs)}
    end
  end

  def analyze_paths(paths, input_path \\ "custom") when is_list(paths) do
    with {:ok, runs} <- load_runs(paths) do
      {:ok, build_report(input_path, runs)}
    end
  end

  def render(report) do
    lines = [
      "Post-mortem summary",
      "",
      "- Runs analyzed: #{report.total_runs}",
      "- Completed runs: #{report.completed_runs}",
      "- Recovered runs: #{report.recovered_runs}",
      "- Runs with failures: #{report.runs_with_failures}",
      ""
    ]

    lines =
      if report.category_counts == [] do
        lines ++ ["Issue categories", "", "- None detected", ""]
      else
        lines ++
          ["Issue categories", ""] ++
          Enum.map(report.category_counts, fn category ->
            "- #{category.family}/#{category.key}: #{category.label} (#{category.count} run#{pluralize(category.count)})"
          end) ++ [""]
      end

    lines =
      if report.test_candidates == [] do
        lines ++ ["Regression candidates", "", "- None suggested", ""]
      else
        lines ++
          ["Regression candidates", ""] ++
          Enum.map(report.test_candidates, fn candidate ->
            "- [#{candidate.category}] #{candidate.title}"
          end) ++ [""]
      end

    lines =
      if report.improvement_ideas == [] do
        lines ++ ["Improvement ideas", "", "- None suggested", ""]
      else
        lines ++
          ["Improvement ideas", ""] ++
          Enum.map(report.improvement_ideas, fn idea ->
            "- #{idea.text}"
          end) ++ [""]
      end

    lines ++
      ["Runs", ""] ++
      Enum.flat_map(report.runs, &render_run/1)
      |> Enum.join("\n")
  end

  defp render_run(run) do
    [
      "- #{Path.basename(run.path)}: #{run.status}#{completed_suffix(run)}",
      "  prompt: #{truncate(run.prompt || "", 100)}",
      "  categories: #{format_category_keys(run.categories)}",
      "  tests: #{format_titles(run.tests)}",
      "  ideas: #{format_idea_keys(run.improvements)}",
      ""
    ]
  end

  defp build_report(input_path, runs) do
    category_counts =
      runs
      |> Enum.flat_map(& &1.categories)
      |> Enum.uniq_by(&{&1.run_path, &1.key})
      |> Enum.frequencies_by(&{&1.family, &1.key, &1.label})
      |> Enum.map(fn {{family, key, label}, count} -> %{family: family, key: key, label: label, count: count} end)
      |> Enum.sort_by(fn category -> {-category.count, category.family, category.key} end)

    candidate_tests =
      runs
      |> Enum.flat_map(& &1.tests)
      |> Enum.uniq_by(& &1.id)
      |> Enum.sort_by(&{&1.category, &1.title})

    improvement_opportunities =
      runs
      |> Enum.flat_map(& &1.improvements)
      |> Enum.uniq_by(& &1.key)
      |> Enum.sort_by(& &1.key)

    review_queue = review_queue(runs)

    summary = %{
      runs_analyzed: length(runs),
      completed_runs: Enum.count(runs, & &1.completed),
      recovered_runs: Enum.count(runs, &(&1.recovered or (&1.failure_history != [] and &1.completed))),
      runs_with_failures: Enum.count(runs, &(length(&1.failure_history) > 0))
    }

    %{
      postmortem_version: @postmortem_version,
      input_path: input_path,
      summary: summary,
      total_runs: summary.runs_analyzed,
      completed_runs: summary.completed_runs,
      recovered_runs: summary.recovered_runs,
      runs_with_failures: summary.runs_with_failures,
      category_counts: category_counts,
      candidate_tests: candidate_tests,
      test_candidates: candidate_tests,
      improvement_opportunities: improvement_opportunities,
      improvement_ideas: improvement_opportunities,
      review_queue: review_queue,
      runs: Enum.sort_by(runs, &{&1.recorded_at || "", &1.path}, :desc)
    }
  end

  defp load_runs(paths) do
    Enum.reduce_while(paths, {:ok, []}, fn path, {:ok, acc} ->
      case path |> File.read() |> decode_run(path) do
        {:ok, run} -> {:cont, {:ok, [run | acc]}}
        {:error, _} = error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, runs} -> {:ok, Enum.reverse(runs)}
      error -> error
    end
  end

  defp decode_run({:ok, contents}, path) do
    case Jason.decode(contents) do
      {:ok, data} when is_map(data) -> {:ok, analyze_run(data, path, contents)}
      {:ok, _other} -> {:error, "expected a JSON object in #{path}"}
      {:error, error} -> {:error, "failed to decode #{path}: #{Exception.message(error)}"}
    end
  end

  defp decode_run({:error, reason}, path), do: {:error, "failed to read #{path}: #{inspect(reason)}"}

  defp analyze_run(data, path, contents) do
    source_lines = String.split(contents, "\n")
    failure_history = List.wrap(data["failure_history"])
    run_context = %{path: path, run_id: Path.basename(path), source_lines: source_lines}
    categories = categories(data, failure_history, run_context)
    tests = regression_candidates(data, run_context, categories)
    improvements = improvement_ideas(data, categories)
    recovered = Enum.any?(List.wrap(data["iteration_records"]), &(to_string(&1["status"] || "") == "recovered"))

    %{
      path: path,
      run_id: Path.basename(path),
      prompt: data["prompt"],
      status: to_string(data["status"] || "unknown"),
      completed: data["completed"] == true,
      recorded_at: data["recorded_at"],
      run_schema_version: data["run_schema_version"] || 0,
      failure_history: failure_history,
      categories: categories,
      tests: tests,
      improvements: improvements,
      recovered: recovered
    }
  end

  defp categories(data, failure_history, run_context) do
    failure_categories =
      failure_history
      |> Enum.with_index()
      |> Enum.map(fn {failure, index} -> failure_category(failure, index, run_context) end)

    recovery_categories =
      data["iteration_records"]
      |> List.wrap()
      |> Enum.with_index()
      |> Enum.flat_map(fn {record, index} -> iteration_categories(record, index, run_context) end)

    grounding_categories = grounding_categories(data, run_context)

    (failure_categories ++ recovery_categories ++ grounding_categories)
    |> dedupe_categories()
    |> Enum.uniq_by(fn category ->
      {category.key, category.evidence, Enum.map(category.pointers, fn pointer -> pointer.json_path end)}
    end)
  end

  defp dedupe_categories(categories) do
    python_exec_errors = Enum.filter(categories, &(&1.key == "python_exec_error"))

    Enum.reject(categories, fn category ->
      redundant_runtime_exception?(category, python_exec_errors)
    end)
  end

  defp redundant_runtime_exception?(%{key: "runtime_exception", run_path: run_path} = category, python_exec_errors) do
    Enum.any?(python_exec_errors, fn python_exec_error ->
      python_exec_error.run_path == run_path and
        (overlapping_runtime_evidence?(category.evidence, python_exec_error.evidence) or
           overlapping_pointer_values?(category.pointers, ["failed_block_code", "stderr"], python_exec_error.evidence) or
           Enum.any?(category.pointers, &(&1.anchor_key == "failed_block_code" and is_binary(&1.anchor_value) and &1.anchor_value != "")))
    end)
  end

  defp redundant_runtime_exception?(_category, _python_exec_errors), do: false

  defp overlapping_runtime_evidence?(left, right) when is_binary(left) and is_binary(right) do
    String.contains?(left, right) or String.contains?(right, left)
  end

  defp overlapping_runtime_evidence?(_left, _right), do: false

  defp overlapping_pointer_values?(pointers, anchor_keys, evidence) when is_binary(evidence) do
    Enum.any?(pointers, fn pointer ->
      pointer.anchor_key in anchor_keys and is_binary(pointer.anchor_value) and
        pointer.anchor_value != "" and String.contains?(evidence, pointer.anchor_value)
    end)
  end

  defp overlapping_pointer_values?(_pointers, _anchor_keys, _evidence), do: false

  defp failure_category(failure, index, run_context) do
    class = to_string(failure["class"] || "unknown_failure")
    {family, label} = classify_failure(class)
    pointers = [
      pointer(run_context, "failure_history[#{index}].class", class),
      pointer(run_context, "failure_history[#{index}].message", failure["message"])
    ]

    %{
      family: family,
      key: class,
      label: label,
      evidence: truncate(failure["message"] || "", 180),
      run_path: run_context.path,
      run_id: run_context.run_id,
      pointers: pointers,
      failure_index: index,
      iteration: nil
    }
  end

  defp iteration_categories(record, index, run_context) do
    status = to_string(record["status"] || "")
    error_kind = normalize_optional(record["error_kind"])
    recovery_kind = normalize_optional(record["recovery_kind"])

    []
    |> maybe_add_iteration_category((status in ["error", "recovered"]) && error_kind, error_kind, record, index, run_context)
    |> maybe_add_iteration_category((status == "recovered") && recovery_kind, recovery_kind, record, index, run_context)
  end

  defp maybe_add_iteration_category(categories, false, _key, _record, _index, _run_context), do: categories
  defp maybe_add_iteration_category(categories, nil, _key, _record, _index, _run_context), do: categories

  defp maybe_add_iteration_category(categories, key, _record_key, record, index, run_context) do
    family = classify_iteration_family(key)
    iteration = record["iteration"]
    pointers = iteration_pointers(record, index, key, run_context)

    categories ++
      [
        %{
          family: family,
          key: key,
          label: humanize_key(key),
          evidence: truncate(iteration_evidence(record), 180),
          run_path: run_context.path,
          run_id: run_context.run_id,
          pointers: pointers,
          failure_index: nil,
          iteration: iteration
        }
      ]
  end

  defp grounding_categories(data, run_context) do
    grounding = data["grounding"] || %{}
    metrics = grounding["metrics"] || %{}
    read_files = metrics["read_files"] || 0
    search_count = metrics["search_count"] || 0
    grade = grounding["grade"]
    context_sources = List.wrap(data["context_sources"])
    context_lazy_bytes = data["context_lazy_bytes"] || 0

    if context_lazy_bytes > 0 and length(context_sources) > 1 and search_count >= 1 and
         read_files < @minimum_multi_file_reads do
      [
        %{
          family: "grounding",
          key: "weak_read_coverage",
          label: "Weak read coverage",
          evidence:
            "Grounding grade #{grade || "unknown"} with #{read_files} direct read(s) after #{search_count} search round(s).",
          run_path: run_context.path,
          run_id: run_context.run_id,
          pointers: [
            pointer(run_context, "grounding.grade", grade),
            pointer(run_context, "grounding.metrics.read_files", read_files),
            pointer(run_context, "grounding.metrics.search_count", search_count)
          ],
          failure_index: nil,
          iteration: nil
        }
      ]
    else
      []
    end
  end

  defp regression_candidates(data, run_context, categories) do
    categories
    |> Enum.map(&candidate_for_category(&1, data, run_context))
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq_by(& &1.id)
  end

  defp candidate_for_category(%{key: key, evidence: evidence} = category, data, run_context) do
    case key do
      "provider_timeout" ->
        candidate(run_context, category, key, "preserves the best available answer after a provider timeout", evidence)

      "total_timeout" ->
        candidate(run_context, category, key, "finalizes from partial work after the total request deadline", evidence)

      "weak_read_coverage" ->
        candidate(
          run_context,
          category,
          key,
          "requires more than one direct read before finalizing a multi-file answer",
          evidence
        )

      "insufficient_grounding" ->
        candidate(run_context, category, key, "requires at least three relevant reads before finalization", evidence)

      "ungrounded_final_answer" ->
        candidate(run_context, category, key, "blocks final answers that cite unread file paths", evidence)

      "python_exec_error" ->
        candidate(run_context, category, key, runtime_test_title(data), failure_block_excerpt(data) || evidence)

      "runtime_finalization_error" ->
        candidate(run_context, category, key, "salvages malformed FINAL output instead of crashing the run", evidence)

      "syntax_unterminated_triple_quote" ->
        candidate(run_context, category, key, "salvages unterminated triple-quoted FINAL bodies", evidence)

      "salvaged_unterminated_final" ->
        candidate(run_context, category, key, "keeps the recovered FINAL body from malformed provider output", evidence)

      "async_failed" ->
        candidate(run_context, category, key, "disables async strategies after the first async failure", evidence)

      "subquery_budget_exhausted" ->
        candidate(run_context, category, key, "finalizes from partial evidence when the sub-query budget is exhausted", evidence)

      "subquery_failed" ->
        candidate(run_context, category, key, "narrows strategy after a sub-query failure", evidence)

      _ ->
        nil
    end
  end

  defp candidate(run_context, category, category_key, title, evidence) do
    %{
      id: "#{category_key}:#{title}",
      run: run_context.run_id,
      run_path: run_context.path,
      category: category_key,
      title: title,
      evidence: evidence,
      pointers: category.pointers,
      iteration: category.iteration,
      failure_index: category.failure_index
    }
  end

  defp improvement_ideas(data, categories) do
    category_keys = MapSet.new(Enum.map(categories, & &1.key))

    []
    |> maybe_add_idea(MapSet.member?(category_keys, "provider_timeout") or MapSet.member?(category_keys, "total_timeout"), %{
      key: "early_timeout_finalization",
      text: "After provider timeouts, prefer an earlier finalize-from-partial-work path instead of retrying a broad strategy.",
      pointers: pointers_for_categories(categories, ["provider_timeout", "total_timeout"])
    })
    |> maybe_add_idea(MapSet.member?(category_keys, "weak_read_coverage") or MapSet.member?(category_keys, "insufficient_grounding"), %{
      key: "force_read_promotion",
      text: "Add an earlier promotion rule from search/preview to targeted `read_file()` calls when search rounds climb but direct reads stay below three.",
      pointers: pointers_for_categories(categories, ["weak_read_coverage", "insufficient_grounding"])
    })
    |> maybe_add_idea(MapSet.member?(category_keys, "ungrounded_final_answer"), %{
      key: "tighten_citation_guard",
      text: "Keep citation validation strict and feed the missing inspected paths back into the recovery prompt.",
      pointers: pointers_for_categories(categories, ["ungrounded_final_answer"])
    })
    |> maybe_add_idea(MapSet.member?(category_keys, "python_exec_error"), %{
      key: "fixture_failed_block_code",
      text: "Promote runtime failures with failing block code into regression fixtures so typo-style crashes stay reproducible.",
      pointers: pointers_for_categories(categories, ["python_exec_error", "runtime_exception"])
    })
    |> maybe_add_idea(MapSet.member?(category_keys, "runtime_finalization_error") or MapSet.member?(category_keys, "syntax_unterminated_triple_quote") or MapSet.member?(category_keys, "salvaged_unterminated_final"), %{
      key: "fixture_malformed_final",
      text: "Keep adding malformed FINAL outputs as fixtures so salvage behavior stays stable across provider changes.",
      pointers: pointers_for_categories(categories, ["runtime_finalization_error", "syntax_unterminated_triple_quote", "salvaged_unterminated_final"])
    })
    |> maybe_add_idea(MapSet.member?(category_keys, "async_failed"), %{
      key: "disable_async_after_failure",
      text: "When async recovery triggers once, hard-disable async for the remainder of the run and steer toward sequential fallback code.",
      pointers: pointers_for_categories(categories, ["async_failed"])
    })
    |> maybe_add_idea(MapSet.member?(category_keys, "subquery_budget_exhausted") or MapSet.member?(category_keys, "subquery_failed"), %{
      key: "narrow_subquery_strategy",
      text: "Bias recovery prompts toward one narrow sub-query or direct reasoning after sub-query failures instead of repeating broad fan-out.",
      pointers: pointers_for_categories(categories, ["subquery_budget_exhausted", "subquery_failed"])
    })
    |> maybe_add_idea(data["completed"] == true and List.wrap(data["failure_history"]) != [], %{
      key: "promote_recovered_runs",
      text: "Any run that completed only after failure recovery is a good fixture candidate, even when the final answer looks acceptable.",
      pointers: Enum.flat_map(categories, & &1.pointers) |> Enum.uniq_by(&pointer_identity/1)
    })
  end

  defp review_queue(runs) do
    runs
    |> Enum.flat_map(& &1.categories)
    |> Enum.group_by(fn entry -> {entry.family, entry.key, entry.label} end)
    |> Enum.map(fn {{family, key, label}, entries} ->
      sorted_entries = Enum.sort_by(entries, &{&1.run_id, &1.iteration || -1, &1.failure_index || -1})

      %{
        id: "#{family}/#{key}",
        kind: family,
        category: key,
        label: label,
        priority: review_priority(family, key, length(entries)),
        count: length(entries),
        representative_runs:
          sorted_entries
          |> Enum.take(3)
          |> Enum.map(fn entry ->
            %{
              run_id: entry.run_id,
              run_path: entry.run_path,
              iteration: entry.iteration,
              failure_index: entry.failure_index,
              evidence_summary: entry.evidence,
              pointers: entry.pointers
            }
          end),
        suggested_action: suggested_action(family, key),
        promotion_state: "new"
      }
    end)
    |> Enum.sort_by(fn item -> {priority_rank(item.priority), -item.count, item.kind, item.category} end)
  end

  defp review_priority(_family, key, count) when key in ["python_exec_error", "runtime_exception"] and count >= 3,
    do: "high"

  defp review_priority("grounding", _key, count) when count >= 3, do: "high"
  defp review_priority("reliability", _key, count) when count >= 2, do: "high"
  defp review_priority(_family, _key, count) when count >= 2, do: "medium"
  defp review_priority(_family, _key, _count), do: "low"

  defp suggested_action("runtime", "python_exec_error"),
    do: "Inspect failing block context, compare with current runtime recovery logic, and decide whether to promote a fixture regression or a stronger runtime guard."

  defp suggested_action("runtime", "runtime_exception"),
    do: "Inspect representative runtime exceptions and confirm whether current recovery still preserves enough failing-block context."

  defp suggested_action("grounding", "weak_read_coverage"),
    do: "Inspect whether the current grounding policy promotes enough searches into direct reads before finalization."

  defp suggested_action("reliability", key) when key in ["provider_timeout", "total_timeout", "first_byte_timeout"],
    do: "Inspect timeout recovery paths and confirm whether partial-answer finalization should happen earlier or more consistently."

  defp suggested_action("runtime", "async_failed"),
    do: "Inspect async fallback behavior and confirm the run disables async after the first async-specific failure."

  defp suggested_action(_family, _key),
    do: "Inspect representative traces and current code paths before deciding whether to promote this into a regression test, recovery change, or monitoring-only note."

  defp priority_rank("high"), do: 0
  defp priority_rank("medium"), do: 1
  defp priority_rank(_), do: 2

  defp pointers_for_categories(categories, keys) do
    categories
    |> Enum.filter(&(&1.key in keys))
    |> Enum.flat_map(& &1.pointers)
    |> Enum.uniq_by(&pointer_identity/1)
  end

  defp pointer_identity(pointer), do: {pointer.run_path, pointer.json_path, pointer.line_hint}

  defp iteration_pointers(record, index, key, run_context) do
    iteration = record["iteration"]
    details = record["details"] || %{}

    [
      pointer(run_context, "iteration_records[#{index}].iteration", iteration),
      pointer(run_context, "iteration_records[#{index}].#{kind_field(key)}", key),
      maybe_pointer(run_context, "iteration_records[#{index}].details.failed_block_code", details["failed_block_code"]),
      maybe_pointer(run_context, "iteration_records[#{index}].stderr", normalize_stderr(record["stderr"]))
    ]
    |> Enum.reject(&is_nil/1)
  end

  defp kind_field(key) when key in ["runtime_exception", "subquery_error", "syntax_error", "syntax_unterminated_triple_quote"], do: "error_kind"
  defp kind_field(_key), do: "recovery_kind"

  defp pointer(run_context, json_path, value) do
    %{
      run_id: run_context.run_id,
      run_path: run_context.path,
      json_path: json_path,
      line_hint: line_hint(run_context.source_lines, json_path, value),
      anchor_key: anchor_key(json_path),
      anchor_value: truncate(anchor_value(value), 120)
    }
  end

  defp maybe_pointer(_run_context, _json_path, nil), do: nil
  defp maybe_pointer(_run_context, _json_path, ""), do: nil
  defp maybe_pointer(run_context, json_path, value), do: pointer(run_context, json_path, value)

  defp line_hint(lines, json_path, value) do
    expected = anchor_value(value)
    key = anchor_key(json_path)
    indexed_lines = Enum.with_index(lines, 1)

    case Regex.run(~r/^failure_history\[(\d+)\]\.(.+)$/u, json_path, capture: :all_but_first) do
      [index, _field] -> locate_indexed_section(indexed_lines, "failure_history", String.to_integer(index), key, expected)
      _ ->
        case Regex.run(~r/^iteration_records\[(\d+)\]\.(.+)$/u, json_path, capture: :all_but_first) do
          [index, _field] -> locate_indexed_section(indexed_lines, "iteration_records", String.to_integer(index), key, expected)
          _ -> locate_generic_line(indexed_lines, key, expected)
        end
    end
  end

  defp locate_indexed_section(indexed_lines, section, index, key, expected) do
    start_line = Enum.find_value(indexed_lines, fn {line, number} -> if String.contains?(line, ~s("#{section}")), do: number end)

    if start_line do
      scoped = Enum.drop_while(indexed_lines, fn {_line, number} -> number < start_line end)
      matching =
        scoped
        |> Enum.filter(fn {line, _number} -> String.contains?(line, ~s("#{key}")) end)

      case Enum.at(matching, index) do
        {_line, number} -> number
        nil -> locate_generic_line(indexed_lines, key, expected)
      end
    else
      locate_generic_line(indexed_lines, key, expected)
    end
  end

  defp locate_generic_line(indexed_lines, key, expected) do
    Enum.find_value(indexed_lines, fn {line, number} ->
      matches_key = String.contains?(line, ~s("#{key}"))
      matches_value = expected == nil or String.contains?(line, expected)
      if matches_key and matches_value, do: number
    end)
  end

  defp anchor_key(json_path) do
    json_path
    |> String.split(".")
    |> List.last()
    |> to_string()
    |> String.replace(~r/\[\d+\]/u, "")
  end

  defp anchor_value(value) when is_binary(value), do: value
  defp anchor_value(value) when is_integer(value), do: Integer.to_string(value)
  defp anchor_value(value) when is_float(value), do: :erlang.float_to_binary(value)
  defp anchor_value(true), do: "true"
  defp anchor_value(false), do: "false"
  defp anchor_value(nil), do: nil
  defp anchor_value(value), do: inspect(value)

  defp normalize_stderr(stderr) when is_binary(stderr) do
    stderr
    |> String.trim()
    |> case do
      "" -> nil
      value -> value
    end
  end

  defp normalize_stderr(_), do: nil

  defp maybe_add_idea(ideas, true, idea), do: [idea | ideas]
  defp maybe_add_idea(ideas, false, _idea), do: ideas

  defp classify_failure(class) do
    case class do
      key when key in ["provider_timeout", "total_timeout", "idle_timeout", "first_byte_timeout"] ->
        {"reliability", "Provider timeout"}

      key when key in ["provider_unavailable", "provider_error", "provider_response_error"] ->
        {"reliability", humanize_key(key)}

      key when key in ["python_exec_error", "runtime_syntax_error", "runtime_finalization_error", "runtime_shutdown", "async_failed"] ->
        {"runtime", humanize_key(key)}

      key when key in ["subquery_budget_exhausted", "subquery_failed"] ->
        {"strategy", humanize_key(key)}

      key when key in ["insufficient_grounding", "ungrounded_final_answer"] ->
        {"grounding", humanize_key(key)}

      _ ->
        {"other", humanize_key(class)}
    end
  end

  defp classify_iteration_family(key) do
    cond do
      String.contains?(key, "async") -> "runtime"
      String.contains?(key, "final") -> "runtime"
      String.contains?(key, "syntax") -> "runtime"
      String.contains?(key, "subquery") -> "strategy"
      true -> "runtime"
    end
  end

  defp iteration_evidence(record) do
    details = record["details"] || %{}

    cond do
      is_binary(details["message"]) and details["message"] != "" -> details["message"]
      is_binary(record["stderr"]) and String.trim(record["stderr"]) != "" -> String.trim(record["stderr"])
      is_binary(details["failed_block_code"]) -> details["failed_block_code"]
      true -> "iteration #{record["iteration"] || "?"} #{record["status"] || "unknown"}"
    end
  end

  defp runtime_test_title(data) do
    if failure_block_excerpt(data) do
      "recovers from runtime errors with failing block context preserved"
    else
      "keeps runtime execution failures reproducible as regression fixtures"
    end
  end

  defp failure_block_excerpt(data) do
    data["iteration_records"]
    |> List.wrap()
    |> Enum.find_value(fn record ->
      details = record["details"] || %{}
      code = details["failed_block_code"]

      if is_binary(code) and code != "" do
        truncate(code, 180)
      end
    end)
  end

  defp expand_paths(path) do
    expanded = Path.expand(path)

    cond do
      File.regular?(expanded) -> {:ok, [expanded]}
      File.dir?(expanded) -> list_json_files(expanded)
      true -> {:error, "path not found: #{path}"}
    end
  end

  defp list_json_files(path) do
    case File.ls(path) do
      {:ok, files} ->
        files =
          files
          |> Enum.filter(&String.ends_with?(&1, ".json"))
          |> Enum.sort(:desc)
          |> Enum.map(&Path.join(path, &1))

        {:ok, files}

      {:error, reason} ->
        {:error, "failed to list #{path}: #{inspect(reason)}"}
    end
  end

  defp format_category_keys([]), do: "none"
  defp format_category_keys(categories), do: categories |> Enum.map(& &1.key) |> Enum.uniq() |> Enum.join(", ")

  defp format_titles([]), do: "none"
  defp format_titles(tests), do: tests |> Enum.map(& &1.title) |> Enum.uniq() |> Enum.join(" | ")

  defp format_idea_keys([]), do: "none"
  defp format_idea_keys(ideas), do: ideas |> Enum.map(& &1.key) |> Enum.uniq() |> Enum.join(", ")

  defp completed_suffix(%{status: "completed"}), do: ""
  defp completed_suffix(%{completed: true}), do: ", completed"
  defp completed_suffix(_run), do: ""

  defp pluralize(1), do: ""
  defp pluralize(_count), do: "s"

  defp normalize_optional(nil), do: nil
  defp normalize_optional(""), do: nil
  defp normalize_optional(value), do: to_string(value)

  defp humanize_key(key) do
    key
    |> to_string()
    |> String.replace("_", " ")
    |> String.trim()
    |> String.capitalize()
  end

  defp truncate(text, limit) when is_binary(text) and byte_size(text) > limit do
    binary_part(text, 0, limit - 3) <> "..."
  end

  defp truncate(text, _limit), do: text
end
