#!/usr/bin/env python3
"""Process `agy -p --output-format stream-json` output for agy-run.sh.

Reads agy's NDJSON events on stdin and:

- prints `[agy] conversation: <id> (started)` on stderr as soon as the
  `init` event arrives, so a run that is killed or times out can still be
  resumed with `--conversation <id>`;
- writes a readable progress log (agy's step checklist, each tool call,
  the agent's interim messages) plus a small JSON status file, which
  `agy-run.sh status` (`/agy:status`) reads to show background runs;
- mirrors the progress lines to stderr live when AGY_PROGRESS=1;
- on the final `result` event prints exactly what the `json` mode printed
  before: the response (or `structured_output`), the
  `[agy] conversation:` line, denied actions, and the exit status
  (124 print timeout, 3 agy error, 0 success), followed by a one-line
  `[agy] summary:` on stderr.

Usage: agy-stream.py <log-file> <status-file>   (either may be "" to skip)
"""
import json
import os
import re
import sys
import time

LOG_PATH, STATUS_PATH = (sys.argv[1:3] + ["", ""])[:2]
LIVE = os.environ.get("AGY_PROGRESS") == "1"
LABEL = os.environ.get("AGY_RUN_LABEL", "")

PATH_KEYS = ("Path", "AbsolutePath", "TargetFile", "FilePath", "File", "path")
TEXT_KEYS = ("CommandLine", "Command", "Query", "Url", "URL", "Pattern",
             "SearchPath", "Prompt", "Description")
# Tools that change files: a successful call with a path counts as an edit.
EDIT_HINTS = ("write", "edit", "replace", "create_file", "delete")
QUIET_TOOLS = {"update_steps"}  # shown through the checklist instead

state = {
    "pid": os.getpid(),
    "label": LABEL,
    # Who started the run, so `cleanup` only touches this Claude session's
    # runs and `cleanup --stop` can end agy (a child of the wrapper).
    "claude_session": os.environ.get("AGY_CLAUDE_SESSION", ""),
    "wrapper_pid": int(os.environ.get("AGY_WRAPPER_PID") or 0) or None,
    "cwd": os.getcwd(),
    "model": "",
    "conversation_id": "",
    "started": time.time(),
    "updated": time.time(),
    "status": "running",
    "steps": [],          # agy's own checklist from update_steps
    "tools": 0,
    "tool_errors": 0,
    "edited": [],
    "last": "",
}
tool_counts = {}
started_tools = set()
agent_text = {}           # step_index -> accumulated text
all_agent_text = []       # in order, for a partial reply without a result
log_fh = None


def open_log():
    global log_fh
    if not LOG_PATH:
        return
    try:
        old = os.umask(0o077)
        log_fh = open(LOG_PATH, "a", encoding="utf-8")
        os.umask(old)
    except OSError:
        log_fh = None


def write_status():
    if not STATUS_PATH:
        return
    state["updated"] = time.time()
    tmp = STATUS_PATH + ".tmp"
    try:
        old = os.umask(0o077)
        with open(tmp, "w", encoding="utf-8") as f:
            json.dump(state, f)
        os.umask(old)
        os.replace(tmp, STATUS_PATH)
    except OSError:
        pass


def progress(line):
    stamp = time.strftime("%H:%M:%S")
    state["last"] = line
    if log_fh:
        try:
            log_fh.write("%s %s\n" % (stamp, line))
            log_fh.flush()
        except OSError:
            pass
    if LIVE:
        sys.stderr.write("[agy] %s\n" % line)
        sys.stderr.flush()


FILE_LINK = re.compile(r"\[([^\]]+)\]\(file://[^)]*\)")


def short(value, limit=90):
    value = FILE_LINK.sub(r"\1", " ".join(str(value).split()))
    return value if len(value) <= limit else value[: limit - 1] + "…"


def rel(path):
    try:
        r = os.path.relpath(path, state["cwd"])
        return path if r.startswith("../..") else r
    except ValueError:
        return path


def tool_target(params):
    if not isinstance(params, dict):
        return "", ""
    for k in PATH_KEYS:
        if isinstance(params.get(k), str) and params[k]:
            return rel(params[k]), params[k]
    for k in TEXT_KEYS:
        if isinstance(params.get(k), str) and params[k]:
            return short(params[k]), ""
    for v in params.values():
        if isinstance(v, str) and v:
            return short(v), ""
    return "", ""


def on_steps(params):
    steps = params.get("steps") if isinstance(params, dict) else None
    if not isinstance(steps, list):
        return
    old = {(s.get("title"), s.get("status")) for s in state["steps"]}
    clean = [{"title": str(s.get("title", "")), "status": str(s.get("status", ""))}
             for s in steps if isinstance(s, dict)]
    state["steps"] = clean
    total = len(clean)
    done = sum(1 for s in clean if s["status"] in ("done", "completed", "skipped"))
    for i, s in enumerate(clean, 1):
        if (s["title"], s["status"]) not in old and s["status"] in ("in_progress", "failed"):
            progress("step %d/%d %s: %s" % (i, total, s["status"].replace("_", " "), short(s["title"])))
    if total and done == total and any(st != "done" for _, st in old):
        progress("all %d steps finished" % total)


def on_step(p):
    idx = p.get("step_index")
    stype = p.get("step_type")
    st = p.get("state")
    if stype == "agent_response":
        delta = p.get("text_delta") or ""
        if delta:
            agent_text[idx] = agent_text.get(idx, "") + delta
            all_agent_text.append(delta)
        if st != "ACTIVE":
            text = agent_text.pop(idx, "").strip()
            if text:
                progress("agy: " + short(text, 160))
        return
    if stype != "tool":
        return
    info = p.get("tool_info") or {}
    name = info.get("name") or p.get("tool_name") or "tool"
    params = info.get("parameters")
    if name in QUIET_TOOLS:
        if st != "ACTIVE":
            on_steps(params)
        return
    target, full_path = tool_target(params)
    if st == "ACTIVE":
        if idx not in started_tools:
            started_tools.add(idx)
            progress("→ %s %s" % (name, target))
        return
    state["tools"] += 1
    tool_counts[name] = tool_counts.get(name, 0) + 1
    err = info.get("error")
    if err:
        state["tool_errors"] += 1
        msg = err.get("message") if isinstance(err, dict) else err
        progress("✗ %s %s: %s" % (name, target, short(msg or "failed", 140)))
    else:
        if full_path and any(h in name.lower() for h in EDIT_HINTS):
            if target not in state["edited"]:
                state["edited"].append(target)
        dur = p.get("duration_seconds")
        if isinstance(dur, (int, float)) and dur >= 5:
            progress("✓ %s %s (%.0fs)" % (name, target, dur))


def fmt_tokens(n):
    if not isinstance(n, (int, float)) or n <= 0:
        return ""
    return "%.1fk tokens" % (n / 1000.0) if n >= 1000 else "%d tokens" % n


def summary_line(result):
    parts = []
    if state["steps"]:
        done = sum(1 for s in state["steps"] if s["status"] in ("done", "completed"))
        parts.append("%d/%d steps" % (done, len(state["steps"])))
    if state["tools"]:
        top = sorted(tool_counts.items(), key=lambda kv: -kv[1])[:4]
        parts.append("%d tool call%s (%s)" % (
            state["tools"], "" if state["tools"] == 1 else "s",
            ", ".join("%s×%d" % kv for kv in top)))
    if state["tool_errors"]:
        parts.append("%d failed" % state["tool_errors"])
    if state["edited"]:
        shown = state["edited"][:6]
        more = len(state["edited"]) - len(shown)
        parts.append("edited: " + ", ".join(shown) + (" +%d more" % more if more > 0 else ""))
    dur = result.get("duration_seconds")
    if isinstance(dur, (int, float)) and dur > 0:
        parts.append("%.0fs" % dur)
    tok = fmt_tokens((result.get("usage") or {}).get("total_tokens"))
    if tok:
        parts.append(tok)
    return " · ".join(parts)


def finish(result):
    """Print the result exactly like the json mode did; return exit code."""
    out = sys.stdout
    structured = result.get("structured_output")
    if structured is not None:
        resp = json.dumps(structured, indent=2) + "\n"
    else:
        resp = result.get("response") or ""
    out.write(resp if resp.endswith("\n") or not resp else resp + "\n")
    cid = result.get("conversation_id") or state["conversation_id"]
    if cid:
        out.write("\n[agy] conversation: %s (follow up with --conversation %s)\n" % (cid, cid))
    out.flush()
    denied = result.get("denied_actions")
    if denied:
        sys.stderr.write("[agy] denied actions (%d) — agy was not allowed to do these:\n" % len(denied))
        for item in denied:
            sys.stderr.write("  - %s\n" % (item if isinstance(item, str) else json.dumps(item)))
    line = summary_line(result)
    if line:
        sys.stderr.write("[agy] summary: %s\n" % line)
    if result.get("finished_reason") == "print_timeout":
        state["status"] = "timeout"
        return 124
    status = result.get("status")
    if status and status != "SUCCESS":
        state["status"] = status.lower()
        sys.stderr.write("[agy] status: %s\n" % status)
        if result.get("error"):
            sys.stderr.write("[agy] error: %s\n" % result["error"])
        return 3
    state["status"] = "done"
    return 0


def main():
    open_log()
    if LABEL:
        progress("task: " + short(LABEL, 160))
    write_status()
    rc = None
    last_write = 0.0
    for raw in sys.stdin:
        line = raw.strip()
        if not line:
            continue
        try:
            ev = json.loads(line)
        except ValueError:
            ev = None
        if not isinstance(ev, dict) or "event" not in ev:
            # Not a stream event (old agy, or plain text): pass it through.
            sys.stdout.write(raw)
            continue
        kind = ev.get("event")
        payload = ev.get(kind) if isinstance(ev.get(kind), dict) else {}
        if kind == "init":
            cid = ev.get("conversation_id") or payload.get("conversation_id") or ""
            state["conversation_id"] = cid
            state["model"] = payload.get("model", "")
            if payload.get("cwd"):
                state["cwd"] = payload["cwd"]
            if cid:
                note = " — progress: %s" % LOG_PATH if LOG_PATH else ""
                sys.stderr.write("[agy] conversation: %s (started)%s\n" % (cid, note))
                sys.stderr.flush()
                progress("started conversation %s%s" % (
                    cid, " on " + state["model"] if state["model"] else ""))
            write_status()
        elif kind == "step_update":
            if not state["conversation_id"] and payload.get("conversation_id"):
                state["conversation_id"] = payload["conversation_id"]
            on_step(payload)
            now = time.time()
            if now - last_write >= 2:
                write_status()
                last_write = now
        elif kind == "result":
            rc = finish(payload)
            progress("finished: %s" % state["status"])
            write_status()

    if rc is None:
        # The stream ended without a result (agy crashed or was killed):
        # hand back what agy had said so far and the id to resume it.
        partial = "".join(all_agent_text)
        if partial:
            sys.stdout.write(partial if partial.endswith("\n") else partial + "\n")
        if state["conversation_id"]:
            cid = state["conversation_id"]
            sys.stdout.write("\n[agy] conversation: %s (follow up with --conversation %s)\n" % (cid, cid))
        state["status"] = "ended without a result"
        progress("ended without a result")
        write_status()
        rc = 3 if state["conversation_id"] else 0
    return rc


if __name__ == "__main__":
    try:
        sys.exit(main())
    except BrokenPipeError:
        sys.exit(141)
