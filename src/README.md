# RLM CLI in Elixir

This directory contains the Elixir implementation of the Recursive Language Model CLI described in `python-example/`, adapted for a CLI-first, Nix-managed workflow.

## Development Setup

From the repository root:

```bash
nix develop
cd src
mix deps.get
mix compile
mix test
```

The flake shell includes Elixir, Erlang, Python 3, `curl`, and `jq`.

## Running the CLI

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

This implementation follows the paper's REPL flow instead of the earlier action-plan MVP:

1. Context is loaded from files, directories, globs, URLs, inline text, or stdin.
2. The full context is injected into a persistent Python REPL as `context`.
3. The root model receives only metadata plus the user query and returns Python code.
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
The Nix code lives under `../nix/`.

Example Home Manager configuration:

```nix
{
  imports = [ inputs.rlm.homeManagerModules.default ];

  programs.rlm = {
    enable = true;
    model = "gpt-4o-mini";
    subModel = "gpt-4o-mini";
    apiKeyFile = "${config.xdg.configHome}/rlm/openai-api-key";
    openaiBaseUrl = "https://api.openai.com/v1";
    runtimeCommand = [ "${pkgs.python3}/bin/python3" ];
    storageDir = "${config.xdg.dataHome}/rlm/runs";
  };
}
```

The flake also exports `packages.<system>.default` and `apps.<system>.default`, both backed by `nix/packages/rlm.nix`.

Example `/etc/rlm/config.exs`:

```elixir
import Config

config :rlm, Rlm.RLM.Settings,
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

The CLI enforces conservative defaults:

- up to 100 loaded files per run
- up to 10 MB of aggregate context text
- bounded root iterations and sub-query count
- truncated execution feedback between iterations

## Testing

```bash
mix test
```

## Notes

- `openai` is the only real provider integration right now.
- `mock` exists for local development and tests.
- Recursion currently matches the reference example's flat sub-call model: the root uses a persistent REPL and sub-queries are plain model calls.
