---
description: Show the progress of running and recent agy runs (including background delegations)
argument-hint: "[--all] [<conversation-id or run-id>]"
allowed-tools: Bash(bash:*)
---

Show what agy runs started through this plugin are doing: running ones
first, plus runs that finished in the last hour. Each entry lists
the status (running, done, timeout, error, or ended without a result),
the agy conversation id, agy's step checklist progress, tool calls, edited
files and the latest activity.

The user's request:

```
$ARGUMENTS
```

Run, passing `--all` and/or an id only if the user gave them:

```
bash "${CLAUDE_PLUGIN_ROOT}/scripts/agy-run.sh" status [--all] [<id>]
```

- With a conversation id or run id, the wrapper prints that run's progress
  log (the last 40 lines).
- `--all` includes finished runs older than an hour (history is kept for
  two days).

Copy the stdout into your reply inside a ``` code block, verbatim. If a
run shows `ended without a result`, the agy process stopped before
finishing; it can be resumed with
`/agy:delegate --conversation <id> continue`.
