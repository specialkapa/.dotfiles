#!/usr/bin/env bash
# Interactive Claude Code session browser + deleter (uses charmbracelet/gum).
#
#   ./session-delete.sh            # browse & (optionally) delete sessions
#   ./session-delete.sh --list     # just print the table, never touch anything
#   ./session-delete.sh --hard     # permanently rm instead of moving to trash
#   ./session-delete.sh [ROOT]     # scan a different projects dir
#
# Selected sessions are moved to a trash dir by default (safe, restorable).
# Pass --hard (or set HARD_DELETE=1) to rm them outright instead.
set -euo pipefail

# ---- args -------------------------------------------------------------------
LIST_ONLY=0
HARD_DELETE="${HARD_DELETE:-0}"
ROOT="$HOME/.claude/projects"
for a in "$@"; do
  case "$a" in
    --list) LIST_ONLY=1 ;;
    --hard) HARD_DELETE=1 ;;
    -*)     echo "unknown flag: $a" >&2; exit 2 ;;
    *)      ROOT="$a" ;;
  esac
done

TRASH_DIR="$HOME/.claude/projects-trash"
DELIM=$'\x1f'   # unit-separator: safe delimiter between the visible label and the file path

command -v gum >/dev/null || { echo "gum is not installed" >&2; exit 1; }
command -v jq  >/dev/null || { echo "jq is not installed"  >&2; exit 1; }
[ -d "$ROOT" ] || { echo "no such dir: $ROOT" >&2; exit 1; }

# ---- gather sessions --------------------------------------------------------
# Each element is:  "<visible label>${DELIM}<absolute path>"
options=()
while IFS= read -r -d '' f; do
  base="$(basename "$f")"
  case "$base" in agent-*|journal*) continue ;; esac   # skip sub-agents & journals

  IFS=$'\t' read -r title msgs branch cwd < <(
    jq -rs '
      (map(select(.type=="ai-title") | .aiTitle) | last) as $t
      | if ($t // "") == "" then empty
        else [
          ($t | gsub("\t";" ")),
          (map(select(.type=="assistant" or .type=="user")) | length),
          ((map(select(.gitBranch) | .gitBranch) | last) // "-"),
          ((map(select(.cwd)       | .cwd)       | last) // "-")
        ] | @tsv end' "$f"
  ) || true
  [ -z "$title" ] && continue   # no ai-title -> skip

  sid="${base%.jsonl}"
  proj="$(basename "$cwd")"
  updated="$(date -r "$f" '+%Y-%m-%d %H:%M')"
  label="$(printf '%s  %-8.8s  %6s msg  %-26.26s  %s' \
             "$updated" "$sid" "$msgs" "$proj" "$title")"
  options+=("${label}${DELIM}${f}")
done < <(find "$ROOT" -type f -name '*.jsonl' -print0)

[ "${#options[@]}" -eq 0 ] && { echo "No titled sessions found under $ROOT"; exit 0; }

# newest-first (labels start with a sortable timestamp)
mapfile -t options < <(printf '%s\n' "${options[@]}" | sort -r)

# ---- list-only mode ---------------------------------------------------------
if [ "$LIST_ONLY" -eq 1 ]; then
  printf '%s\n' "${options[@]}" | sed "s/${DELIM}.*//"
  echo
  echo "${#options[@]} sessions"
  exit 0
fi

# ---- pick -------------------------------------------------------------------
# --label-delimiter makes gum show only the label but return the path.
selected="$(printf '%s\n' "${options[@]}" \
  | gum choose --no-limit --height 20 \
      --label-delimiter="$DELIM" \
      --header "↑↓ move · space select · enter confirm · esc cancel — pick sessions to DELETE")"

[ -z "$selected" ] && { echo "Nothing selected."; exit 0; }

# ---- confirm ----------------------------------------------------------------
count="$(printf '%s\n' "$selected" | grep -c .)"
echo "About to remove $count session(s):"
while IFS= read -r p; do
  [ -z "$p" ] && continue
  t="$(jq -rs 'map(select(.type=="ai-title") | .aiTitle) | last // "(untitled)"' "$p")"
  echo "  • $t  [$(basename "$p")]"
done <<< "$selected"
echo

if [ "$HARD_DELETE" = "1" ]; then
  gum confirm "Permanently delete these $count session(s)? This CANNOT be undone." || {
    echo "Aborted."; exit 0; }
  while IFS= read -r p; do
    [ -z "$p" ] && continue
    rm -- "$p" && echo "deleted  $p"
  done <<< "$selected"
else
  gum confirm "Move these $count session(s) to trash ($TRASH_DIR)?" || {
    echo "Aborted."; exit 0; }
  mkdir -p "$TRASH_DIR"
  while IFS= read -r p; do
    [ -z "$p" ] && continue
    # preserve the project-folder name so restores are unambiguous
    dest="$TRASH_DIR/$(basename "$(dirname "$p")")__$(basename "$p")"
    mv -- "$p" "$dest" && echo "trashed  $p"
  done <<< "$selected"
  echo
  echo "Restore any of them with:  mv \"$TRASH_DIR/<folder>__<uuid>.jsonl\" back to its project dir"
fi
