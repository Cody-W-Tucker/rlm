# Runtime

The Python runtime is a persistent subprocess that executes model-authored Python and talks to Elixir over line-delimited JSON.

## Flow

```text
Rlm.Runtime.PythonRepl
  -> launches priv/runtime.py
  -> runtime/main.py event loop
  -> exec request runs code in a persistent namespace
  -> runtime may emit llm_query messages back to Elixir
  -> runtime returns exec_done with stdout/stderr/final/evidence
```

## Protocol

Main message types:

- `ready`
- `set_context`
- `set_file_sources`
- `reset_final`
- `exec`
- `llm_query`
- `llm_result`
- `exec_done`
- `shutdown`

## Module Map

- `runtime.py`: thin entrypoint that bootstraps the internal package
- `runtime/main.py`: stdin thread and command loop
- `runtime/protocol.py`: request/result coordination for sub-queries
- `runtime/exec.py`: direct exec, async-wrapper fallback, final-value recovery, result shaping
- `runtime/namespace.py`: Python symbols exposed to model-authored code
- `runtime/state.py`: mutable runtime state and evidence tracking
- `runtime/files.py`: file listing, reading, previewing
- `runtime/search.py`: grep helpers and hit objects
- `runtime/jsonl.py`: JSONL sampling and field-aware search

## Exposed Python Surface

- `context`
- `list_files`, `sample_files`
- `read_file`, `peek_file`
- `grep_files`, `grep_open`, `peek_hit`, `open_hit`
- `read_jsonl`, `sample_jsonl`, `grep_jsonl_fields`
- `llm_query`, `async_llm_query`
- `FINAL`, `FINAL_VAR`

## Recovery Behavior

- Try direct `exec` first.
- If needed, retry through the async wrapper for top-level `await` patterns.
- Recover malformed triple-quoted `FINAL("""...` output when possible.
- Include evidence about searches, previews, and reads in `exec_done.details.evidence`.

## Where To Edit

- Add or change runtime-exposed helpers: `namespace.py` plus the relevant helper module
- Change execution or recovery behavior: `exec.py`
- Change protocol messaging: `protocol.py`
- Change file/search/JSONL capabilities: `files.py`, `search.py`, `jsonl.py`
