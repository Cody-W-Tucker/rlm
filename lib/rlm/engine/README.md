# Engine

`Rlm.Engine` runs one end-to-end model execution against the persistent Python runtime.

## Flow

```text
CLI / Session
  -> Rlm.Engine.run/5
  -> Rlm.Runtime.PythonRepl.start/2
  -> Rlm.Engine.Iteration.run/7
  -> provider generates Python
  -> Rlm.Engine.Execution.BlockRunner executes blocks
  -> runtime result is classified
  -> finalize / recover / continue
  -> Rlm.Engine.Finalizer builds the result
```

## Module Map

- `engine.ex`: top-level facade, run state lifecycle, Python REPL setup
- `iteration.ex`: iteration loop, recovery flow, sub-query handler
- `finalizer.ex`: final result shaping, incomplete/failure rendering, iteration output events
- `execution/block_runner.ex`: executes one or more code blocks against the Python runtime
- `runtime_outcome.ex`: classifies runtime results before policy decides next action
- `failure.ex`: structured failure classification
- `recovery.ex`: recovery policy and feedback
- `prompt/`: system prompt, context metadata, and iteration feedback generation
- `grounding/`: file-backed answer validation and grounding grades

## State And Data

- `RunState` tracks token usage, best partial answer, recovery flags, failures, and sub-query metadata.
- Providers return Python code, not final prose.
- Python stdout, stderr, final values, and evidence come back through `PythonRepl`.
- `Iteration` decides whether to finalize, recover, or continue.

## Where To Edit

- Change iteration behavior: `iteration.ex`
- Change result fields or partial-answer rendering: `finalizer.ex`
- Change failure or recovery behavior: `failure.ex`, `recovery.ex`
- Change prompt policy: `prompt/`
- Change grounding rules: `grounding/policy.ex`
