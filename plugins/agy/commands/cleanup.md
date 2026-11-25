---
description: Remove this session's finished agy run records (and optionally stop its running agy runs)
argument-hint: "[--stop] [--all] [<conversation-id or run-id>...]"
allowed-tools: Bash(bash:*)
---

Clean up the agy runs this Claude session started, once you are done with
them. Run, passing only the flags and ids the user gave (none by default):

```
bash "${CLAUDE_PLUGIN_ROOT}/scripts/agy-run.sh" cleanup [--stop] [--all] [<id>...]
```

The user's request:

```
$ARGUMENTS
```

What it does:

- Default: deletes the progress logs and status records (what
  `/agy:status` shows) of **finished** runs started by this Claude session.
  Running runs are kept.
- `--stop`: also ends this session's still-running agy runs and removes
  their records. Only use it when the user asked, or when you started a run
  you no longer need (e.g. a background delegation you abandoned).
- `--all`: also removes finished runs from other or earlier Claude sessions.
  Only when the user asks for it.
- Ids: clean up just those runs (conversation id or run id).

agy's own conversation history is not deleted (agy has no headless way to
do that), so `--conversation <id>` follow-ups keep working after cleanup.

Relay the wrapper's output in one or two lines.
