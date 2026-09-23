---
description: Ask the Antigravity CLI to review the current git diff
argument-hint: "[--model <model>] [focus text]"
allowed-tools: Bash(bash:*)
---

Run a code review of the current uncommitted changes through `agy`. Forward
any focus text the user provided as a steer for the review.

The user's request:

```
$ARGUMENTS
```

## How to invoke

If the user's text contains `--model <value>` (or `--model=<value>`), extract
the flag and its value. The remaining text is the focus text.

Pass the focus text via stdin using a single-quoted heredoc (`<<'PROMPT_EOF2'`)
to prevent shell expansions:

```
bash "${CLAUDE_PLUGIN_ROOT}/scripts/agy-run.sh" review <<'PROMPT_EOF2'
<focus text, verbatim>
PROMPT_EOF2
```

Or with `--model`:

```
bash "${CLAUDE_PLUGIN_ROOT}/scripts/agy-run.sh" review --model <model> <<'PROMPT_EOF2'
<focus text, verbatim>
PROMPT_EOF2
```

If the user provided no focus text, omit the heredoc:

```
bash "${CLAUDE_PLUGIN_ROOT}/scripts/agy-run.sh" review
```
(or with `--model <model>` if specified).

Pass the model's exact identifier (e.g. `claude-opus-4-6-thinking`,
`gemini-3.8-flash-high`) or canonical display label. Run `/agy:models` to see
available models and recommendations.

Return Antigravity's response verbatim. If there is no diff, the wrapper will
report it — relay that to the user and suggest they stage or make changes
first.
