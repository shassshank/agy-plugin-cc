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
  if [ -n "${ANTIGRAVITY_API_KEY:-}" ]; then
    echo "api-key"
  elif [ -d "$HOME/.config/antigravity" ] || [ -d "$HOME/.gemini/antigravity-cli" ]; then
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
    echo "       run \`agy\` once interactively, or export ANTIGRAVITY_API_KEY" >&2
    exit 1
  fi
  echo "$path"
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
    "$path" -p "$prompt" --model "$model" "$@"
  else
    "$path" -p "$prompt" "$@"
  fi
}

cmd_review() {
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
  local diff
  diff="$(git -C "$repo_dir" diff HEAD 2>/dev/null || true)"
  if [ -z "$diff" ]; then
    diff="$(git -C "$repo_dir" diff 2>/dev/null || true)"
  fi
  if [ -z "$diff" ]; then
    echo "error: no git diff found in $repo_dir. Stage or make changes first." >&2
    exit 1
  fi
  local full
  full=$(printf '%s\n\nDiff:\n```diff\n%s\n```\n' "$focus" "$diff")
  if [ -n "$model" ]; then
    "$path" -p "$full" --model "$model" "$@"
  else
    "$path" -p "$full" "$@"
  fi
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
  prompt="Use your built-in generate_image tool to create the following image. Description: ${description}.${name_clause}

After the tool returns, you MUST end your reply with a single line in this exact format (no quotes, no markdown, nothing after it):
IMAGE_PATH: <absolute filesystem path to the saved image>

The IMAGE_PATH line is required — the calling wrapper parses it to locate the file."

  local response rc
  if [ -n "$model" ]; then
    response="$("$agy_path" -p "$prompt" --model "$model" 2>&1)" || rc=$?
  else
    response="$("$agy_path" -p "$prompt" 2>&1)" || rc=$?
  fi
  rc="${rc:-0}"
  printf '%s\n' "$response"

  local src
  src="$(printf '%s' "$response" \
    | sed -n 's/^[[:space:]]*IMAGE_PATH:[[:space:]]*//p' \
    | tail -n1)"

  # Fallback when the model skips the marker line.
  if [ -z "$src" ] || [ ! -f "$src" ]; then
    src="$(printf '%s' "$response" \
      | grep -oE '/[^[:space:]]+\.(png|jpg|jpeg|webp)' \
      | head -n1)"
  fi

  if [ -n "$src" ] && [ -f "$src" ]; then
    echo
    echo "[wrapper] generated: $src"
    if [ -n "$output" ]; then
      cp "$src" "$output"
      echo "[wrapper] copied to: $output"
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
  /agy:review [--model M] [focus]       Send current `git diff` to agy for review.
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

Underlying CLI
  Run `agy --help` for agy's own flags: --add-dir, -c/--continue,
  --conversation, --dangerously-skip-permissions, -i/--prompt-interactive,
  --log-file, -p/--print, --print-timeout, --sandbox.

  Subcommands: changelog, help, install, models, plugin/plugins, update.
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
