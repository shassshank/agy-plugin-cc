# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.0.4] - 2026-10-08

Brings the plugin up to date with Antigravity CLI 1.3.x.

### Added
- Multi-turn follow-ups: `/agy:ask`, `/agy:delegate`, `/agy:research` and
  `/agy:review` now end with `[agy] conversation: <id>`; pass
  `--conversation <id>` on the next call to resume that agy conversation with
  its full history. The wrapper runs agy with `--output-format json` to get
  the id (requires `python3`; `AGY_PLAIN_OUTPUT=1` restores raw text output).
- `/agy:review --base <ref>` reviews everything since the merge base with
  `<ref>` (committed branch work plus uncommitted edits).
- `--effort <low|medium|high|xhigh|max>` documented and forwarded on all
  agy-backed commands.
- `/agy:help` now lists useful agy-native flags, follow-up usage, and exit
  codes, plus agy's newer subcommands (`agents`, `mcp`, `remote-control`).
- Session guide: a `SessionStart` hook (startup, resume, `/clear`,
  compaction) injects a compact guide telling Claude which `/agy:*` command
  and flags to use when (`--conversation` for follow-ups, never `-c`;
  `--effort` levels; `--base`; `--json-schema`; `--print-timeout`; exit-code
  handling). Disable with `AGY_NO_SESSION_GUIDE=1`. The `agy:usage-guide`
  skill gains a matching flag-selection table.
- Default print timeouts: `/agy:review` 15m, `/agy:image` 10m (ask,
  delegate and research stay unlimited). `AGY_PRINT_TIMEOUT` overrides all
  of them (`0` = no limit). agy reports a timeout only on stderr, so the
  wrapper detects it and exits `124`.

### Fixed
- Auth detection checked `ANTIGRAVITY_API_KEY`, which `agy` never reads, so
  users signed in only via `GEMINI_API_KEY` were reported as unauthenticated.
  The wrapper and `/agy:setup` now use `GEMINI_API_KEY` (and
  `GOOGLE_API_KEY`).
- agy can exit 0 even when a run ends on a model error (e.g. `No capacity
  available for model …`). The wrapper now reads the JSON status, prints the
  error, and exits `3`, while still printing any partial response.
- `/agy:review` ignored untracked (newly created) files; they are now
  included as new-file diffs.
- `/agy:review` on very large diffs could fail with "Argument list too long";
  diffs over ~200 KB (`AGY_REVIEW_MAX_INLINE_BYTES`) are now handed to agy as
  a temporary file.
- `/agy:review` with no focus text now invokes the wrapper with
  `</dev/null`, so it can never block waiting on an open stdin.
- `/agy:image --output out.png` copied agy's JPEG bytes into a `.png` file;
  the wrapper now converts formats with `sips` or ImageMagick, or warns when
  it cannot.
- `--json-schema` replies printed agy's raw `response` (with extra
  `toolAction`/`toolSummary` keys); the wrapper now prints the clean
  `structured_output` object.
- `/agy:image` ignored agy model errors (exit 0); it now goes through the
  same error handling and exits `3`. It also died silently under
  `set -o pipefail` whenever agy's reply had no image path, so the
  "no IMAGE_PATH" warning never appeared; fixed.
- OAuth detection now requires agy's token file instead of only its data
  directory, so a signed-out machine is no longer reported as ready.
- `/agy:review` from a subdirectory now scopes tracked and untracked files
  to the same repo root; the inline-size limit is measured in bytes rather
  than characters; the large-diff temp directory is removed on Ctrl-C or
  kill as well.
- Stale docs: headless runs no longer have a 5-minute default timeout (agy
  removed it), image generation now goes through agy's `image-generator`
  subagent, and exit code `3` is documented.

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
