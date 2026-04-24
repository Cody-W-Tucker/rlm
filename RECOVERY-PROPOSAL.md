# RLM Recovery Proposal

This proposal covers two scopes:

1. Fix now: the smallest reliability changes that move `rlm` toward always producing a meaningful result.
2. Next feature wave: the directional changes that turn `rlm` into a recovery-first RLM rather than a code-generating loop that sometimes exits with raw internal errors.

The target behavior is:

- On success, return a normal answer.
- On recoverable failure, retry with a simpler strategy or return a constrained partial answer.
- On terminal startup/config failure, return a short actionable diagnosis.
- Avoid raw internal errors as the final user-visible answer unless startup is impossible.

## Current Baseline

The current codebase already has several important pieces in place:

- The main orchestration loop is in `lib/rlm/engine.ex`.
- Context-shape and budget-aware prompting now happens in `lib/rlm/engine/policy.ex`.
- The Python bridge and sub-query plumbing live in `lib/rlm/runtime/python_repl.ex` and `priv/runtime.py`.
- Runtime config imports now merge correctly in `config/runtime.exs`.

This is a good base, but the system still has a gap between "errors are surfaced cleanly" and "errors are turned into useful outcomes".

The main issues in the current code are:

- `Engine` still collapses failures into `error_result/5`, which returns a raw error string as the final answer (`lib/rlm/engine.ex`).
- The tracker only stores token and sub-query counts, not recovery state or best-so-far answers (`lib/rlm/engine/run_state.ex`).
- `PythonRepl` now fails fast on shutdown and supervisor loss, but those errors are still just text payloads, not structured recovery signals (`lib/rlm/runtime/python_repl.ex`).
- The Python runtime still exposes async behavior through an `AwaitableString` shim, which is better than before but still awkward for natural `asyncio.gather(...)` usage (`priv/runtime.py`).

## 1. Fix Now

These changes should be the next small wave. They are intentionally minimal and should fit the current architecture.

### 1.1 Add Structured Error Classification

Problem:

- Errors are mostly passed around as strings.
- The engine cannot make good policy decisions if everything looks like a generic message.

Proposal:

- Introduce a small error classifier in Elixir, likely near `Rlm.Engine` or in a new `Rlm.Engine.Failure`-style module.
- Normalize raw failures into categories such as:
  - `:provider_timeout`
  - `:provider_unavailable`
  - `:python_exec_error`
  - `:async_failed`
  - `:subquery_budget_exhausted`
  - `:runtime_shutdown`
  - `:config_error`

Why this aligns with the ideal behavior:

- The Elixir side should supervise and recover intentionally, not only relay strings.
- This is the minimum needed for policy-aware retries.

Grounding in code:

- `llm_query_handler/3` currently returns plain `{:error, message}` (`lib/rlm/engine.ex`).
- `PythonRepl.normalize_task_result/1` converts failures into `[ERROR] ...` strings (`lib/rlm/runtime/python_repl.ex`).
- `error_result/5` formats a single generic `[RLM Error] ...` answer (`lib/rlm/engine.ex`).

### 1.2 Track Best-So-Far Answer in the Engine

Problem:

- The engine has no explicit place to store a usable partial answer.
- If a late iteration fails, `rlm` can still end on a raw timeout or shutdown message.

Proposal:

- Extend the tracker state beyond token counts.
- Store:
  - `best_answer_so_far`
  - `best_answer_reason`
  - `last_successful_subquery`
  - `recovery_flags`

- Update this state whenever:
  - an iteration prints a coherent summary
  - a sub-query returns a useful synthesis
  - the model calls `FINAL(...)`

Why this aligns with the ideal behavior:

- The system should prefer a partial useful answer over a raw failure.
- This is the smallest way to get that behavior without redesigning the loop.

Grounding in code:

- `start_tracker/0` currently only tracks `total_sub_queries`, `input_tokens`, and `output_tokens` (`lib/rlm/engine/run_state.ex`).
- `build_iteration_feedback/4` has access to printed output and runtime errors, but none of that is persisted as a candidate answer (`lib/rlm/engine.ex` and `lib/rlm/engine/policy.ex`).

### 1.3 Add One Recovery Iteration Path

Problem:

- Today, once an iteration hits a provider/runtime error, the run ends through `error_result/5`.
- That gives no chance for the model to simplify its strategy.

Proposal:

- Add one constrained recovery path in `execute_iterations/8`.
- If an iteration fails with a recoverable classified error:
  - append a recovery feedback message to history
  - set policy flags for the remainder of the run
  - allow one more iteration using a simpler strategy

The recovery feedback should say things like:

- "The previous strategy timed out. Do not retry the same broad sub-query."
- "Async failed. Do not use async again in this run."
- "Use direct reasoning or one narrow sub-query and finalize with the best available answer."

Why this aligns with the ideal behavior:

- This preserves the paper-like model autonomy while letting Elixir shape safe recovery.
- It is the smallest bridge between self-healing intent and actual engine behavior.

Grounding in code:

- `execute_iterations/8` already builds incremental history and feeds back runtime output (`lib/rlm/engine.ex`).
- The natural extension is to add a recovery feedback branch instead of going straight to `error_result/5` (`lib/rlm/engine.ex`).

### 1.4 Add Run-Level Strategy Memory

Problem:

- Prompt guidance is better now, but the engine itself does not remember prior failures.
- The model can still repeat a bad pattern unless it chooses not to.

Proposal:

- Track simple run-level flags such as:
  - `async_disabled`
  - `broad_subqueries_disabled`
  - `recovery_mode`

- Reflect these flags in `build_system_prompt/3` and in recovery feedback.

Why this aligns with the ideal behavior:

- The system should ban clearly bad strategies after one failure.
- This is soft supervisory control, not a complicated planner.

Grounding in code:

- `build_system_prompt/3` already includes budget state and strategy rules (`lib/rlm/engine/policy.ex`).
- It is the right place to expose run-level constraints once the engine tracks them.

### 1.5 Improve Final Error Rendering

Problem:

- Final errors are still too raw.
- Agent consumers and users should get either a useful answer, or a useful diagnosis.

Proposal:

- Replace the current generic `error_result/5` behavior with a final renderer that prefers:
  1. `best_answer_so_far` plus a short limitation note
  2. a concise diagnosis with an exact recommended change

Example target output:

> This directory appears to configure a desktop NixOS stack covering audio, gaming, GPU hardware, and VPN/networking. I could not fully verify all requested implementation details because a broad provider query timed out. Retry with a narrower question or a longer request timeout.

Grounding in code:

- `error_result/5` is currently the main place to change (`lib/rlm/engine.ex`).

## 2. Next Feature Wave

Once the smaller recovery changes are in place, the next wave should make recovery and strategy selection first-class features.

### 2.1 Add Explicit Strategy Labels to Run Traces

Problem:

- The saved run JSON is already useful, but it still requires reading raw Python code to infer what happened.

Proposal:

- Record fields like:
  - `strategy: direct_synthesis | broad_subquery | sequential_chunking | parallel_chunking | fallback`
  - `failure_class: provider_timeout | async_failed | runtime_shutdown | ...`
  - `used_recovery: true | false`

Why this matters:

- It will make tuning much faster.
- It will let us compare prompt changes and control changes without manually reading every trace.

Grounding in code:

- Run artifacts already include `iteration_records`, `total_sub_queries`, token counts, and final answer data.
- The change belongs near the result assembly and persistence path, starting from `finalize_result/7` in `lib/rlm/engine.ex`.

### 2.2 Support Medium-Context Policies as Product Behavior

Problem:

- Medium-sized contexts are where the system is most likely to overreact: too big for naive direct prompting, too small for expensive decomposition.

Proposal:

- Add explicit engine-side policy for medium contexts:
  - prefer direct reasoning first
  - allow one narrow sub-query if needed
  - only then allow small sequential chunking
  - never default to broad parallel fan-out for medium inputs

Why this matters:

- This matches the successful direction we already saw after adding the context-aware prompt header.

Grounding in code:

- The current context header already infers a `strategy_hint` from bytes and source count (`lib/rlm/engine/policy.ex`).
- The feature change is to move that idea from prompt advice into actual engine policy.

### 2.3 Make Async Either Real or Intentionally Narrow

Problem:

- `async_llm_query` is currently usable for some cases, but it is still not a clean abstraction for the kinds of async code the model naturally writes.

Proposal:

- Choose one direction explicitly:
  - either implement proper async/future semantics that work naturally with `asyncio.gather(...)`
  - or narrow the contract and document/prompt that async is not for arbitrary gather patterns

Why this matters:

- Right now async exists in an in-between state: better than before, but still a source of avoidable complexity.

Grounding in code:

- See `AwaitableString` and `async_llm_query` in `priv/runtime.py`.

### 2.4 Offer Execution Policies

Proposal:

- Add optional CLI modes such as:
  - `--conservative`
  - `--balanced`
  - `--exploratory`

These would mainly affect:

- chunking aggressiveness
- recovery willingness
- sub-query caps
- timeout expectations

Why this matters:

- It gives a simple, explicit user-facing knob without forcing the prompt to do all the work.

### 2.5 Strengthen the Output Contract

Proposal:

- Define a clear product contract:
  - never return raw internal errors as the whole answer unless startup is impossible
  - always attempt one of:
    - a direct answer
    - a partial answer with limitation note
    - a concise diagnosis with the next required change

Why this matters:

- This is the behavior users and downstream agents actually care about.
- It is the most important direction change for the project.

## Suggested Order

Recommended sequence:

1. Structured error classification
2. Best-so-far answer tracking
3. One recovery iteration path
4. Run-level strategy memory
5. Improved final error rendering
6. Strategy labels in run traces
7. Medium-context engine policies
8. A clearer async decision
9. Optional execution policies

This order keeps the implementation small at first while steadily moving toward the ideal version we want: an Elixir-supervised RLM that can recover from normal failures, simplify its own strategy, and still produce meaningful outputs.
