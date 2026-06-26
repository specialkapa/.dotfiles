#!/usr/bin/env bash
# refresh-next-event.sh — write the next Outlook event to a cache file the WezTerm
# tabline reads (%USERPROFILE%\.cache\wezterm-next-event, reachable from both WSL
# and the Windows-side WezTerm).
#
# No-op unless on WSL with classic PowerShell present. PowerShell is invoked by
# ABSOLUTE PATH on purpose — it must NOT be on $PATH (that breaks Claude Code on
# the WSL CLI), so we never rely on or modify PATH here.
set -euo pipefail

grep -qiE '(microsoft|wsl)' /proc/version 2>/dev/null || exit 0

PS="/mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe"
[ -x "$PS" ] || exit 0

dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ps1="$dir/next-event.ps1"
[ -f "$ps1" ] || exit 0

win_home="$(cmd.exe /C 'echo %USERPROFILE%' 2>/dev/null | tr -d '\r')"
[ -n "$win_home" ] || exit 0
cache_dir="$(wslpath -u "$win_home")/.cache"
mkdir -p "$cache_dir"
cache_file="$cache_dir/wezterm-next-event"

# Throttle: skip the slow PowerShell+Outlook call if the cache is fresh (<2 min).
# Keeps rapid tab/pane opening from spawning PowerShell every time. Pass --force
# to bypass (e.g. a manual refresh).
if [ "${1:-}" != "--force" ] && [ -f "$cache_file" ] && [ -n "$(find "$cache_file" -mmin -2 2>/dev/null)" ]; then
    exit 0
fi

# Feed the script via STDIN (-Command -) rather than -File: executing it from the
# \\wsl.localhost\ UNC path trips PowerShell's AuthorizationManager. `|| true`
# keeps a non-zero PowerShell exit (e.g. Outlook closed) from aborting the script.
out="$("$PS" -NoProfile -ExecutionPolicy Bypass -Command - <"$ps1" 2>/dev/null | tr -d '\r')" || true
printf '%s' "$out" >"$cache_file"
