# agy — Antigravity CLI plugin for Claude Code

Use Google's [Antigravity CLI (`agy`)](https://antigravity.google/) from
inside Claude Code. Delegate tasks to the `agy:runner` subagent, run quick
prompts, or get a second-opinion code review — without leaving your editor.

This plugin is for Claude Code users who already use (or want to start using)
Antigravity and want a smooth way to call it from the workflow they already
have. Intentionally small: no Node runtime, no broker, no review-gate hook —
just Bash and `agy`.

## What you get

- **`/agy:setup`** — verify `agy` is installed and authenticated; can install
  it for you if it is missing.
- **`/agy:ask [--model <model>] <prompt>`** — one-shot prompt through `agy -p`;
  returns the raw response.
- **`/agy:delegate [--background] [--model <model>] <task>`** — hand a task
  to the `agy:runner` subagent. `--background` for long jobs.
- **`/agy:research [--background] [--model <model>] <topic>`** — delegate a
  deep-research investigation; wraps the topic in a structured prompt and
  routes through `agy:runner`.
- **`/agy:image [--name <slug>] [--output <path>] [--model <model>] <description>`** — generate an image with `agy`'s built-in
  `image-generator` subagent (Imagen under the hood).
- **`/agy:review [--model <model>] [--base <ref>] [focus]`** — ask Antigravity
  to review your uncommitted changes (including untracked files), or a whole
  branch with `--base main`.
- **`/agy:models`** — list available models with curated recommendations.
- **`/agy:help`** — show all commands and model selection guide.
- **`agy:runner` subagent** — thin forwarding wrapper around the Antigravity
  CLI; available as `subagent_type: "agy:runner"` for programmatic
  delegation.

## Requirements

- **Claude Code** with plugin-marketplace support
  (`/plugin marketplace add …`).
- **Antigravity CLI (`agy`)** installed locally. `/agy:setup` can install it
  on first run.
- **Auth** for `agy`: either OAuth sign-in (after one interactive run of
  `agy`) or `GEMINI_API_KEY` exported in your shell.
- **Bash** and **git** in `PATH`. macOS, Linux, or WSL.

## Install

In Claude Code, run these three slash commands in order:

```text
/plugin marketplace add shassshank/agy-plugin-cc
/plugin install agy@agy-plugin-cc
/reload-plugins
```

Then verify everything is wired up:

```text
/agy:setup
```

If `agy` is missing, `/agy:setup` offers to install it via the official
installer:

```bash
curl -fsSL https://antigravity.google/cli/install.sh | bash
```

If `agy` is installed but not logged in, run `agy` once interactively in your
terminal to complete OAuth — or export `GEMINI_API_KEY`.

## Updating

When a Claude Code session starts, the plugin checks whether a newer version
has been published to this repo and, if so, shows a one-line notice. To update:

```bash
claude plugin marketplace update agy-plugin-cc
claude plugin update agy@agy-plugin-cc
```

Then restart Claude Code. The check fetches
[`plugin.json`](./plugins/agy/.claude-plugin/plugin.json) from GitHub at most
once a day, times out after 3 seconds, and never blocks your session. Turn it
off with `export AGY_NO_UPDATE_CHECK=1`.

## Usage

### Ask a quick question

```text
/agy:ask explain the difference between Go channels and Rust async in one paragraph
```

Returns Antigravity's response verbatim, followed by a
`[agy] conversation: <id>` line.

### Follow up in the same agy conversation

Pass that id back with `--conversation` to continue where agy left off, with
its full history:

```text
/agy:ask --conversation 5c9b18f9-... now write tests for the function you proposed
/agy:delegate --conversation 5c9b18f9-... also update the README for that change
```

Set `AGY_PLAIN_OUTPUT=1` to get agy's raw text output without the
conversation line.

### Delegate a task to the `agy:runner` subagent

```text
/agy:delegate refactor the SQL queries in src/db/queries.go to use prepared statements
```

For long tasks, run in the background and let Claude Code notify you when it
finishes:

```text
/agy:delegate --background investigate why integration tests are flaky in CI
```

You can also delegate by talking to Claude:

```text
Ask agy to look at this file and suggest a simpler design.
```

The plugin's selection rules route through the `agy:runner` subagent
automatically.

### Review the current diff

Stage or make some changes, then:

```text
/agy:review
/agy:review focus on error handling and concurrency safety
/agy:review --base main          # everything on this branch since main
```

Untracked files are included, scoped to the whole repo even from a
subdirectory. Very large diffs are handed to agy as a temporary file instead
of being inlined in the prompt. Reviews stop after 15 minutes by default
(`--print-timeout <dur>` or `AGY_PRINT_TIMEOUT` to change; `0` = no limit);
a timed-out run exits `124` and can be continued with `--conversation <id>`.

### Pick a specific model

```text
/agy:delegate --model claude-sonnet-4-6 fix the off-by-one in pagination
/agy:delegate --model gemini-3.1-pro-high write a high-coverage test for the cache layer
/agy:ask --model claude-opus-4-6-thinking "explain Go's escape analysis"
/agy:review --model gemini-3.8-flash-high
```

Pass either the model's exact identifier (e.g. `claude-opus-4-6-thinking`,
`gemini-3.8-flash-high`) or canonical display label (e.g.
`"Claude Opus 4.6 (Thinking)"`). Run `/agy:models` to view all available
models alongside curated recommendations.

Tune reasoning depth on any call with `--effort low|medium|high|xhigh|max`:

```text
/agy:ask --effort high is this lock-free queue actually linearizable?
```

If no `--model` is given, the wrapper omits the flag and `agy` uses its own
default. Project-local `AGENTS.md` and `GEMINI.md` files are read directly
by `agy` and unaffected by this plugin.

### Delegate a deep research investigation

```text
/agy:research what's the current state of WebGPU support across browsers in 2026?
/agy:research --background --model claude-opus-4-6-thinking survey post-quantum signature schemes used in TLS
```

The command wraps your topic in a research-oriented preamble (background,
key findings, caveats, sources) and delegates to `agy:runner`. Long
investigations work well in `--background`.

### Generate an image

```text
/agy:image a minimalist dark-mode login mockup, blue accent color
/agy:image --name hero --output ./assets/hero.png isometric illustration of a developer at a desk
```

Hands the request to `agy`'s built-in `image-generator` subagent. The image
is written to the Antigravity artifacts dir (e.g.
`~/.gemini/antigravity-cli/brain/<uuid>/<name>.jpg`). Pass `--output` if
you want the wrapper to copy it next to your project; if the extension you
ask for differs (e.g. `.png`), it is converted with `sips` (macOS) or
ImageMagick.

## How it works

Under the hood, the plugin is a thin wrapper around your local `agy` install:

```
Claude Code  →  /agy:*  →  agy:runner subagent  →  agy-run.sh  →  agy -p "..."
```

- The plugin does **not** ship its own Antigravity runtime — it uses your
  local `agy` binary, your local auth, and your local config.
- The wrapper script
  ([`plugins/agy/scripts/agy-run.sh`](./plugins/agy/scripts/agy-run.sh))
  handles binary discovery, auth detection, and exit codes. It runs agy in
  JSON print mode to surface the conversation id, and exits `3` (with an
  `[agy] error:` line) when agy reports a model/agent error such as no
  model capacity — even in cases where agy itself exits 0 — and `124` when
  `--print-timeout` cut the run short.
- The `agy:runner` subagent is a *forwarder*: it invokes the wrapper exactly
  once per request and returns Antigravity's output verbatim. No
  reinterpretation.

## Built-in guidance for Claude

A `SessionStart` hook ([`session-guide.sh`](./plugins/agy/scripts/session-guide.sh))
adds a short "which agy command and flag to use when" guide to Claude's
context on startup, resume, `/clear` and compaction. It tells Claude, for
example, to reuse `--conversation <id>` for follow-ups instead of `-c`, when
to raise `--effort`, when to use `--base` or `--json-schema`, and how to
handle exit codes `3` and `124`. The longer version lives in the
`agy:usage-guide` skill. Turn the hook off with
`export AGY_NO_SESSION_GUIDE=1`.

## Configuration

`agy` stores its preferences (selected model, theme, telemetry, trusted
workspaces) in `~/.gemini/antigravity-cli/settings.json`. Project-local
`AGENTS.md` / `GEMINI.md` files are read directly by `agy`. This plugin
doesn't override or shadow any of that — drop config files where `agy`
expects them and they'll be picked up.

The `--model <model>` flag on `/agy:ask`, `/agy:delegate`, `/agy:research`,
`/agy:review`, and `/agy:image` forwards straight through to `agy`'s own native
`--model` flag for that one call — no config file is touched, so a TUI session
running in parallel is unaffected.

## FAQ

### Do I need an Antigravity subscription?

You need whatever account `agy` accepts: Google AI Pro, Ultra, Code Assist
Standard/Enterprise, or an enterprise GCP project. See the
[Antigravity docs](https://antigravity.google/docs/cli-overview) for details.

### Does this plugin send data anywhere other than what `agy` sends?

No. The plugin runs `agy` locally over a Bash wrapper. The wrapper only reads
filesystem paths and your shell environment. Your prompts go directly to
Google through `agy`'s normal channels. The only other request the plugin
makes is the daily update check — a plain download of `plugin.json` from
`raw.githubusercontent.com` that sends nothing about you or your code
(disable with `AGY_NO_UPDATE_CHECK=1`).

### Can I keep using Antigravity outside this plugin?

Yes — the plugin uses your local install. Running `agy` directly in a
terminal keeps working exactly as before.

### Why a subagent instead of just a slash command?

Subagents in Claude Code can run in the background and report back when
finished. That is the workflow you want when you "hand this off to another
model and keep working" — which is the whole point of delegating to `agy`.

## Inspiration

Inspired by
[`openai/codex-plugin-cc`](https://github.com/openai/codex-plugin-cc), which
does the same thing for Codex. This plugin is intentionally smaller.

## License

[MIT](./LICENSE).
