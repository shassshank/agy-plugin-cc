---
description: Run a one-shot prompt through the Antigravity CLI and return its output verbatim
argument-hint: "[--model <model>] <prompt>"
allowed-tools: Bash(bash:*)
---

Forward the user's request below to `agy -p` via the wrapper script. Return
Antigravity's response verbatim — do not paraphrase or add commentary.

The user's request:

```
$ARGUMENTS
```

## How to invoke

If the user's text begins with `--model <value>` (or `--model=<value>`, e.g.
`--model claude-opus-4-6-thinking rest of prompt…`), extract the flag and its
value and pass it as an argument before the heredoc. Anything else stays as the
prompt body.

Feed the prompt body to the wrapper via stdin using a single-quoted heredoc
(`<<'PROMPT_EOF2'`) to prevent shell expansions:

```
bash "${CLAUDE_PLUGIN_ROOT}/scripts/agy-run.sh" ask <<'PROMPT_EOF2'
<raw prompt text, verbatim>
PROMPT_EOF2
```

Or with `--model`:

```
bash "${CLAUDE_PLUGIN_ROOT}/scripts/agy-run.sh" ask --model <model> <<'PROMPT_EOF2'
<raw prompt text, verbatim>
PROMPT_EOF2
```

Pass the model's exact identifier (e.g. `claude-opus-4-6-thinking`,
`gemini-3.8-flash-high`) or canonical display label (e.g. `"Claude Opus 4.6 (Thinking)"`).
Run `/agy:models` to see available models and recommendations.

Notes:

- If the wrapper reports `agy is not installed` or `not authenticated`, stop
  and tell the user to run `/agy:setup`.
- If the user's request is empty, ask what they want to ask Antigravity.
- For multi-step or long-running work, suggest `/agy:delegate`, which routes
  through the `agy:runner` subagent and supports `--background`.
