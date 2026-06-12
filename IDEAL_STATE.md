## Ideal State

This document describes the maintainer-facing target state for `rlm`.

It is grounded in the current implementation under `lib/rlm/**` and `priv/runtime/**`, with explicit comparison against `fast-rlm` where that comparison reveals a cleaner mechanism.

The main conclusion is simple:

- `rlm` already has stronger evidence governance than most RLM runtimes.
- The next step is not more prompt sophistication.
- The next step is to replace prompt pressure with runtime logic wherever the desired behavior is stable enough to enforce.

## The Core Shift

Today, too much of the system's discipline still lives in instructions like:

- do not keep searching
- promote hits into reads
- run one challenge pass
- do not dump raw evidence
- keep sub-queries narrow

Those instructions are often good.

But whenever the behavior is important, repeated, and machine-checkable, the ideal state is to enforce it with logic instead of hoping the model obeys the prompt.

That is the strongest lesson from `fast-rlm`.

`fast-rlm` is not better because it prompts more elegantly.
It is better in a few key places because it converts desired behavior into mechanism:

- schema validation instead of format advice
- delegation guards instead of chunking advice
- explicit capability inheritance instead of soft assumptions
- one run log artifact instead of inferred reconstruction

That is the direction `rlm` should keep moving in.

## What `rlm` Should Preserve

The ideal state is not a simpler but weaker runtime.

`rlm` already has real strengths that should remain first-class:

- evidence tracking inside the runtime
- grounding grades with structural and semantic dimensions
- hit-followup tracking instead of raw search counts
- explicit provider timeout classes
- recovery feedback tied to failure class
- file-backed and line-delimited corpus support
- post-mortem analysis that produces categories, fixtures, and review queues
- judgment-style protocols like Compass

The goal is not to become `fast-rlm`.

The goal is to keep `rlm`'s stronger evidence model while borrowing `fast-rlm`'s bias toward explicit runtime controls.

## Ideal State Principles

1. When a behavior is critical and checkable, enforce it in code.
2. Use prompts to explain strategy, not to carry core guarantees.
3. Keep run diagnosis compact and operator-first.
4. Prefer a small number of strong mechanisms over many soft reminders.
5. Preserve the distinction between search activity and inspected evidence.
6. Make delegation, finalization, and recovery legible from one run artifact.

## Where Prompting Should Give Way To Logic

### 1. Delegation discipline

Current state:

- The prompt teaches the model to scout first, keep sub-queries narrow, and avoid broad fan-out.
- Recovery also tries to narrow behavior after failures.

Ideal state:

- Add explicit delegation guards in the runtime.
- Detect when a sub-query receives a large, barely-compressed slice of the parent's context.
- Block or challenge that delegation before it runs.
- Prefer a single batch-level guard for parallel fan-out rather than repeating the same check per sub-query.

Borrowed from `fast-rlm`:

- compression guard
- batch-level delegation review
- stronger parallel delegation primitive

What this changes:

- fewer wasteful broad sub-queries
- fewer prompt-only reminders about chunking
- more consistent recursion cost control

### 2. Final output contract

Current state:

- `rlm` is strong at evidence retrieval and answer presentability checks.
- But final output is still effectively text-only.
- The system prompts for good output shape and rejects some bad finals after the fact.

Ideal state:

- Support structured final outputs as a first-class runtime contract.
- Allow the root run and sub-queries to declare an output schema.
- Validate `FINAL(...)` against that schema.
- Preserve runtime state on schema failure and let the model repair only the output.

Borrowed from `fast-rlm`:

- schema-validated final output
- schema-validated sub-agent output
- repair loop without recomputing work

What this changes:

- less prompt budget spent on output formatting discipline
- less downstream parsing fragility
- tighter tool and pipeline integration

### 3. Grounding convergence

Current state:

- `rlm` already tracks evidence well.
- It already grades grounding and blocks weak finalization.
- But some convergence behavior still depends on prompt language like "stop searching" and "run one challenge pass".

Ideal state:

- Promote more of the convergence logic into policy gates.
- Make the runtime explicitly aware of phases like:
  - scouting
  - promoted reading
  - challenge pass
  - ready to finalize
- Use evidence metrics to decide which transitions are allowed.

This should not remove the prompt guidance.
It should reduce dependence on it.

What this changes:

- fewer late-stage search spirals
- fewer runs that satisfy structural reads without semantic challenge
- clearer ownership of why a run was blocked from finalizing

### 4. Recovery mode behavior

Current state:

- Recovery instructions are already strong.
- Recovery flags already disable some bad strategies after failure.

Ideal state:

- Move more recovery constraints from text into capability toggles and runtime restrictions.
- If async failed once, disable async at the runtime boundary for the rest of the run.
- If grounding recovery is active, narrow available actions toward read promotion and finalization.
- If sub-query budget is exhausted, make further sub-queries impossible rather than merely discouraged.

Borrowed from `fast-rlm`:

- stronger capability gating over repeated instruction

What this changes:

- less repeated recovery prompting
- more reliable post-failure behavior
- clearer proof that the runtime actually changed state after a failure

### 5. Operator-facing observability

Current state:

- `rlm` persists rich run records.
- `rlm` has better post-mortem semantics than `fast-rlm`.
- But the first maintainer question, "what happened in this run?", still takes too much reconstruction.
- Recent run artifacts show the exact problem: they are strong end-of-run snapshots, but weak operator logs.
- A single run JSON already contains useful fields like `failure_history`, `recovery_flags`, `grounding`, and `iteration_records`, but each iteration also embeds large `stdout`, large `raw_response`, and large `details.evidence` payloads.
- That makes the artifact rich for forensic reading but poor for fast diagnosis, diffing, and timeline-style inspection.

Ideal state:

- Every run should have one primary operator artifact.
- That artifact should show:
  - iteration tree
  - sub-query tree
  - code executed
  - stdout/stderr
  - failure and recovery events
- grounding transitions
- finalization decision
- tokens and latency
- reason codes for why the run continued, recovered, blocked finalization, or terminated
- compact evidence-state deltas instead of repeating the full evidence payload on every iteration
- references to large payloads instead of inlining the same giant text repeatedly

More concretely, the primary run artifact should be event-oriented, not only snapshot-oriented.

The saved final JSON should remain, but it should become the summary object, not the only serious debugging object.

An ideal split is:

- one append-only event log for operator inspection
- one compact final summary for post-mortem and storage
- optional large payload sidecars for heavy stdout, provider responses, or rendered evidence bundles

Borrowed from `fast-rlm`:

- one run log format
- quick stats view
- run-tree inspection
- optional TUI or equivalent viewer

What this changes:

- faster debugging
- easier comparison between runs
- less dependence on reading raw JSON plus separate post-mortem output
- less duplication of oversized payloads in each iteration record
- clearer visibility into grounding progression across iterations instead of only the final grade
- clearer visibility into when recovery flags changed and why

## What Still Looks Better In Fast-RLM

These are the concrete areas where `fast-rlm` still represents a cleaner state.

### 1. Run inspection UX

`fast-rlm` has the better first-run operator story:

- one JSONL log
- step-by-step run tree
- simple stats command
- optional TUI viewer

`rlm` has richer semantics, but the ideal state is to make those semantics visible through an equally direct operator interface.

The recent `rlm` run artifacts make the gap concrete:

- they are easy to archive but harder to scan
- they mix summary state with huge per-iteration payloads
- they do not present a clean event timeline
- they do not make grounding transitions, recovery transitions, or finalization blockers visible at a glance

So the logging target is not just "add a viewer." It is to reshape the primary artifact around operator questions:

- what did the model do this iteration?
- what evidence state changed?
- why did policy allow continuation?
- why was finalization blocked?
- what changed after recovery mode activated?

### 2. Structured output enforcement

`fast-rlm` cleanly treats output shape as a runtime contract.

That is better than relying on prompt instructions, presentability heuristics, or downstream parsing.

`rlm` should adopt this directly.

### 3. Delegation controls

`fast-rlm` is cleaner where it turns "please compress before delegating" into actual enforcement.

`rlm` should borrow this pattern while keeping its stronger evidence model.

### 4. Capability inheritance model

`fast-rlm` is explicit about what sub-agents inherit and what they do not.

`rlm` already has strong built-in runtime primitives, but the ideal state is to make capability boundaries just as explicit, inspectable, and enforceable.

## What Should Be Better In `rlm` Than Fast-RLM

The ideal state is not parity.
It is selective superiority.

`rlm` should remain better at:

- evidence-aware retrieval for real corpora
- distinguishing search from inspected evidence
- semantic grounding, not just structural grounding
- recovery tied to failure class
- provider reliability and timeout taxonomy
- post-mortem review and regression extraction
- JSON, JSONL, log, and mixed file-backed corpus handling
- judgment protocols like Compass when they are actually useful

## The Missing Layer

The biggest missing object is not another prompt.

It is a maintainer-facing operating layer that unifies the controls the system already has.

The ideal state document should correspond to an ideal state artifact in the runtime itself:

- a stable run diagnosis view
- one primary run log
- explicit grounding phase/status
- explicit recovery phase/status
- explicit finalization decision report
- explicit reason a sub-query was allowed, blocked, or challenged

That is the point where the repo stops feeling like several strong subsystems and starts feeling like one coherent runtime.

## Concrete Priorities

If we are serious about moving from prompt pressure to runtime logic, the next priorities should be:

1. Add structured output schemas for root answers and sub-queries.
2. Add delegation compression guards and batch fan-out controls.
3. Add a first-class run log and viewer that surfaces iteration, sub-query, grounding, and recovery state in one place.
4. Convert more recovery instructions into enforced capability toggles.
5. Make grounding phase transitions explicit in policy rather than mostly rhetorical in prompts.

## Implementation Realities

Not every ideal-state item has the same implementation cost.

Some are close extensions of the current architecture.
Some cut across the runtime protocol and result model.

This section exists to keep the document actionable.

### Lower-friction changes

These are areas where the current code already provides strong hooks.

#### 1. Event-oriented logging

Why it is relatively close:

- the engine already emits `:iteration_start`, `:generated_code`, and `:iteration_output` events
- the CLI already consumes `on_event`
- the runtime/primitives path already emits events like `:sub_query_start`, `:sub_query_complete`, `:inspect_context`, and `:final_answer`

Relevant code:

- `lib/rlm/engine/iteration.ex`
- `lib/rlm/engine/finalizer.ex`
- `lib/rlm/runtime/primitives.ex`
- `lib/rlm/cli/events.ex`

What the evidence suggests:

- the repo already has an event seam
- the missing part is breadth and persistence, not a fresh architecture
- this means a first-class event log is more of an extension than a rewrite

What is still missing:

- grounding-transition events
- recovery-flag-change events
- finalization-blocked events with reason codes
- persistence of the event stream as a primary run artifact

#### 2. Explicit grounding phases

Why it is relatively close:

- grounding already has structural grades
- grounding already has semantic grades
- search-promotion and finalization checks already exist
- `assess_evidence()` already computes an implicit next-step model

Relevant code:

- `lib/rlm/engine/grounding/policy.ex`
- `lib/rlm/engine/grounding/grade.ex`
- `priv/runtime/evidence.py`

What the evidence suggests:

- the phase model is already present in logic, just not surfaced as a named state machine
- making phases explicit should mostly be a packaging and policy-state change, not a conceptual invention

Likely target phases:

- scout
- retrieve
- promote_reads
- challenge
- finalize_ready
- blocked

#### 3. Recovery enforcement

Why it is relatively close:

- recovery flags already exist in run state
- failure classes already map to those flags
- recovery feedback is already separated from ordinary iteration feedback

Relevant code:

- `lib/rlm/engine/run_state.ex`
- `lib/rlm/engine/recovery/strategy.ex`
- `lib/rlm/engine/prompt/recovery_constraints.ex`

What the evidence suggests:

- the architecture already distinguishes "policy flag exists" from "prompt tells the model what that means"
- the real gap is that these flags are mostly consumed by prompt text today

That makes this area medium difficulty, not speculative difficulty.

### Medium-friction changes

These have good insertion points, but the current implementation does not yet carry enough structure to make them trivial.

#### 4. Delegation guards

Why this is plausible:

- every sub-query already crosses one narrow boundary: `llm_query()` in `priv/runtime/protocol.py`
- all sub-query execution is routed through `SubqueryTasks`
- sub-query budget is already enforced centrally

Relevant code:

- `priv/runtime/protocol.py`
- `lib/rlm/runtime/python_repl/subquery_tasks.ex`
- `lib/rlm/engine/iteration.ex`

What the evidence suggests:

- there is already a single choke point where delegation can be observed and constrained
- that makes guards feasible without redesigning the whole runtime

What makes it non-trivial:

- current `llm_query()` only receives `sub_context` and `instruction`
- it does not carry parent-context size, compression metadata, or batch shape
- parallel fan-out today is just Python-level concurrency over `async_llm_query`, not a dedicated batch primitive

So the likely path is:

- add delegation metadata first
- then add runtime guard logic
- then add a dedicated batch/fan-out primitive if needed

#### 5. Capability boundaries

Why this is plausible:

- the Python surface is centralized in `namespace.py`
- built-in helper exposure is already explicit

Relevant code:

- `priv/runtime/namespace.py`
- `priv/runtime/README.md`

What the evidence suggests:

- capability boundaries are already explicit in code layout
- but they are not yet configurable per run, per recovery state, or per sub-query mode

What makes it non-trivial:

- built-ins are currently global for the run namespace
- sub-queries are provider-side text calls, not nested Python runtimes with their own capability tables
- recovery flags do not yet flow into namespace-level helper gating

So this is a good target, but not a one-file change.

### Higher-friction changes

These are still worth doing, but they cross deeper assumptions in the current runtime model.

#### 6. Structured final outputs and structured sub-query outputs

Why this is harder than it first appears:

- `FINAL(...)` currently coerces to string
- `FINAL_VAR(...)` also coerces to string
- sub-query results are normalized as `%{status: "ok", text: text}`
- provider sub-queries are natural-language-only today

Relevant code:

- `priv/runtime/namespace.py`
- `priv/runtime/state.py`
- `priv/runtime/exec.py`
- `priv/runtime/protocol.py`
- `lib/rlm/runtime/python_repl/subquery_tasks.ex`
- `lib/rlm/providers/openai.ex`

What the evidence suggests:

- this is not just a validator addition
- it requires changing the runtime result model from "final answer is text" to "final answer may be a JSON-compatible value"
- it also requires deciding whether sub-queries remain plain natural-language completions or become structured return channels

This should still happen.
It is just more invasive than the logging or grounding-phase work.

#### 7. Fully replacing prompt-based convergence with enforcement

Why this is the hardest category:

- the current system already uses rich logic to grade and block
- but some strategy concepts still only exist as rhetoric in prompts, not as explicit state transitions or allowed-action rules
- the current model still has broad freedom inside each Python block

What the evidence suggests:

- the ideal state is not to delete strategic prompting
- it is to move only the repeated, stable, checkable parts into logic first

That means the practical order should be:

1. add explicit state and events
2. add runtime gates for obvious violations
3. keep prompts for higher-level strategy that is not yet stable enough to encode rigidly

## What More Evidence Would Sharpen

Some ideal-state items already have enough evidence to move.
Some would benefit from one more focused pass.

### Evidence we already have enough of

- logging needs an event-first artifact
- recovery flags should become more enforceable than prompt-only
- grounding phases are already implicit enough to formalize

### Evidence that would sharpen design before implementation

#### 1. Delegation guards

Useful next evidence:

- inspect several runs with heavy `async_llm_query` or broad sub-query usage
- measure how often large sub-contexts are handed to sub-queries
- classify whether bad fan-out is mostly breadth, poor compression, or unnecessary sub-queries

Why:

- this will determine whether the first mechanism should be a size guard, a batch primitive, or a more specific recovery-driven block

#### 2. Structured outputs

Useful next evidence:

- search runs and call sites that would benefit from non-text finals
- identify whether the real need is typed root outputs, typed sub-queries, or both
- inspect any downstream consumers that currently parse answer text

Why:

- this determines whether to start with root-only schema validation or a larger protocol change

#### 3. Capability gating

Useful next evidence:

- inspect which helpers are actually misused in failed or recovered runs
- determine whether gating should focus first on async, broad search, or sub-query issuance itself

Why:

- the current namespace is explicit, but over-gating the wrong helper would add complexity without enough benefit

## Short Version

The ideal state for `rlm` is:

- keep the strong evidence model
- keep the strong recovery and provider model
- reduce dependence on behavioral prompting
- add more hard runtime contracts
- make run diagnosis operator-first

That is the right borrowing from `fast-rlm`.

Not simpler prompts.
Stronger mechanisms.
