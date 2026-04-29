# rlm

This repository contains a Nix-first Elixir implementation of a Recursive Language Model CLI.

Quick start:

```bash
nix develop
mix deps.get
mix compile
mix test
mix rlm --provider mock --text "Hello from RLM" "What is this context?"
```

Nix layout:

- `nix/modules/rlm.nix`: Home Manager module and options
- `nix/packages/rlm.nix`: default flake package

Home Manager module:

```nix
{
  imports = [ inputs.rlm.homeManagerModules.default ];

  programs.rlm = {
    enable = true;
    model = "gpt-4o-mini";
    apiKeyFile = "${config.xdg.configHome}/rlm/openai-api-key";
    openaiBaseUrl = "https://api.openai.com/v1";
  };
}
```

Flake package:

```bash
nix run .#rlm -- --provider mock --text "hello" "what is this?"
```

## Running The CLI

Everything is one-shot. The command writes the final answer to stdout and persists a JSON trajectory for later inspection.

```bash
mix rlm --provider mock --text "Example context" "What does this describe?"
mix rlm --file lib/rlm/cli.ex "Summarize this module"
mix rlm --file lib/**/*.ex "Explain the runtime flow"
mix rlm --url https://example.com/data.txt "Extract the main idea"
printf 'alpha\nbeta\n' | mix rlm --stdin "What is in stdin?"
```

`run` remains as an alias:

```bash
mix rlm run --file README.md "Summarize this file"
```

## How It Works

1. Context is loaded from files, directories, globs, URLs, inline text, or stdin.
2. The full context is injected into a persistent Python REPL as `context`.
3. The root model receives metadata plus the user query and returns Python code.
4. The Python runtime executes that code, exposing `llm_query()`, `async_llm_query()`, `FINAL()`, and `FINAL_VAR()`.
5. Printed output and stderr are fed back into the next root-model iteration.
6. The run stops when the Python runtime sets a final value or a configured limit is reached.

Each finished run is saved as JSON under the configured storage directory.

## Architecture

The project is split into a small number of layers with explicit responsibilities.

```text
CLI / Session
  -> Context loading and normalization
  -> Engine orchestration
  -> Provider request/stream handling
  -> Persistent Python runtime
```

### CLI Layer

- `lib/rlm/cli.ex`: one-shot CLI entrypoint
- `lib/rlm/cli/session.ex`: interactive session loop and slash commands
- `lib/rlm/cli/context.ex`: shared context loading and merging helpers
- `lib/rlm/cli/runner.ex`: shared run-and-persist flow
- `lib/rlm/cli/events.ex`: shared event formatting for stderr and interactive output

This layer is responsible for user-facing I/O, not execution policy.

### Context Layer

- `lib/rlm/context/loader.ex`: loads files, directories, globs, URLs, pasted text, and stdin-backed content into a normalized bundle

The engine consumes a context bundle instead of dealing with raw file or URL inputs directly.

### Engine Layer

- `lib/rlm/engine.ex`: facade for a single run
- `lib/rlm/engine/iteration.ex`: main loop, recovery path, and sub-query flow
- `lib/rlm/engine/finalizer.ex`: result shaping and partial/failure rendering
- `lib/rlm/engine/failure.ex`: structured failure classification
- `lib/rlm/engine/recovery.ex`: recovery policy
- `lib/rlm/engine/prompt/`: prompt generation and iteration feedback
- `lib/rlm/engine/grounding/`: file-backed grounding validation and grading

This layer decides whether a run should continue, recover, or finalize.

See `lib/rlm/engine/README.md` for a focused engine map.

### Provider Layer

- `lib/rlm/providers/openai.ex`: OpenAI-compatible request construction
- `lib/rlm/providers/request_manager.ex`: streamed response collection, timeout handling, and partial-output retention

The provider layer turns model API responses into plain text for the engine.

### Runtime Bridge

- `lib/rlm/runtime/python_repl.ex`: GenServer facade around the Python subprocess
- `lib/rlm/runtime/python_repl/`: protocol, port, state, and sub-query task helpers
- `priv/runtime.py`: thin Python entrypoint
- `priv/runtime/`: Python runtime internals

This layer is the boundary between Elixir orchestration and persistent Python execution.

See `priv/runtime/README.md` for the runtime protocol and Python module map.

## Run Flow

For a normal one-shot CLI run:

1. `Rlm.CLI` parses args and builds settings.
2. `Rlm.CLI.Context` loads inputs into a context bundle.
3. `Rlm.CLI.Runner` calls `Rlm.Engine.run/5`.
4. `Rlm.Engine` starts `RunState` and `PythonRepl`.
5. `Rlm.Engine.Iteration` asks the provider for Python code.
6. `Rlm.Engine.Execution.BlockRunner` executes the returned code in the persistent Python runtime.
7. The Python runtime may call back into Elixir with `llm_query` sub-queries.
8. The engine classifies the runtime result and either:
   - finalizes,
   - recovers with a stricter next step, or
   - continues to another iteration.
9. `Rlm.CLI.Runner` persists the final run record through `RunStore`.

## Special Patterns

These patterns are intentional and are the main ways the project stays manageable.

### Thin Facades Over Focused Modules

Top-level modules now stay small and stable while detailed behavior moves behind them.

Examples:

- `Rlm.Engine` delegates to `Iteration` and `Finalizer`
- `Rlm.Runtime.PythonRepl` delegates to protocol, port, and task helpers
- `priv/runtime.py` delegates to `priv/runtime/`

This keeps public entrypoints stable while making internal changes safer.

### Persistent Python Runtime Instead Of One Process Per Block

The runtime keeps namespace state across iterations and code blocks.

That enables:

- multi-block execution in one iteration
- top-level variable reuse
- async sub-query coordination
- targeted file inspection without rehydrating everything each time

### Model Writes Code, Not Final Prose First

The root model produces Python, not just an answer string.

That allows the system to:

- search the corpus
- inspect files directly
- run sub-queries selectively
- record evidence and grounding behavior
- distinguish between scout-only and read-backed answers

### Recovery Is Structured, Not Ad Hoc

The engine does not just retry blindly.

It classifies failures, records them, and applies a constrained recovery strategy.

Examples:

- malformed or partial Python output can still be salvaged
- top-level `await` falls back through an async wrapper
- weak grounding can trigger a stricter follow-up iteration
- provider partial output can still become the best partial answer

### File-Backed Grounding Is Explicit

For file-backed corpora, the system tracks whether the model only searched, previewed, or actually read files.

This supports:

- grounding grades
- blocking unsupported file citations
- preferring read-backed final answers over scout-only synthesis

### Shared Flow For One-Shot And Interactive Modes

One-shot CLI and interactive session mode now share:

- context normalization
- run execution and persistence
- event formatting

That reduces behavior drift between entrypoints.

### Line-Delimited JSON Across The Elixir/Python Boundary

The Elixir runtime bridge and the Python subprocess communicate using a small line-delimited JSON protocol.

That gives the project:

- a debuggable boundary
- explicit message types
- recoverable subprocess failures
- a clean place to evolve runtime capabilities without entangling them with engine policy

## Configuration

Configuration is loaded from Elixir application config, not shell environment variables.

Defaults live in `config/config.exs`.

At runtime the app also imports either of these files when present:

- `/etc/rlm/config.exs`
- `~/.config/rlm/config.exs`

That lets Home Manager manage credentials, the OpenAI-compatible provider endpoint, model selection, the Python command, and storage paths declaratively.

If you use this repository as a flake input, it exports `homeManagerModules.default` and `homeManagerModules.rlm`.

Example `/etc/rlm/config.exs`:

```elixir
import Config

config :rlm, Rlm.Settings,
  provider: :openai,
  model: "gpt-4o-mini",
  sub_model: "gpt-4o-mini",
  api_key: "sk-...",
  openai_base_url: "https://api.openai.com/v1",
  connect_timeout: 5000,
  first_byte_timeout: 30000,
  idle_timeout: 15000,
  total_timeout: 120000,
  runtime_command: ["/run/current-system/sw/bin/python3"],
  storage_dir: "/var/lib/rlm/runs"
```

Important settings:

- `provider`
- `model`
- `sub_model`
- `api_key`
- `openai_base_url`
- `connect_timeout`
- `first_byte_timeout`
- `idle_timeout`
- `total_timeout`
- `runtime_command`
- `max_iterations`
- `max_sub_queries`
- `truncate_length`
- `max_context_bytes`
- `max_lazy_file_bytes`
- `max_context_files`
- `storage_dir`

## Safety Limits

- up to 1000 loaded files per run
- up to 50 MB of aggregate preloaded context text
- up to 500 MB per lazy file-backed source
- bounded root iterations and sub-query count
- truncated execution feedback between iterations

## Testing

```bash
mix test
```
