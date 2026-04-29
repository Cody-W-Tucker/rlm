# rlm

Most RLMs show what recursion can do.

We show what recursion looks like when it is engineered to be grounded, inspectable, and sustainable.

## Typical RLM

The promise of the RLM pattern is compelling:

The model have the room to search, inspect, narrow, test, and refine before finalizing.

1. Load a corpus or working context.
2. Let the model decide what to do next.
3. Give it tools to investigate.
4. Feed the results back into the loop.
5. Stop when it has enough evidence to answer.

### Problems

Many RLM-style systems can produce impressive demos, but they often break in the places that matter most:

- they recurse without meaningful control
- they search without distinguishing search from evidence
- they retry without structured recovery
- they hide state inside the loop
- they blur policy and execution
- they become costly, fragile, and hard to trust over time

## Grounded Policy-Based RLM

We enforce search policies and grounding techniques that grades the subagent's work and inform next steps.

So, if a model...

- only searched
- previewed likely sources, without reading enough surrounded context
- never actually read files it searched through

Answers can be challenged. Unsupported citations can be blocked.

This is why the system is more trustworthy: it is designed to make the model earn its conclusions.

## What Serious Practitioners Notice

Experienced practitioners will recognize that this repository is solving the harder RLM problem.

- Grounding is operationalized, not hand-waved.
- Recovery is structured, not ad hoc.
- Iteration and sub-query behavior are bounded.
- The runtime is persistent, so work can accumulate across steps.
- Runs are stored, so the trajectory is inspectable after the fact.
- One-shot and interactive usage share the same execution flow.

These are the difference between a recursive system that looks capable and one that stays usable under real conditions.

## Sustainable Recovery And Orchestration

When models write code, failures are inevitable. Most RLM systems handle this poorly: they pass errors to the next iteration and hope the model figures it out.

The real challenge is not making a model do something clever once. It is making recursive behavior reliable enough to operate, recover, debug, and evolve over time.

`rlm` treats recovery as a core design constraint, not an afterthought:

- **bounded iterations** instead of open-ended loops
- **bounded sub-queries** instead of runaway decomposition
- **structured recovery** instead of blind retrying
- **truncated feedback** so each step stays legible
- **explicit runtime boundaries** between orchestration and execution
- **persisted run records** so behavior can be inspected later

These policies prevent recursion from drifting into cost blowups, fake certainty, or opaque behavior.

### Why Elixir

`rlm` is implemented in Elixir because reliable recursion depends on orchestration quality as much as model quality.

Elixir provides exactly what this problem needs:

- supervision of long-lived processes and isolated components
- timeouts, failures, and retries as first-class operational concerns
- explicit message boundaries instead of hidden control flow
- systems that stay inspectable as they become more recursive

## Nix-Only Getting Started

This project is Nix-first and the supported setup path is Nix.

Use the flake as an input when you want `rlm` installed and configured as part of your NixOS or Home Manager setup.

```nix
{
  inputs.rlm.url = "github:codyt/rlm";
}
```

Home Manager can then import the module:

```nix
{
  imports = [ inputs.rlm.homeManagerModules.default ];

  programs.rlm = {
    enable = true;
    model = "gpt-5.4-mini";
    apiKeyFile = "${config.xdg.configHome}/rlm/openai-api-key";
    openaiBaseUrl = "https://api.openai.com/v1";
  };
}
```

## Run Examples

```bash
rlm --file README.md "Summarize this file"
rlm --file lib/**/*.ex "Explain the runtime flow"
rlm --url https://example.com/data.txt "Extract the main idea"
printf 'alpha\nbeta\n' | rlm --stdin "What is in stdin?"
```
