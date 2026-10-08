#!/usr/bin/env bash
# agy-run.sh — Claude Code wrapper around Google Antigravity CLI (`agy`).
# Subcommands: check | ask | review | image | models | help.
# `--model` is passed straight through to agy's own native --model flag.

set -euo pipefail

find_agy() {
  if command -v agy >/dev/null 2>&1; then
    command -v agy
    return 0
  fi
  for candidate in \
      "$HOME/.local/bin/agy" \
      "/opt/antigravity/bin/agy" \
      "/usr/local/bin/agy"; do
    if [ -x "$candidate" ]; then
      echo "$candidate"
      return 0
    fi
  done
  return 1
}

auth_status() {
  # agy reads GEMINI_API_KEY or GOOGLE_API_KEY (GOOGLE_API_KEY wins when
  # both are set); OAuth sign-in stores a token file in its data directory.
  if [ -n "${GEMINI_API_KEY:-}" ] || [ -n "${GOOGLE_API_KEY:-}" ]; then
    echo "api-key"
  elif [ -s "$HOME/.gemini/antigravity-cli/antigravity-oauth-token" ]; then
    echo "oauth"
  else
    echo "missing"
  fi
}

j_esc() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//$'\n'/\\n}"
  s="${s//$'\r'/\\r}"
  s="${s//$'\t'/\\t}"
  printf '%s' "$s"
}

cmd_check() {
  if ! path="$(find_agy | head -n1)"; then
    cat <<JSON
{ "installed": false, "path": "", "version": "", "auth": "unknown",
  "error": "agy binary not found; install with: curl -fsSL https://antigravity.google/cli/install.sh | bash" }
JSON
    return 0
  fi
  version="$("$path" --version 2>/dev/null | head -n1 || echo unknown)"
  auth="$(auth_status)"
  printf '{ "installed": true, "path": "%s", "version": "%s", "auth": "%s", "error": "" }\n' \
    "$(j_esc "$path")" "$(j_esc "$version")" "$(j_esc "$auth")"
}

require_ready() {
  if ! path="$(find_agy)"; then
    echo "error: agy is not installed." >&2
    echo "       install: curl -fsSL https://antigravity.google/cli/install.sh | bash" >&2
    exit 127
  fi
  if [ "$(auth_status)" = "missing" ]; then
    echo "error: agy is not authenticated." >&2
    echo "       run \`agy\` once interactively to sign in, or export GEMINI_API_KEY" >&2
    exit 1
  fi
  echo "$path"
}

# run_agy <agy-path> <agy args...>
# Runs agy in JSON print mode so the conversation id can be surfaced for
# follow-ups (`--conversation <id>`), then prints the plain response text
# (or the `structured_output` object when --json-schema was used).
# Falls back to agy's native text output when python3 is missing, when the
# caller already chose an --output-format, or when AGY_PLAIN_OUTPUT=1.
#
# Time limit: callers may set `local default_print_timeout=<dur>`; it is
# applied unless the args already carry --print-timeout. AGY_PRINT_TIMEOUT
# overrides it for every command ("0" = no limit). agy reports a timeout
# only on stderr (status stays SUCCESS), so that case exits 124.
run_agy() {
  local path="$1"; shift
  local arg has_fmt=0 has_timeout=0
  for arg in "$@"; do
    case "$arg" in
      --output-format|--output-format=*) has_fmt=1 ;;
      --print-timeout|--print-timeout=*) has_timeout=1 ;;
    esac
  done
  local timeout="${AGY_PRINT_TIMEOUT:-${default_print_timeout:-}}"
  if [ "$has_timeout" -eq 0 ] && [ -n "$timeout" ] && [ "$timeout" != "0" ]; then
    set -- "$@" --print-timeout "$timeout"
  fi

  if [ "$has_fmt" -eq 1 ] || [ "${AGY_PLAIN_OUTPUT:-}" = "1" ] \
      || ! command -v python3 >/dev/null 2>&1; then
    "$path" "$@"
    return
  fi

  local out rc=0 err_file
  err_file="$(mktemp "${TMPDIR:-/tmp}/agy_err.XXXXXX")"
  out="$("$path" "$@" --output-format json 2>"$err_file")" || rc=$?
  cat "$err_file" >&2
  local timed_out=0
  grep -q 'print timeout after' "$err_file" 2>/dev/null && timed_out=1
  rm -f "$err_file"

  printf '%s' "$out" | python3 -c '
import json, sys
raw = sys.stdin.read()
try:
    data = json.loads(raw)
except ValueError:
    data = None
if not isinstance(data, dict):
    sys.stdout.write(raw if raw.endswith("\n") or not raw else raw + "\n")
    sys.exit(0)
structured = data.get("structured_output")
if structured is not None:
    resp = json.dumps(structured, indent=2) + "\n"
else:
    resp = data.get("response") or ""
sys.stdout.write(resp if resp.endswith("\n") or not resp else resp + "\n")
cid = data.get("conversation_id")
if cid:
    sys.stdout.write("\n[agy] conversation: %s (follow up with --conversation %s)\n" % (cid, cid))
status = data.get("status")
if status and status != "SUCCESS":
    sys.stderr.write("[agy] status: %s\n" % status)
    if data.get("error"):
        sys.stderr.write("[agy] error: %s\n" % data["error"])
    sys.exit(3)
' || { local prc=$?; [ "$rc" -eq 0 ] && rc="$prc"; }

  if [ "$timed_out" -eq 1 ] && [ "$rc" -eq 0 ]; then
    echo "[wrapper] agy hit the print timeout${timeout:+ ($timeout)}; the reply above is partial or empty." >&2
    echo "[wrapper] continue it with --conversation <id>, or retry with a longer --print-timeout (0 = no limit)." >&2
    rc=124
  fi
  return "$rc"
}

models_cache_file() {
  local cache_dir session_id
  cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/agy-plugin-cc"
  mkdir -p "$cache_dir" 2>/dev/null || true
  # Scoped to the Claude Code session so the list is fetched once per
  # session and reused for the rest of it; a new session gets a fresh
  # fetch. Falls back to a single shared cache outside Claude Code.
  session_id="${CLAUDE_CODE_SESSION_ID:-nosession}"
  echo "$cache_dir/models-$session_id.tsv"
}

fetch_models_raw() {
  local path="$1"
  local cache_file
  cache_file="$(models_cache_file)"

  if [ -s "$cache_file" ]; then
    cat "$cache_file"
    return 0
  fi

  local err_file
  err_file="$(mktemp "${TMPDIR:-/tmp}/agy_models_err.XXXXXX")"
  local raw_output rc=0
  raw_output="$("$path" models 2>"$err_file")" || rc=$?
  if [ "$rc" -ne 0 ]; then
    cat "$err_file" >&2
    rm -f "$err_file"
    exit "$rc"
  fi
  rm -f "$err_file"

  printf '%s\n' "$raw_output" > "$cache_file"

  # Best-effort cleanup of stale sessions' caches so this directory
  # doesn't grow unbounded across many past sessions.
  find "$(dirname "$cache_file")" -maxdepth 1 -name 'models-*.tsv' -mtime +2 -delete 2>/dev/null || true

  printf '%s\n' "$raw_output"
}

cmd_models() {
  local path
  path="$(require_ready)"
  local raw_output
  raw_output="$(fetch_models_raw "$path")"

  # Recommendations are derived from whatever `agy models` returned
  # (family/tier/version parsed from each id) -- there is no hardcoded
  # per-model-id table to fall out of date as models ship.
  if command -v python3 >/dev/null 2>&1; then
    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    printf '%s\n' "$raw_output" | python3 "$script_dir/agy-model-blurbs.py"
  else
    printf '%-26s %-30s\n' "MODEL ID" "DISPLAY LABEL"
    printf '%-26s %-30s\n' "--------" "-------------"
    local tab
    tab="$(printf '\t')"
    while IFS="$tab" read -r mid label || [ -n "$mid" ]; do
      [ -z "$mid" ] && continue
      printf '%-26s %-30s\n' "$mid" "$label"
    done <<< "$raw_output"
  fi
}

cmd_ask() {
  local model=""
  local model_flag_seen=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --model)
        model_flag_seen=1
        if [ $# -ge 2 ]; then
          model="$2"; shift 2
        else
          shift
        fi ;;
      --model=*)
        model_flag_seen=1
        model="${1#--model=}"
        shift ;;
      --)        shift; break ;;
      *)         break ;;
    esac
  done
  if [ "$model_flag_seen" -eq 1 ] && [ -z "$model" ]; then
    echo "error: --model requires a non-empty value (run /agy:models to see available models)" >&2
    exit 64
  fi

  # A remaining arg starting with '-' is an agy-native passthrough flag
  # (e.g. --sandbox), not a positional prompt — read the prompt from
  # stdin in that case so `ask --sandbox <<'EOF' ...` doesn't swallow
  # the flag as the prompt text and silently drop the heredoc body.
  local prompt=""
  if [ $# -gt 0 ] && [ "${1#-}" = "$1" ]; then
    prompt="$1"
    shift
  elif [ ! -t 0 ]; then
    prompt="$(cat)"
    prompt="${prompt%$'\n'}"
  fi

  if [ -z "$prompt" ]; then
    echo "error: ask requires a prompt argument (or via stdin)" >&2
    exit 64
  fi

  local path
  path="$(require_ready)"
  if [ -n "$model" ]; then
    run_agy "$path" -p "$prompt" --model "$model" "$@"
  else
    run_agy "$path" -p "$prompt" "$@"
  fi
}

cmd_review() {
  local model=""
  local model_flag_seen=0
  local base=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --model)
        model_flag_seen=1
        if [ $# -ge 2 ]; then
          model="$2"; shift 2
        else
          shift
        fi ;;
      --model=*)
        model_flag_seen=1
        model="${1#--model=}"
        shift ;;
      --base)
        if [ $# -ge 2 ] && [ -n "$2" ]; then
          base="$2"; shift 2
        else
          echo "error: --base requires a git ref (e.g. --base main)" >&2
          exit 64
        fi ;;
      --base=*)
        base="${1#--base=}"
        if [ -z "$base" ]; then
          echo "error: --base= requires a non-empty git ref" >&2
          exit 64
        fi
        shift ;;
      --)        shift; break ;;
      *)         break ;;
    esac
  done
  if [ "$model_flag_seen" -eq 1 ] && [ -z "$model" ]; then
    echo "error: --model requires a non-empty value (run /agy:models to see available models)" >&2
    exit 64
  fi

  # See cmd_ask() for why a leading '-' routes to stdin instead of
  # being consumed as the positional focus text.
  local focus=""
  if [ $# -gt 0 ] && [ "${1#-}" = "$1" ]; then
    focus="$1"
    shift
  elif [ ! -t 0 ]; then
    focus="$(cat)"
    focus="${focus%$'\n'}"
  fi
  focus="${focus:-Please review the following diff for correctness, edge cases, security issues, and style.}"

  local path
  path="$(require_ready)"
  local repo_dir="${CLAUDE_PROJECT_DIR:-$PWD}"
  # Run from the repo root so tracked and untracked files cover the same scope.
  repo_dir="$(git -C "$repo_dir" rev-parse --show-toplevel 2>/dev/null || printf '%s' "$repo_dir")"
  local diff
  if [ -n "$base" ]; then
    # Everything since the branch point: committed work plus uncommitted edits.
    local merge_base
    if ! merge_base="$(git -C "$repo_dir" merge-base "$base" HEAD 2>/dev/null)"; then
      echo "error: cannot find a merge base between '$base' and HEAD in $repo_dir." >&2
      exit 1
    fi
    diff="$(git -C "$repo_dir" diff "$merge_base" 2>/dev/null || true)"
  else
    diff="$(git -C "$repo_dir" diff HEAD 2>/dev/null || true)"
    if [ -z "$diff" ]; then
      diff="$(git -C "$repo_dir" diff 2>/dev/null || true)"
    fi
  fi

  # `git diff` never shows untracked files; append them as new-file diffs.
  local untracked_diff="" f
  while IFS= read -r -d '' f; do
    untracked_diff+="$(git -C "$repo_dir" diff --no-index -- /dev/null "$f" 2>/dev/null || true)"$'\n'
  done < <(git -C "$repo_dir" ls-files --others --exclude-standard -z 2>/dev/null)
  if [ -n "$untracked_diff" ]; then
    diff="${diff:+$diff$'\n'}$untracked_diff"
  fi

  if [ -z "$diff" ]; then
    echo "error: no git diff found in $repo_dir. Stage or make changes first." >&2
    exit 1
  fi

  # agy only takes the prompt as an argument, so a huge diff would hit the
  # OS argument-size limit. Above the threshold, hand agy a file instead.
  local full
  local max_inline="${AGY_REVIEW_MAX_INLINE_BYTES:-200000}"
  local diff_bytes
  diff_bytes="$(printf '%s' "$diff" | LC_ALL=C wc -c | tr -d '[:space:]')"
  if [ "$diff_bytes" -gt "$max_inline" ]; then
    AGY_REVIEW_TMP="$(mktemp -d "${TMPDIR:-/tmp}/agy_review.XXXXXX")"
    # Global (not local) so the EXIT trap can still see it after return.
    trap 'rm -rf "${AGY_REVIEW_TMP:-}"' EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM
    printf '%s\n' "$diff" > "$AGY_REVIEW_TMP/review.diff"
    full="$(printf '%s\n\nThe diff to review is too large to inline. Read it from this file (unified diff format): %s' \
      "$focus" "$AGY_REVIEW_TMP/review.diff")"
    set -- --add-dir "$AGY_REVIEW_TMP" "$@"
  else
    full=$(printf '%s\n\nDiff:\n```diff\n%s\n```\n' "$focus" "$diff")
  fi

  local rc=0
  local default_print_timeout="15m"
  if [ -n "$model" ]; then
    run_agy "$path" -p "$full" --model "$model" "$@" || rc=$?
  else
    run_agy "$path" -p "$full" "$@" || rc=$?
  fi
  if [ -n "${AGY_REVIEW_TMP:-}" ]; then
    rm -rf "$AGY_REVIEW_TMP"
    AGY_REVIEW_TMP=""
  fi
  return "$rc"
}

lower_ext() {
  local base="${1##*/}"
  local ext="${base##*.}"
  [ "$ext" = "$base" ] && ext=""
  printf '%s' "$ext" | tr '[:upper:]' '[:lower:]'
}

# copy_image <src> <dest>: copy, converting format when the extensions
# disagree (agy usually saves JPEG; asking for out.png should give a PNG).
copy_image() {
  local src="$1" dest="$2"
  local src_ext dest_ext
  src_ext="$(lower_ext "$src")"
  dest_ext="$(lower_ext "$dest")"
  [ "$src_ext" = "jpg" ] && src_ext="jpeg"
  [ "$dest_ext" = "jpg" ] && dest_ext="jpeg"

  if [ -z "$dest_ext" ] || [ "$src_ext" = "$dest_ext" ]; then
    cp "$src" "$dest"
    echo "[wrapper] copied to: $dest"
    return 0
  fi
  if command -v sips >/dev/null 2>&1 \
      && sips -s format "$dest_ext" "$src" --out "$dest" >/dev/null 2>&1; then
    echo "[wrapper] converted $src_ext -> $dest_ext: $dest"
    return 0
  fi
  if command -v magick >/dev/null 2>&1 && magick "$src" "$dest" >/dev/null 2>&1; then
    echo "[wrapper] converted $src_ext -> $dest_ext: $dest"
    return 0
  fi
  cp "$src" "$dest"
  echo "[wrapper] copied to: $dest"
  echo "[wrapper] warning: source is .$src_ext but $dest was requested and no converter (sips/magick) was available; the file contents are still $src_ext." >&2
}

cmd_image() {
  local description=""
  local name=""
  local output=""
  local model=""
  local model_flag_seen=0
  local positional=()
  while [ $# -gt 0 ]; do
    case "$1" in
      --model)
        model_flag_seen=1
        if [ $# -ge 2 ]; then
          model="$2"; shift 2
        else
          shift
        fi ;;
      --model=*)
        model_flag_seen=1
        model="${1#--model=}"
        shift ;;
      --name)
        if [ $# -ge 2 ]; then
          name="$2"; shift 2
        else
          echo "error: --name requires a value (e.g. --name coffee_cup)" >&2
          exit 64
        fi ;;
      --name=*)
        name="${1#--name=}"
        if [ -z "$name" ]; then
          echo "error: --name= requires a non-empty value" >&2
          exit 64
        fi
        shift ;;
      --output)
        if [ $# -ge 2 ]; then
          output="$2"; shift 2
        else
          echo "error: --output requires a path (e.g. --output /tmp/out.png)" >&2
          exit 64
        fi ;;
      --output=*)
        output="${1#--output=}"
        if [ -z "$output" ]; then
          echo "error: --output= requires a non-empty path" >&2
          exit 64
        fi
        shift ;;
      --)        shift; positional+=("$@"); break ;;
      *)         positional+=("$1"); shift ;;
    esac
  done
  if [ "$model_flag_seen" -eq 1 ] && [ -z "$model" ]; then
    echo "error: --model requires a non-empty value (run /agy:models to see available models)" >&2
    exit 64
  fi
  description="${positional[*]:-}"
  if [ -z "$description" ] && [ ! -t 0 ]; then
    description="$(cat)"
    description="${description%$'\n'}"
  fi
  if [ -z "$description" ]; then
    echo "error: image requires a description" >&2
    exit 64
  fi
  local agy_path
  agy_path="$(require_ready)"

  local name_clause=""
  if [ -n "$name" ]; then
    name_clause=" Save the image with name \"${name}\"."
  fi
  local prompt
  prompt="Use your built-in image generation (the image-generator subagent / generate_image tool) to create the following image. Description: ${description}.${name_clause}

After the tool returns, you MUST end your reply with a single line in this exact format (no quotes, no markdown, nothing after it):
IMAGE_PATH: <absolute filesystem path to the saved image>

The IMAGE_PATH line is required — the calling wrapper parses it to locate the file."

  local response rc=0
  local default_print_timeout="10m"
  if [ -n "$model" ]; then
    response="$(run_agy "$agy_path" -p "$prompt" --model "$model" 2>&1)" || rc=$?
  else
    response="$(run_agy "$agy_path" -p "$prompt" 2>&1)" || rc=$?
  fi
  printf '%s\n' "$response"

  local src
  src="$(printf '%s' "$response" \
    | sed -n 's/^[[:space:]]*IMAGE_PATH:[[:space:]]*//p' \
    | tail -n1)"

  # Fallback when the model skips the marker line.
  if [ -z "$src" ] || [ ! -f "$src" ]; then
    src="$(printf '%s' "$response" \
      | grep -oE '/[^[:space:]]+\.(png|jpg|jpeg|webp)' \
      | head -n1 || true)"
  fi

  if [ -n "$src" ] && [ -f "$src" ]; then
    echo
    echo "[wrapper] generated: $src"
    if [ -n "$output" ]; then
      copy_image "$src" "$output"
    fi
  else
    echo
    echo "[wrapper] warning: agy did not include an IMAGE_PATH line and no image path was found in its reply." >&2
    echo "[wrapper]          if --output was requested, the copy was skipped." >&2
  fi
  return "$rc"
}

cmd_help() {
  cat <<'HELP'
/agy:* commands (Claude Code plugin for the Antigravity CLI)

Slash commands
  /agy:setup                            Verify agy install + auth. Offers install if missing.
  /agy:ask [--model M] <prompt>         One-shot prompt; returns agy's response verbatim.
  /agy:delegate [--background] [--model M] <task>
                                        Hand a task to the agy:runner subagent.
  /agy:research [--background] [--model M] <topic>
                                        Deep-research investigation via agy:runner.
  /agy:review [--model M] [--base REF] [focus]
                                        Review uncommitted changes (incl. untracked
                                        files), or everything since REF with --base.
  /agy:image [--model M] [--name S] [--output P] <description>
                                        Generate an image via agy's built-in tool.
  /agy:models                           List available models with recommended use cases.
  /agy:help                             This help.

Model selection (--model)
  Pass the model's exact identifier or display label from `agy models`
  (or run /agy:models for a curated list with recommended use cases).

  Examples:
    --model claude-opus-4-6-thinking
    --model "Claude Opus 4.6 (Thinking)"
    --model gemini-3.8-flash-high
    --model "Gemini 3.1 Pro (High)"

How --model works
  The plugin forwards the model value directly to agy's own native
  `--model` flag for that call. agy accepts either the model id or
  canonical display label verbatim. No settings.json is touched, so a
  TUI session running in parallel is unaffected.

  If an invalid model is provided, agy rejects it and prints its list
  of available models. Run /agy:models or `agy models` for the live list.

Follow-ups (multi-turn)
  /agy:ask, /agy:delegate, /agy:research and /agy:review end with a line
    [agy] conversation: <id>
  Pass `--conversation <id>` on the next call to continue that same agy
  conversation with its full history (agy keeps it server-side).
  Set AGY_PLAIN_OUTPUT=1 to get agy's raw text output without this line.

Useful agy-native flags (passed straight through)
  --effort low|medium|high|xhigh|max   Reasoning effort for this call.
  --conversation <id>                  Continue a previous conversation.
  --add-dir <path>                     Add a directory to agy's workspace.
  --sandbox                            Run with terminal restrictions.
  --print-timeout 10m                  Cap the run. Defaults: review 15m,
                                       image 10m, ask/delegate/research none.
                                       AGY_PRINT_TIMEOUT overrides (0 = none).
  --json-schema <json|file>            Enforce a structured (object) reply.

Exit codes
  0 ok · 1 not authenticated / no diff / bad model · 3 agy model or agent
  error, e.g. no model capacity (see the `[agy] error:` / AGY_ERROR line on
  stderr; any partial response is still printed) · 64 bad wrapper usage ·
  124 print timeout hit (partial reply; follow up with --conversation) ·
  127 agy not installed.

Underlying CLI
  Run `agy --help` for agy's own flags. Subcommands: agents, changelog,
  help, install, mcp, models, plugin/plugins, remote-control, update.
HELP
}

main() {
  case "${1:-}" in
    check)              cmd_check ;;
    ask)     shift;     cmd_ask "$@" ;;
    review)  shift;     cmd_review "$@" ;;
    image)   shift;     cmd_image "$@" ;;
    models)             cmd_models ;;
    help|-h|--help|"")  cmd_help ;;
    *)                  echo "error: unknown subcommand '$1'" >&2; cmd_help >&2; exit 64 ;;
  esac
}

# Skip dispatch when sourced (lets unit tests call functions directly).
if [ "${BASH_SOURCE[0]:-}" = "${0:-}" ]; then
  main "$@"
fi
