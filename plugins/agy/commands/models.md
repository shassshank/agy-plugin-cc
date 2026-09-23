---
description: List available Antigravity models and curated recommendations
allowed-tools: Bash(bash:*)
---

Run the wrapper's models branch, then print its stdout verbatim as a fenced
code block in your text response. Do not paraphrase, reorder, or summarize —
the wrapper is the authoritative source for the live model list and curated
recommendations. The output MUST appear as readable text in the reply, not just
as a collapsed tool result.

```
bash "${CLAUDE_PLUGIN_ROOT}/scripts/agy-run.sh" models
```

After the Bash call completes, copy the full stdout into your response inside
a ``` code block.
