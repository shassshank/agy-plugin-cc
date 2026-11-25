# agy (Claude Code plugin payload)

This directory is the actual Claude Code plugin. For install instructions and
full usage, see the [repo-level README](../../README.md).

## Layout

- `commands/` — slash commands: `/agy:setup`, `/agy:ask`, `/agy:delegate`,
  `/agy:research`, `/agy:review`, `/agy:image`, `/agy:models`,
  `/agy:status`, `/agy:cleanup`, `/agy:help`.
- `agents/runner.md` — the `agy:runner` subagent (thin forwarder around the
  Antigravity CLI).
- `skills/antigravity-cli/` — internal runtime skill, used only inside the
  `agy:runner` subagent.
- `scripts/agy-run.sh` — bash wrapper that locates `agy`, checks auth,
  invokes `agy -p`, and implements the `status` and `cleanup` subcommands.
- `scripts/agy-stream.py` — processes agy's `--output-format stream-json`
  events: early conversation id, per-run progress log and status file,
  final reply and `[agy] summary:` line.
- `scripts/agy-model-blurbs.py` — annotates `agy models` with recommended
  uses for `/agy:models`.
- `skills/usage-guide/` — when to use which command, model and flag.
- `hooks/hooks.json` — SessionStart hooks: `scripts/check-update.sh` (update
  notice) and `scripts/session-guide.sh` (injects a compact usage guide).

## Why this layout

Mirrors the conventions used by
[`openai/codex-plugin-cc`](https://github.com/openai/codex-plugin-cc), trimmed
down: no Node runtime, no broker, no review-gate hook. Plain Bash plus a
single subagent.
