# Iteration Loop and Finalization
Relevant source files
- [lib/rlm/engine/answer_quality.ex](https://github.com/Cody-W-Tucker/rlm/blob/4bc8e1ba/lib/rlm/engine/answer_quality.ex)
- [lib/rlm/engine/failure.ex](https://github.com/Cody-W-Tucker/rlm/blob/4bc8e1ba/lib/rlm/engine/failure.ex)
- [lib/rlm/engine/finalizer.ex](https://github.com/Cody-W-Tucker/rlm/blob/4bc8e1ba/lib/rlm/engine/finalizer.ex)
- [lib/rlm/engine/iteration.ex](https://github.com/Cody-W-Tucker/rlm/blob/4bc8e1ba/lib/rlm/engine/iteration.ex)
- [lib/rlm/engine/run_state.ex](https://github.com/Cody-W-Tucker/rlm/blob/4bc8e1ba/lib/rlm/engine/run_state.ex)
- [priv/runtime/jsondoc.py](https://github.com/Cody-W-Tucker/rlm/blob/4bc8e1ba/priv/runtime/jsondoc.py)
- [priv/runtime/protocol.py](https://github.com/Cody-W-Tucker/rlm/blob/4bc8e1ba/priv/runtime/protocol.py)
- [test/rlm/engine/core_runtime_test.exs](https://github.com/Cody-W-Tucker/rlm/blob/4bc8e1ba/test/rlm/engine/core_runtime_test.exs)

The iteration loop is the core orchestration mechanism of the RLM engine. It manages the recursive transition between LLM code generation, Python execution, and result verification. This process continues until a grounded answer is produced, a terminal error occurs, or the iteration budget is exhausted.

## The Iteration Lifecycle

The `Rlm.Engine.Iteration` module implements the primary loop through `execute_iterations/11`[lib/rlm/engine/iteration.ex54-89](https://github.com/Cody-W-Tucker/rlm/blob/4bc8e1ba/lib/rlm/engine/iteration.ex#L54-L89) Each turn of the loop follows a "Generate-Execute-Verify" pattern:

1. **Prompt Assembly**: The system prompt is dynamically constructed based on the current iteration count and a `snapshot` of the `RunState`[lib/rlm/engine/iteration.ex90-91](https://github.com/Cody-W-Tucker/rlm/blob/4bc8e1ba/lib/rlm/engine/iteration.ex#L90-L91)
2. **Code Generation**: The provider module (e.g., OpenAI) generates Python code intended to explore the context or finalize an answer [lib/rlm/engine/iteration.ex95-96](https://github.com/Cody-W-Tucker/rlm/blob/4bc8e1ba/lib/rlm/engine/iteration.ex#L95-L96)
3. **Extraction**: Raw text from the provider is parsed into executable Python blocks using `Rlm.Engine.Response.Extractor`[lib/rlm/engine/iteration.ex143-144](https://github.com/Cody-W-Tucker/rlm/blob/4bc8e1ba/lib/rlm/engine/iteration.ex#L143-L144)
4. **Execution**: Code blocks are sent to the persistent Python REPL via `Rlm.Engine.Execution.BlockRunner`[lib/rlm/engine/iteration.ex148-149](https://github.com/Cody-W-Tucker/rlm/blob/4bc8e1ba/lib/rlm/engine/iteration.ex#L148-L149)
5. **Classification**: The outcome is evaluated to determine if the run should `finalize`, `continue`, `recover`, or `fail`[lib/rlm/engine/iteration.ex182-232](https://github.com/Cody-W-Tucker/rlm/blob/4bc8e1ba/lib/rlm/engine/iteration.ex#L182-L232)

### Data Flow: Iteration to Finalization

The following diagram bridges the high-level iteration logic to the specific Elixir modules and functions that manage the state transitions.

**Diagram: Rlm.Engine.Iteration Logic Flow**

```

```

## Result Classification

After code execution, `classify_exec_result/4` determines the next state [lib/rlm/engine/iteration.ex182](https://github.com/Cody-W-Tucker/rlm/blob/4bc8e1ba/lib/rlm/engine/iteration.ex#L182-L182)

| Classification | Condition | Outcome |
| --- | --- | --- |
| **Finalized** | Code called `FINAL(value)` and passed grounding policy. | Loop terminates; `Finalizer` shapes the output struct. |
| **Continue** | Code executed successfully but did not call `FINAL()`. | A new iteration starts with updated history. |
| **Recoverable Failure** | A runtime error or format violation occurred that matches a recovery strategy. | `Rlm.Engine.Recovery` injects advice into the next prompt. |
| **Unrecoverable Failure** | Budget exhaustion or fatal provider/runtime errors. | Loop terminates with an error result. |

Sources: `<FileRef file-url="https://github.com/Cody-W-Tucker/rlm/blob/4bc8e1ba/lib/rlm/engine/iteration.ex#L182-L232" min=182 max=232 file-path="lib/rlm/engine/iteration.ex">Hii</FileRef>`

## Handling Failures and Recovery

Failures are converted into structured `Rlm.Engine.Failure` structs [lib/rlm/engine/failure.ex1-6](https://github.com/Cody-W-Tucker/rlm/blob/4bc8e1ba/lib/rlm/engine/failure.ex#L1-L6) The engine distinguishes between provider errors (timeouts, rate limits) and runtime errors (Python syntax errors, exceptions) [lib/rlm/engine/failure.ex10-27](https://github.com/Cody-W-Tucker/rlm/blob/4bc8e1ba/lib/rlm/engine/failure.ex#L10-L27)

If a failure occurs during execution, the engine attempts to "salvage" the run:

- **Runtime Hints**: If a specific known error occurs (e.g., incorrect `read_file` usage), the failure logic appends a "Hint" to the message sent back to the LLM [lib/rlm/engine/failure.ex104-121](https://github.com/Cody-W-Tucker/rlm/blob/4bc8e1ba/lib/rlm/engine/failure.ex#L104-L121)
- **Partial Answers**: If the run fails but a "best so far" answer exists in the `RunState`, the engine may promote this to the final output instead of returning a raw error [lib/rlm/engine/run_state.ex94-106](https://github.com/Cody-W-Tucker/rlm/blob/4bc8e1ba/lib/rlm/engine/run_state.ex#L94-L106)

Sources: `<FileRef file-url="https://github.com/Cody-W-Tucker/rlm/blob/4bc8e1ba/lib/rlm/engine/failure.ex#L10-L121" min=10 max=121 file-path="lib/rlm/engine/failure.ex">Hii</FileRef> <FileRef file-url="https://github.com/Cody-W-Tucker/rlm/blob/4bc8e1ba/lib/rlm/engine/run_state.ex#L94-L106" min=94 max=106 file-path="lib/rlm/engine/run_state.ex">Hii</FileRef>`

## Finalization and Output Shaping

The `Rlm.Engine.Finalizer` is responsible for transforming the internal `RunState` and iteration history into the final result struct returned to the user [lib/rlm/engine/finalizer.ex9-18](https://github.com/Cody-W-Tucker/rlm/blob/4bc8e1ba/lib/rlm/engine/finalizer.ex#L9-L18)

### The Final Result Struct

The output includes comprehensive metadata for post-mortem analysis:

- **Answer**: The string value passed to `FINAL()` or the best partial answer [lib/rlm/engine/finalizer.ex26](https://github.com/Cody-W-Tucker/rlm/blob/4bc8e1ba/lib/rlm/engine/finalizer.ex#L26-L26)
- **Grounding**: A grade (A-F) and semantic level produced by `GroundingGrade.assess/2`[lib/rlm/engine/finalizer.ex20](https://github.com/Cody-W-Tucker/rlm/blob/4bc8e1ba/lib/rlm/engine/finalizer.ex#L20-L20)
- **Compass**: The final diagnostic judgment and verification strings extracted from execution details [lib/rlm/engine/finalizer.ex21-22](https://github.com/Cody-W-Tucker/rlm/blob/4bc8e1ba/lib/rlm/engine/finalizer.ex#L21-L22)
- **Stats**: Token counts (`input_tokens`, `output_tokens`) and total sub-queries [lib/rlm/engine/finalizer.ex30-32](https://github.com/Cody-W-Tucker/rlm/blob/4bc8e1ba/lib/rlm/engine/finalizer.ex#L30-L32)
- **Iteration Records**: A complete log of every code block executed, its stdout/stderr, and its status [lib/rlm/engine/finalizer.ex42](https://github.com/Cody-W-Tucker/rlm/blob/4bc8e1ba/lib/rlm/engine/finalizer.ex#L42-L42)

### Incomplete and Error Results

If the loop hits `max_iterations`, `finalize_incomplete_result/6` is called [lib/rlm/engine/finalizer.ex46](https://github.com/Cody-W-Tucker/rlm/blob/4bc8e1ba/lib/rlm/engine/finalizer.ex#L46-L46) It uses `AnswerQuality.presentable?/1` to check if the `best_answer_so_far` looks like a real answer or just raw instrumentation/logs [lib/rlm/engine/answer_quality.ex18-69](https://github.com/Cody-W-Tucker/rlm/blob/4bc8e1ba/lib/rlm/engine/answer_quality.ex#L18-L69) If unpresentable, it returns a standard "iteration limit reached" message [lib/rlm/engine/finalizer.ex52](https://github.com/Cody-W-Tucker/rlm/blob/4bc8e1ba/lib/rlm/engine/finalizer.ex#L52-L52)

**Diagram: RunState and Finalization Bridge**

```

```

Sources: `<FileRef file-url="https://github.com/Cody-W-Tucker/rlm/blob/4bc8e1ba/lib/rlm/engine/finalizer.ex#L9-L79" min=9 max=79 file-path="lib/rlm/engine/finalizer.ex">Hii</FileRef> <FileRef file-url="https://github.com/Cody-W-Tucker/rlm/blob/4bc8e1ba/lib/rlm/engine/run_state.ex#L7-L24" min=7 max=24 file-path="lib/rlm/engine/run_state.ex">Hii</FileRef> <FileRef file-url="https://github.com/Cody-W-Tucker/rlm/blob/4bc8e1ba/lib/rlm/engine/answer_quality.ex#L18-L69" min=18 max=69 file-path="lib/rlm/engine/answer_quality.ex">Hii</FileRef>`