## Current State

This document is a plain-language map of what this repo currently is, what kinds of failures it is built to reason about, and where the current operational signal is strongest.

It is based on the current code in `lib/rlm/**` plus the local post-mortem artifact in `tmp/postmortem.json`.

## What This Repo Is

`rlm` is a recursive agent runtime built around a persistent Python REPL.

The model does not answer directly. It generates Python, the runtime executes that Python, and the engine decides whether to continue, recover, or finalize.

At a high level:

1. `Rlm.Engine.run/5` starts a run and a Python REPL.
2. `Rlm.Engine.Iteration` drives the loop.
3. Provider output is parsed into executable Python blocks.
4. Runtime results are classified.
5. Grounding, answer-quality, and recovery policy decide whether the run can finish.
6. The run is persisted to JSON.
7. `Rlm.PostMortem` turns saved runs into review categories and regression candidates.

Key owner modules:

- `lib/rlm/engine.ex`: top-level orchestration.
- `lib/rlm/engine/iteration.ex`: control loop.
- `lib/rlm/engine/grounding/policy.ex`: file-backed evidence rules.
- `lib/rlm/engine/grounding/grade.ex`: grounding grade calculation.
- `lib/rlm/engine/failure.ex`: failure classification.
- `lib/rlm/engine/recovery/strategy.ex`: recovery flags and instructions.
- `lib/rlm/engine/answer_quality.ex`: presentability checks for final text.
- `lib/rlm/providers/request_manager*.ex`: provider streaming and timeout behavior.
- `lib/rlm/storage/run_store.ex`: persisted run records.
- `lib/rlm/post_mortem.ex`: telemetry bucketing and review queue generation.

## The Repo's Real Concern Areas

The code is not mostly about "making the model smart." It is mostly about controlling four risk areas:

1. Trustworthiness
2. Runtime reliability
3. Provider reliability
4. Recovery and observability

That is the real shape of the system.

## Current Issue Taxonomy In Code

`Rlm.PostMortem` currently groups failures into these families:

- `grounding`
- `reliability`
- `runtime`
- `strategy`
- `other`

The categories that matter most right now are below.

| Family | Common categories | What they mean in practice | Primary owning code |
|---|---|---|---|
| `grounding` | `weak_read_coverage`, `insufficient_grounding`, `ungrounded_final_answer` | The model searched or previewed, but did not inspect enough real evidence to justify the answer | `lib/rlm/engine/grounding/policy.ex`, `lib/rlm/engine/prompt/iteration_feedback.ex`, `lib/rlm/engine/prompt/base.ex` |
| `reliability` | `idle_timeout`, `total_timeout`, `first_byte_timeout`, `provider_response_error` | The provider or stream failed, stalled, or returned unusable output | `lib/rlm/providers/request_manager.ex`, `lib/rlm/providers/request_manager/timeouts.ex`, `lib/rlm/engine/recovery/strategy.ex` |
| `runtime` | `python_exec_error`, `async_failed`, `runtime_finalization_error`, `async_wrapper_syntax_error` | The generated Python was wrong, malformed, or used helpers incorrectly | `lib/rlm/engine/failure.ex`, `lib/rlm/engine/execution/block_runner.ex`, `lib/rlm/engine/response/*`, `lib/rlm/engine/recovery/strategy.ex` |
| `strategy` | `subquery_failed`, `subquery_budget_exhausted` | The decomposition strategy or sub-query usage drifted into waste or dead ends | `lib/rlm/engine/iteration.ex`, `lib/rlm/engine/recovery/strategy.ex` |
| `other` | `provider_http_error` and leftovers | Useful signal, but usually not the main architectural question | Mixed |

## Current Signal From Local Post-Mortem Data

The current local artifact reports:

- `461` runs analyzed
- `409` completed runs
- `97` recovered runs
- `144` runs with failures

Top categories in the current artifact:

| Category | Count | Interpretation |
|---|---:|---|
| `weak_read_coverage` | 112 | The model often keeps searching without promoting enough direct reads |
| `insufficient_grounding` | 99 | Finalization is frequently blocked because the answer did not earn enough inspected evidence |
| `python_exec_error` | 17 | Runtime misuse still happens often enough to matter |
| `idle_timeout` | 13 | Provider streams still stall in visible ways |
| `ungrounded_final_answer` | 7 | Some final answers still overreach or cite unsupported evidence |
| `total_timeout` | 7 | Some runs still spend too long before converging |
| `provider_response_error` | 6 | Provider output formatting still sometimes fails the runtime contract |

The most important conclusion is simple:

The repo's main live problem is still grounding discipline, not provider transport.

## What The Code Is Already Good At

There is already real structure here. This is not a repo with no controls.

Current strengths:

- Grounding policy is explicit, not implicit.
- Final answers can be blocked for weak evidence.
- Timeout classes are separated into `first_byte`, `idle`, and `total`.
- Recovery instructions are per-failure-class, not generic.
- Partial answers can be preserved on failure.
- Malformed final outputs and some runtime failures already have salvage paths.
- Runs are persisted with enough detail to inspect `failure_history`, `grounding`, and `iteration_records` later.
- Post-mortem review already proposes regression candidates and improvement ideas.

This means the repo does have introspection primitives. The problem is that they are still fragmented.

## Where Introspection Is Weak Right Now

This is the part that is probably making the system feel hard to read.

### 1. The signal is split across too many layers

You have to mentally combine:

- `failure_history`
- `grounding`
- `iteration_records`
- `recovery_flags`
- `best_answer_reason`
- post-mortem category logic

There is no single first-class "run diagnosis" view that says:

- what kind of run this was
- why it failed or recovered
- whether the problem was trust, runtime, or provider related
- which subsystem owns the next fix

### 2. Grounding signal is strong, but the story is not compact

The grounding subsystem is doing a lot:

- grading evidence
- checking search-vs-read promotion
- checking file citation validity
- checking multi-file adequacy
- shaping iteration feedback

But that logic is spread across:

- `grounding/policy.ex`
- `grounding/grade.ex`
- `prompt/iteration_feedback.ex`
- `prompt/base.ex`
- `recovery/strategy.ex`

So the system knows a lot about grounding, but a maintainer does not get one compact view of the current grounding posture.

### 3. Post-mortem taxonomy is more mature than the top-level docs

`Rlm.PostMortem` has a clearer practical taxonomy than the repo's README.

The code already thinks in terms of:

- trust failures
- runtime failures
- provider failures
- strategy failures
- regression candidates
- improvement opportunities

But that shape is not yet surfaced as a standing repo document or dashboard.

### 4. Some categories appear historically sticky

The post-mortem layer can keep showing categories whose original enforcement path may have moved or changed.

Example:

- `ungrounded_final_answer` is still a live family, but not every historical subtype maps cleanly to one obvious current validator.

That makes the artifact useful, but not always self-explaining.

### 5. The current artifact is still telemetry, not a maintained operating picture

`tmp/postmortem.json` is rich, but it is not human-first.

It answers:

- what happened historically

Better than it answers:

- what the repo currently believes its main failure modes are
- which issues are already well-contained
- what should actually be worked on first

## The Most Important Current State Summary

If you want the shortest honest summary of the repo, it is this:

- The core architecture is real and coherent.
- The system already has meaningful grounding and recovery policy.
- The dominant active issue family is still grounding.
- The second meaningful issue family is runtime misuse of helper/tool contracts.
- Provider timeouts are present, but they look more contained than the grounding problems.
- Observability exists as raw artifacts and review logic, but not yet as one stable maintainer-facing operating document.

## What To Read First When Debugging

If the question is "what kind of problem is this run?", read in this order:

1. `failure_history`
2. `grounding`
3. `iteration_records`
4. `recovery_flags`
5. `best_answer_reason`

If the question is "what subsystem owns this?", use this map:

- weak evidence or overreach: `lib/rlm/engine/grounding/*`
- malformed or unusable final text: `lib/rlm/engine/answer_quality.ex`, `lib/rlm/engine/finalizer.ex`, `lib/rlm/engine/response/*`
- Python/runtime crashes: `lib/rlm/engine/failure.ex`, `lib/rlm/engine/execution/*`
- provider stalls and stream failures: `lib/rlm/providers/request_manager*`
- repeated bad recovery behavior: `lib/rlm/engine/recovery/*`
- historical pattern and category counts: `lib/rlm/post_mortem.ex`, `tmp/postmortem.json`

## Useful Commands

Regenerate the full post-mortem baseline:

```bash
bin/rlm-postmortem-json > tmp/postmortem.json
```

Refresh only new runs since checkpoint:

```bash
bin/rlm-postmortem-json --incremental ~/.local/state/rlm/runs > tmp/postmortem.json
```

Important caveat:

Incremental mode updates the artifact with only new runs after the checkpoint. If you want a full-picture snapshot document, use the full baseline command.

## What Seems Worth Adding Next

The repo likely wants one more maintainer-facing layer, somewhere between raw run JSON and the current post-mortem artifact.

The missing object is something like:

- a stable current-state report
- grouped by owning subsystem
- split into `trust`, `runtime`, `provider`, and `strategy`
- explicitly marking `active`, `contained`, and `historical` issues

That would make the existing introspection primitives feel like one system instead of several good pieces.
