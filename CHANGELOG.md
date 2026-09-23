# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.0.3] - 2026-09-23

### Added
- Session-start update check: a `SessionStart` hook compares the installed
  plugin version with the latest `plugin.json` on GitHub (cached for 24h,
  3-second timeout) and shows a notice with the update commands when a newer
  version is available. Disable with `AGY_NO_UPDATE_CHECK=1`.

## [0.0.2] - 2026-09-08

### Added
- New `/agy:models` slash command and wrapper `models` subcommand to query
  `agy models` and display a clean table of available models alongside curated
  recommendations and use-case blurbs.
- Uniform `--model <value>` flag support on `/agy:review` and `/agy:image`,
  forwarded straight through to `agy`'s native `--model` flag.

### Fixed
- Fixed crash in `agy-run.sh`'s `cmd_image` where `positional` empty array expansion
  under `set -u` failed with "unbound variable" on macOS bash 3.2.
- Fixed issue where `--model` was silently dropped by `/agy:delegate` and
  `/agy:research` commands; prompt text now preserves `--model <name>` at the
  front when handed to the `agy:runner` subagent.
- Fixed shell-injection and fragile-quoting risks across `/agy:ask`,
  `/agy:review`, `/agy:image`, `agy:runner`, and `antigravity-cli` runtime skill
  by passing prompt, focus, and description bodies via stdin using single-quoted
  heredocs (`<<'PROMPT_EOF2'`).
- Fixed `cmd_ask`/`cmd_review` swallowing an agy-native passthrough flag
  (e.g. `--sandbox`) as the literal prompt/focus text and silently dropping
  the real stdin/heredoc body. A leading `-` on the first remaining arg now
  routes to stdin instead of being consumed as positional text.

## [0.0.1] - 2026-09-08

### Added
- Initial release of `agy-plugin-cc`, a Claude Code plugin marketplace for
  the `agy` plugin — a wrapper around Google's Antigravity CLI (`agy`).
- `/agy:setup` — verify `agy` install and authentication; offer to install
  if missing.
- `/agy:ask [--model <alias>] <prompt>` — one-shot `agy -p` prompt,
  returned verbatim.
- `/agy:delegate [--background] [--model <alias>] <task>` — hand a task to
  the `agy:runner` subagent.
- `/agy:research [--background] [--model <alias>] <topic>` — deep-research
  investigation via `agy:runner`.
- `/agy:review [focus]` — pipe the current `git diff` into `agy` for review.
- `/agy:image [--name <slug>] [--output <path>] <description>` — generate
  an image via `agy`'s built-in `generate_image` tool.
- `/agy:help` — index of every `/agy:*` command, supported `--model`
  aliases, and canonical model names.
- `agy:runner` subagent — thin forwarding wrapper around the Antigravity
  CLI, plus the internal `antigravity-cli` runtime skill.
- `agy-run.sh` — bash wrapper handling binary discovery, auth detection,
  and exit codes.
- `--model <alias>` support on `/agy:ask`, `/agy:delegate`, and
  `/agy:research`, forwarded straight through to `agy`'s own native
  `--model` flag. Alias table: `flash-low`, `flash-medium` (`flash-med`),
  `flash` (`flash-high`), `pro-low`, `pro` (`pro-high`), `sonnet`
  (`claude-sonnet`), `opus` (`claude-opus`), `gpt-oss` (`gpt-oss-120b`).
  Canonical model ids/labels are also accepted verbatim.
