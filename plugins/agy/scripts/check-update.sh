#!/usr/bin/env bash
# check-update.sh — SessionStart hook: tell the user when a newer agy plugin
# version is published on GitHub. Never blocks or fails the session.
# Opt out with AGY_NO_UPDATE_CHECK=1.

set -u

REMOTE_URL="https://raw.githubusercontent.com/shassshank/agy-plugin-cc/main/plugins/agy/.claude-plugin/plugin.json"
CACHE_TTL=86400  # re-check GitHub at most once a day

[ "${AGY_NO_UPDATE_CHECK:-}" = "1" ] && exit 0

plugin_root="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
cache_dir="${CLAUDE_PLUGIN_DATA:-$HOME/.cache/agy-plugin-cc}"
cache_file="$cache_dir/latest-version"

read_version() {
  grep -m1 '"version"' | sed -E 's/.*"version"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/'
}

# Succeeds when $1 is a strictly newer x.y.z version than $2.
version_gt() {
  local IFS=.
  local -a a=(${1%%-*}) b=(${2%%-*})
  local i
  for i in 0 1 2; do
    local x="${a[$i]:-0}" y="${b[$i]:-0}"
    case "$x$y" in *[!0-9]*) return 1 ;; esac
    [ "$((10#$x))" -gt "$((10#$y))" ] && return 0
    [ "$((10#$x))" -lt "$((10#$y))" ] && return 1
  done
  return 1
}

current="$(read_version < "$plugin_root/.claude-plugin/plugin.json" 2>/dev/null)"
[ -n "$current" ] || exit 0

latest=""
if [ -f "$cache_file" ]; then
  mtime="$(stat -f %m "$cache_file" 2>/dev/null || stat -c %Y "$cache_file" 2>/dev/null || echo 0)"
  if [ $(( $(date +%s) - mtime )) -lt "$CACHE_TTL" ]; then
    latest="$(cat "$cache_file" 2>/dev/null)"
  fi
fi

if [ -z "$latest" ] && command -v curl >/dev/null 2>&1; then
  latest="$(curl -fsSL --max-time 3 "$REMOTE_URL" 2>/dev/null | read_version)"
  if [ -n "$latest" ]; then
    mkdir -p "$cache_dir" 2>/dev/null && printf '%s\n' "$latest" > "$cache_file" 2>/dev/null
  fi
fi

[ -n "$latest" ] || exit 0
version_gt "$latest" "$current" || exit 0

msg="agy plugin update available: v$current → v$latest. Update with: claude plugin marketplace update agy-plugin-cc && claude plugin update agy@agy-plugin-cc — then restart Claude Code. Changelog: https://github.com/shassshank/agy-plugin-cc/blob/main/CHANGELOG.md"

printf '{"systemMessage":"%s","hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"%s"}}\n' "$msg" "$msg"
exit 0
