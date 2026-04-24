# rlm

This repository contains a Nix-first Elixir implementation of a Recursive Language Model CLI.

The Mix project lives in `src/`. Inside it, the code is organized by system boundary so the main flow is easy to follow:

- `lib/rlm/cli.ex` and `lib/rlm/cli/`: CLI entrypoints
- `lib/rlm/engine.ex` and `lib/rlm/engine/`: orchestration, policy, recovery, and run state
- `lib/rlm/context/`: context loading
- `lib/rlm/runtime/`: Python runtime bridge
- `lib/rlm/providers/`: provider behavior and implementations
- `lib/rlm/storage/`: saved run artifacts

Quick start:

```bash
nix develop
cd src
mix deps.get
mix compile
mix test
mix rlm --provider mock --text "Hello from RLM" "What is this context?"
```

See `src/README.md` for the CLI workflow and Home Manager-managed configuration.

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
