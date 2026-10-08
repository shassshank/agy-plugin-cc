---
description: Delegate a task to the Antigravity (`agy`) runner subagent; supports background execution and model selection
argument-hint: "[--background] [--model <model>] [--effort <level>] [--conversation <id>] <task description>"
allowed-tools: Agent
---

Hand the user's task to the `agy:runner` subagent
(`subagent_type: "agy:runner"`).

Raw user request:
$ARGUMENTS

## Routing rules

- If the request contains `--background`, launch the subagent with
  `run_in_background: true`. Strip only the `--background` flag from the
  forwarded prompt text.
- Otherwise run the subagent in the foreground.
- Do NOT strip `--model <name>`. Preserve `--model <name>` at the front of the
  prompt text handed to the `agy:runner` subagent so the runner can extract and
  forward it to the wrapper script as `--model "<name>"`.
- If no model is given, omit `--model` entirely and let `agy` use its own
  default.
- Likewise preserve any other leading agy-native flags (`--effort <level>`,
  `--conversation <id>`, `--sandbox`, `--add-dir <path>`) at the front of the
  prompt text; the runner forwards them to the wrapper.
- To follow up on an earlier delegation, pass the `--conversation <id>` from
  that run's `[agy] conversation:` line — agy resumes with its full history.

Models can be specified by exact id (e.g. `gemini-3.8-flash-high`,
`claude-opus-4-6-thinking`) or canonical display label (e.g.
`"Claude Opus 4.6 (Thinking)"`). Run `/agy:models` to see available models and
recommendations.

## Response style

The subagent is a thin wrapper around `agy`. Return its output verbatim — no
extra commentary before or after.

If the user did not supply a task, ask what they would like Antigravity to do.
