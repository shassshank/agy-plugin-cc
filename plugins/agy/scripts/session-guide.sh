#!/usr/bin/env bash
# session-guide.sh — SessionStart hook: inject a compact "which agy command /
# flag to use when" guide into Claude's context, so delegation to agy picks
# the right options without the user having to spell them out. Runs on
# startup, resume, /clear and compaction. Never blocks or fails the session.
# Opt out with AGY_NO_SESSION_GUIDE=1.

set -u

[ "${AGY_NO_SESSION_GUIDE:-}" = "1" ] && exit 0

if command -v agy >/dev/null 2>&1 || [ -x "$HOME/.local/bin/agy" ] \
    || [ -x "/opt/antigravity/bin/agy" ] || [ -x "/usr/local/bin/agy" ]; then
  status_line="agy is installed."
else
  status_line="agy is NOT installed — if the user wants agy, run /agy:setup first."
fi

read -r -d '' guide <<'GUIDE'
agy plugin (Google Antigravity CLI) — when to use what. STATUS_LINE

Commands
- /agy:ask — one-shot question or quick second opinion; no file edits expected.
- /agy:delegate — self-contained coding/refactor/debug task agy should carry out (it can edit files). Add --background when it will take minutes.
- /agy:research — open-ended investigation needing sources; prefer --background and --effort high.
- /agy:review — independent review of uncommitted changes (untracked files included); --base main for a whole branch. Give focus text when the user has a concern.
- /agy:image — any generated image (the only image-generation path); --output <path> to place it in the project (format converted to match the extension).
- /agy:models — check the live model list before naming a model you are unsure exists.

Flags (put them before the prompt text; they are forwarded to agy)
- --model <id>: only when the user asks or the task clearly needs it. Fast/cheap: gemini-*-flash-*; hardest reasoning: gemini-*-pro-high or claude-opus-*-thinking; second opinion from another family: gpt-oss-*. Otherwise omit and let agy choose.
- --effort low|medium|high|xhigh|max: low for lookups/trivial edits, high for debugging, architecture, research and reviews of risky code; omit for ordinary tasks.
- --conversation <id>: ALWAYS use for follow-ups on earlier agy work ("now also…", "fix what you found"). Every reply ends with "[agy] conversation: <id>" — reuse that id instead of re-sending context. Never use -c/--continue: it resumes the user's most recent agy conversation, which may be their own terminal session.
- --print-timeout <dur>: review defaults to 15m and image to 10m; ask/delegate/research have no limit. Set one (e.g. 20m) for delegations that must not run unbounded; 0 = no limit.
- --add-dir <path>: when the task needs files outside the current repo.
- --json-schema '<object schema>': when you need machine-readable output; the wrapper prints the structured object.
- --sandbox: only if the user asks for restricted execution. --dangerously-skip-permissions: only on explicit user request.
- Do not use --mode plan for "plan only" work: headless agy ignores it and may still edit files. Ask for a plan in the prompt instead.

Results
- Relay agy's output verbatim, keeping the "[agy] conversation:" line.
- Exit 3 = model/agent error (e.g. no capacity): relay the [agy] error line, then retry once or suggest another --model. Exit 124 = timed out with a partial reply: continue with --conversation <id> or a longer --print-timeout. Exit 1 "not authenticated" or 127 = tell the user to run /agy:setup.
- agy cannot see this conversation: include file paths, the goal and what is already ruled out in the prompt.
GUIDE

guide="${guide/STATUS_LINE/$status_line}"

j_esc() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//$'\n'/\\n}"
  s="${s//$'\r'/\\r}"
  s="${s//$'\t'/\\t}"
  printf '%s' "$s"
}

printf '{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"%s"}}\n' "$(j_esc "$guide")"
exit 0
