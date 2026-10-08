---
description: Ask the Antigravity CLI to review the current git diff
argument-hint: "[--model <model>] [--base <ref>] [--effort <level>] [focus text]"
allowed-tools: Bash(bash:*)
---

Run a code review through `agy`. By default it reviews uncommitted changes
(staged, unstaged, and untracked files). With `--base <ref>` (e.g.
`--base main`) it reviews everything since the branch point with that ref —
committed branch work plus uncommitted edits. Forward any focus text the user
provided as a steer for the review.

The user's request:

```
$ARGUMENTS
```

## How to invoke

If the user's text contains `--model <value>`, `--base <ref>`, or agy-native
flags such as `--effort <level>`, extract them and pass them as arguments
before the heredoc. The remaining text is the focus text.

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

If the user provided no focus text, redirect stdin from `/dev/null` so the
wrapper never waits on an open stdin:

```
bash "${CLAUDE_PLUGIN_ROOT}/scripts/agy-run.sh" review [--base <ref>] [--model <model>] </dev/null
```

Large diffs are handed to agy as a temporary file automatically.

Pass the model's exact identifier (e.g. `claude-opus-4-6-thinking`,
`gemini-3.8-flash-high`) or canonical display label. Run `/agy:models` to see
available models and recommendations.

Return Antigravity's response verbatim. If there is no diff, the wrapper will
report it — relay that to the user and suggest they stage or make changes
first.
