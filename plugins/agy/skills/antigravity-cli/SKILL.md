---
name: antigravity-cli
description: Internal runtime contract for invoking the Antigravity CLI (`agy`) from the `agy` subagent. Not user-invocable.
user-invocable: false
---

# Antigravity CLI runtime

Use this skill only inside the `agy` subagent.

## Primary helper

```
bash "${CLAUDE_PLUGIN_ROOT}/scripts/agy-run.sh" ask [--model <model>] [agy-flags...] <<'PROMPT_EOF2'
<prompt>
PROMPT_EOF2
```

The wrapper:

- Locates `agy` in `PATH`, `~/.local/bin`, `/opt/antigravity/bin`, or
  `/usr/local/bin`.
- Verifies auth (system keyring OAuth or `ANTIGRAVITY_API_KEY`).
- Reads the prompt from stdin (or positional argument) and runs `agy -p`
  non-interactively.
- If `--model <model>` is supplied, forwards it directly to `agy`'s own
  native `--model` flag for that call.
- Forwards any extra arguments straight to `agy` — so
  `… ask --sandbox <<'PROMPT_EOF2' …` becomes `agy -p "<prompt>" --sandbox`.

## Rules of engagement

One wrapper call per task. The subagent is a forwarder, not an orchestrator —
keep the user's task text intact and let `agy` do the work.

Strip flags that belong to the parent slash command (`--background`) before
forwarding. Pass `--model <model>` to the wrapper (not to agy directly).
Pass agy-native flags through to the wrapper.

## Model selection

Pass the model's exact identifier (e.g. `gemini-3.8-flash-high`,
`claude-opus-4-6-thinking`) or canonical display label (e.g.
`"Claude Opus 4.6 (Thinking)"`).

Run `bash "${CLAUDE_PLUGIN_ROOT}/scripts/agy-run.sh" models` (or `/agy:models`)
for the full list of available models and curated recommendations.

## agy-native flags worth knowing

Run `agy --help` for the full list. Useful ones:

- `--sandbox` — extra-restrictive execution; only when the user asked for it.
- `--print-timeout 10m` — extend the default 5min print timeout.
- `--add-dir <path>` — add a directory to the workspace (repeatable).

## What this skill does NOT do

- Does not install or authenticate `agy`. That is `/agy:setup`'s job.
- Does not retry, summarize, or post-process `agy`'s output.
- Does not read files, run `git`, or make HTTP calls outside the wrapper.

## Error handling

If the wrapper exits non-zero, return its stderr verbatim. Standard exit
codes:

- `127` — `agy` binary not found.
- `1` — not authenticated, no diff found (`review` subcommand), or `agy`
  itself rejected the model (see its stderr).
- `64` — bad CLI usage of the wrapper itself (e.g. empty prompt or empty `--model`).
