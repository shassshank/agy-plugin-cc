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
  # both are set), or Application Default Credentials with AGY_ADC_AUTH.
  # Google sign-in lives in the OS keychain (macOS Keychain, Windows
  # Credential Manager) and only falls back to a token file when the
  # keychain is unavailable, so a missing file proves nothing: ask agy
  # itself with `agy models`, which fails fast with "Please sign in" when
  # signed out (an unauthenticated `agy -p` instead waits 60s for a browser
  # login). The probe's output seeds the per-session models cache, and a
  # cached list means this session already proved the sign-in works.
  if [ -n "${GEMINI_API_KEY:-}" ] || [ -n "${GOOGLE_API_KEY:-}" ]; then
    echo "api-key"; return
  fi
  if [ -n "${AGY_ADC_AUTH:-}" ]; then
    echo "adc"; return
  fi
  if [ -s "$HOME/.gemini/antigravity-cli/antigravity-oauth-token" ] \
      || [ -s "$(models_cache_file)" ]; then
    echo "oauth"; return
  fi
  local path out rc=0
  path="${1:-$(find_agy | head -n1)}" || { echo "unknown"; return; }
  out="$("$path" models 2>&1 </dev/null)" || rc=$?
  if [ "$rc" -eq 0 ] && printf '%s\n' "$out" | grep -q $'\t'; then
    printf '%s\n' "$out" | grep $'\t' > "$(models_cache_file)" 2>/dev/null || true
    echo "oauth"
  elif printf '%s' "$out" | grep -qiE 'sign in|log in|authenticat'; then
    echo "missing"
  else
    # Network trouble or an unexpected reply: let the real call decide.
    echo "unknown"
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
  auth="$(auth_status "$path")"
  local warning=""
  if version_lt "$version" "$MIN_AGY_VERSION"; then
    warning="agy $version is older than $MIN_AGY_VERSION, which this plugin is tested on; older versions can report a successful run as an error (exit 3) after a retried model request. Update with: agy update"
  fi
  printf '{ "installed": true, "path": "%s", "version": "%s", "auth": "%s", "warning": "%s", "error": "" }\n' \
    "$(j_esc "$path")" "$(j_esc "$version")" "$(j_esc "$auth")" "$(j_esc "$warning")"
}

# Oldest agy release the plugin is tested on: 1.5.13 stopped reporting
# `status: ERROR` for runs that succeeded after a retried model request.
MIN_AGY_VERSION="1.5.13"

# version_lt A B: succeeds when x.y.z version A is older than B.
version_lt() {
  local va="${1%%[!0-9.]*}" vb="${2%%[!0-9.]*}"
  [ -n "$va" ] && [ -n "$vb" ] || return 1  # unparseable: don't warn
  local IFS=.
  local -a a=($va) b=($vb)
  local i
  for i in 0 1 2; do
    local x="${a[$i]:-0}" y="${b[$i]:-0}"
    case "$x$y" in ''|*[!0-9]*) return 1 ;; esac
    [ "$((10#$x))" -lt "$((10#$y))" ] && return 0
    [ "$((10#$x))" -gt "$((10#$y))" ] && return 1
  done
  return 1
}

require_ready() {
  if ! path="$(find_agy | head -n1)"; then
    echo "error: agy is not installed." >&2
    echo "       install: curl -fsSL https://antigravity.google/cli/install.sh | bash" >&2
    exit 127
  fi
  if [ "$(auth_status "$path")" = "missing" ]; then
    echo "error: agy is not authenticated." >&2
    echo "       run \`agy\` once interactively to sign in, or export GEMINI_API_KEY" >&2
    exit 1
  fi
  echo "$path"
}

# read_only_settings: print a JSON object for agy's per-run `--settings`
# flag that denies the file-edit tool (`write_file`), so a review or a
# question cannot change the working tree. Since agy 1.5.7 headless runs
# default to Auto mode, which approves workspace edits without asking.
# The user's own `permissions` from settings.json are carried over (in
# case agy replaces the whole object rather than merging it). Reads and
# shell commands stay allowed. Prints nothing when python3 is missing.
read_only_settings() {
  command -v python3 >/dev/null 2>&1 || return 0
  python3 - "$HOME/.gemini/antigravity-cli/settings.json" <<'PY'
import json, sys
perms = {}
try:
    with open(sys.argv[1], encoding="utf-8-sig") as f:
        loaded = json.load(f).get("permissions")
    if isinstance(loaded, dict):
        perms = loaded
except (OSError, ValueError, AttributeError):
    pass
deny = [r for r in perms.get("deny", []) if isinstance(r, str)]
if "write_file(*)" not in deny:
    deny.append("write_file(*)")
perms["deny"] = deny
print(json.dumps({"permissions": perms}, separators=(",", ":")))
PY
}

# has_settings_flag <args...>: succeeds when the caller already passed
# --settings (theirs wins; the read-only guard is then not added).
has_settings_flag() {
  local a
  for a in "$@"; do
    case "$a" in --settings|--settings=*) return 0 ;; esac
  done
  return 1
}

# add_read_only_guard <args...>: set READ_ONLY_ARGS to the extra agy args
# that block file edits (empty when the caller passed its own --settings,
# or python3 is missing).
add_read_only_guard() {
  READ_ONLY_ARGS=()
  if has_settings_flag "$@"; then
    echo "[wrapper] --settings was passed; not adding the read-only edit guard." >&2
    return 0
  fi
  local settings
  settings="$(read_only_settings)"
  [ -n "$settings" ] && READ_ONLY_ARGS=(--settings "$settings")
  return 0
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
# overrides it for every command ("0" = no limit). A timed-out turn is
# detected from `finished_reason: "print_timeout"` in the JSON result
# (agy >= 1.4.11) or the `[agy] print timeout after` stderr line, and exits
# 124 whatever agy's own exit code was (agy >= 1.5.0 exits 3, older 0).
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
denied = data.get("denied_actions")
if denied:
    sys.stderr.write("[agy] denied actions (%d) — agy was not allowed to do these:\n" % len(denied))
    for item in denied:
        sys.stderr.write("  - %s\n" % (item if isinstance(item, str) else json.dumps(item)))
if data.get("finished_reason") == "print_timeout":
    sys.exit(124)
status = data.get("status")
if status and status != "SUCCESS":
    sys.stderr.write("[agy] status: %s\n" % status)
    if data.get("error"):
        sys.stderr.write("[agy] error: %s\n" % data["error"])
    sys.exit(3)
' || { local prc=$?; [ "$prc" -eq 124 ] && timed_out=1; [ "$rc" -eq 0 ] && rc="$prc"; }

  if [ "$timed_out" -eq 1 ]; then
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
  local read_only=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --read-only) read_only=1; shift ;;
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
  if [ "$read_only" -eq 1 ]; then
    add_read_only_guard "$@"
    set -- "$@" "${READ_ONLY_ARGS[@]+"${READ_ONLY_ARGS[@]}"}"
  fi
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

  # A reviewer must not edit the tree it reviews.
  add_read_only_guard "$@"
  set -- "$@" "${READ_ONLY_ARGS[@]+"${READ_ONLY_ARGS[@]}"}"

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
  /agy:ask [--model M] [--read-only] <prompt>
                                        One-shot prompt; returns agy's response verbatim.
                                        /agy:ask passes --read-only (file edits blocked).
  /agy:delegate [--background] [--model M] <task>
                                        Hand a task to the agy:runner subagent.
  /agy:research [--background] [--model M] <topic>
                                        Deep-research investigation via agy:runner.
  /agy:review [--model M] [--base REF] [focus]
                                        Review uncommitted changes (incl. untracked
                                        files), or everything since REF with --base.
                                        Always read-only: agy's file-edit tool is denied.
  /agy:image [--model M] [--name S] [--output P] <description>
                                        Generate an image via agy's built-in tool.
  /agy:models                           List available models with recommended use cases.
  /agy:help                             This help.

Model selection (--model)
  Pass the model's exact identifier or display label from `agy models`
  (or run /agy:models for a curated list with recommended use cases).
  The list depends on how you sign in (Google account, API key, Vertex AI).

  Examples:
    --model claude-opus-4-6-thinking
    --model "Claude Opus 4.6 (Thinking)"
    --model gemini-3.8-flash-high

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
  --conversation <id>                  Continue a previous conversation
                                       (agy 1.5.16 aliases: -r, --resume).
  --add-dir <path>                     Add a directory to agy's workspace.
  --sandbox                            Run with terminal restrictions.
  --print-timeout 10m                  Cap the run. Defaults: review 15m,
                                       image 10m, ask/delegate/research none.
                                       AGY_PRINT_TIMEOUT overrides (0 = none).
  --json-schema <json|file>            Enforce a structured (object) reply.
  --mode plan                          Plan only: agy writes a plan and stops
                                       without editing. Carry it out with
                                       --conversation <id> "proceed".
  --disable-slash-commands             Send a prompt that starts with "/"
                                       literally instead of as an agy skill.
  --mode accept-edits|auto             Headless runs default to auto (agy
                                       1.5.7+): workspace edits approved,
                                       commands sandboxed.
  --settings '<json>'                  Per-run settings.json override, never
                                       saved (replaces the read-only guard).

Exit codes
  0 ok · 1 not authenticated / no diff / bad model · 3 agy model or agent
  error, e.g. no model capacity (see the `[agy] error:` / AGY_ERROR line on
  stderr; any partial response is still printed) · 64 bad wrapper usage ·
  124 print timeout hit (partial reply; follow up with --conversation) ·
  127 agy not installed.

Underlying CLI
  Run `agy --help` for agy's own flags. Subcommands:
  acp, agents, changelog, help, install, mcp, mic-serve, models,
  plugin/plugins, remote-control, update.
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
