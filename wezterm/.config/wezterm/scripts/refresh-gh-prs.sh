#!/usr/bin/env bash
# refresh-gh-prs.sh — write the count of PRs awaiting my review to a cache the
# WezTerm tabline reads. NOT WSL-gated: runs anywhere gh exists. States written:
#   <n>   -> number of open PRs with review requested from me
#   auth  -> gh present but not authenticated
#   perm  -> authenticated but the token can't fetch (missing scope / 403)
#   err   -> other failure (e.g. network)
#   (empty) -> gh not installed → tabline hides the section
set -uo pipefail   # no -e: we handle each failure explicitly

# Cache target: on WSL, write to the Windows %USERPROFILE% so the Windows-side
# WezTerm can read it; on native Linux/mac, use $HOME/.cache.
cache_file=""
if command -v cmd.exe >/dev/null 2>&1; then
    win_home="$(cmd.exe /C 'echo %USERPROFILE%' 2>/dev/null | tr -d '\r')"
    [ -n "$win_home" ] && cache_file="$(wslpath -u "$win_home" 2>/dev/null)/.cache/wezterm-gh-prs"
fi
[ -z "$cache_file" ] && cache_file="$HOME/.cache/wezterm-gh-prs"
mkdir -p "$(dirname "$cache_file")"

write() { printf '%s' "$1" >"$cache_file"; }

# Throttle: skip the network call if the cache is fresh (<2 min); --force bypasses.
if [ "${1:-}" != "--force" ] && [ -f "$cache_file" ] && [ -n "$(find "$cache_file" -mmin -2 2>/dev/null)" ]; then
    exit 0
fi

command -v gh >/dev/null 2>&1 || { write ""; exit 0; }          # gh missing → hide
gh auth status >/dev/null 2>&1 || { write "auth"; exit 0; }      # not logged in

tmp_err="$(mktemp)"
count="$(gh search prs --review-requested=@me --state=open --json url --jq 'length' 2>"$tmp_err")"
rc=$?
err="$(cat "$tmp_err")"; rm -f "$tmp_err"

if [ "$rc" -eq 0 ] && [[ "$count" =~ ^[0-9]+$ ]]; then
    write "$count"
elif printf '%s' "$err" | grep -qiE '403|scope|forbidden|not accessible|permission'; then
    write "perm"
else
    write "err"
fi
