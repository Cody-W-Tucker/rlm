# rlm

This repository contains a Nix-first Elixir implementation of a Recursive Language Model CLI.

The Mix project lives at the repository root. The code is organized by system boundary so the main flow is easy to follow:

- `lib/rlm/cli.ex` and `lib/rlm/cli/`: CLI entrypoints
- `lib/rlm/engine.ex` and `lib/rlm/engine/`: orchestration, policy, recovery, and run state
- `lib/rlm/context/`: context loading
- `lib/rlm/runtime/`: Python runtime bridge
- `lib/rlm/providers/`: provider behavior and implementations
- `lib/rlm/storage/`: saved run artifacts

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
  runtime_command: ["/run/current-system/sw/bin/python3"],
  storage_dir: "/var/lib/rlm/runs"
```

Important settings:

- `provider`
- `model`
- `sub_model`
- `api_key`
- `openai_base_url`
- `runtime_command`
- `max_iterations`
- `max_sub_queries`
- `truncate_length`
- `metadata_preview_lines`
- `max_context_bytes`
- `max_context_files`
- `storage_dir`

## Safety Limits

- up to 100 loaded files per run
- up to 10 MB of aggregate context text
- bounded root iterations and sub-query count
- truncated execution feedback between iterations

## Testing

```bash
mix test
```
