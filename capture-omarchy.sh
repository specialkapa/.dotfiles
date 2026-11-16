#!/usr/bin/env bash
#
# capture-omarchy.sh — pull this machine's current Omarchy state back into the repo.
#
#   ./capture-omarchy.sh            capture, then show `git status`
#   ./capture-omarchy.sh --dry-run  only report what would be captured
#   ./capture-omarchy.sh --auto     what the background watcher runs: quiet, and a
#                                   desktop notification only when there is news
#
# You normally don't run this yourself: the omarchy-autocapture package runs it
# (systemd user path unit + timer) whenever Omarchy saves its config or a plugin
# is added/removed. It never commits; review with `git status` and commit.
#
# It handles the ways the live setup drifts away from the repo:
#   - Omarchy (migrations, `omarchy plugin enable`, the bar UI) often saves
#     files like shell.json by replacing the link with a plain file. The plain
#     file is the newest state, so it is moved into the repo and re-linked.
#   - New hyprmoncfg monitor profiles are moved into the repo and linked.
#   - Plugins added, removed or updated -> plugins.lock is rewritten. Every
#     plugin is a git clone (mine live in their own GitHub repos too).
# And it warns (once per state) about what a new machine would NOT get:
#   - a plugin folder that is not a git clone,
#   - one of my plugins with uncommitted changes or a commit not pushed yet.
set -euo pipefail

DOTFILES="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PLUGINS="$HOME/.config/omarchy/plugins"
LOCK="$DOTFILES/omarchy-plugins/plugins.lock"
PROFILES="$HOME/.config/hyprmoncfg/profiles"
OWNER=specialkapa # GitHub owner of my own plugins
STATE="${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles-capture/warned"
dry_run=0
auto=0
case ${1:-} in
-n | --dry-run) dry_run=1 ;;
--auto) auto=1 ;;
"") ;;
*)
	echo "unknown argument: $1" >&2
	exit 1
	;;
esac

info() { ((auto)) || echo -e "\033[94m==>\033[0m $*" >&2; }
item() { # something captured into the repo
	captured+=("$1")
	echo "  $1" >&2
}
warn() { # something a new machine would miss
	warnings+=("$1")
	echo -e "  \033[0;33m$1\033[0m" >&2
}
captured=()
warnings=()

# 1. Linked files that were replaced by plain files.
info "Linked files replaced by plain files"
for pkg in omarchy hyprmoncfg; do
	relink=0
	while IFS= read -r -d '' src; do
		rel=${src#"$DOTFILES/$pkg/"}
		live="$HOME/$rel"
		[[ -f $live && ! -L $live ]] || continue
		# A folded directory link means the live file IS the repo file.
		[[ $(readlink -f "$live") == "$(readlink -f "$src")" ]] && continue
		item "~/$rel"
		if ((!dry_run)); then
			mv -f "$live" "$src"
			relink=1
		fi
	done < <(find "$DOTFILES/$pkg" -path "$DOTFILES/$pkg/.*" -type f -print0)
	if ((relink)); then stow -d "$DOTFILES" -t "$HOME" -R "$pkg"; fi
done

# 2. New monitor profiles.
info "Monitor profiles"
if [[ -d $PROFILES ]]; then
	relink=0
	for f in "$PROFILES"/*.json; do
		[[ -f $f && ! -L $f ]] || continue
		dest="$DOTFILES/hyprmoncfg/.config/hyprmoncfg/profiles/${f##*/}"
		[[ -e $dest ]] && continue # handled by step 1
		item "new monitor profile ${f##*/}"
		if ((!dry_run)); then
			mv "$f" "$dest"
			relink=1
		fi
	done
	if ((relink)); then stow -d "$DOTFILES" -t "$HOME" -R hyprmoncfg; fi
fi

# 3. Plugins.
info "Plugins"
new_lock=$(
	echo "# Omarchy plugins: <id> <git url> <commit>. Kept current by ./capture-omarchy.sh (runs automatically)"
	for dir in "$PLUGINS"/*/; do
		dir=${dir%/}
		[[ -L $dir || ! -d $dir/.git ]] && continue
		echo "${dir##*/} $(git -C "$dir" remote get-url origin) $(git -C "$dir" rev-parse HEAD)"
	done
)
if [[ $new_lock != "$(cat "$LOCK")" ]]; then
	while IFS= read -r line; do
		case $line in
		\<*) item "plugin removed/changed: ${line#< }" ;;
		\>*) item "plugin added/updated: ${line#> }" ;;
		esac
	done < <(diff <(grep -v '^#' "$LOCK" | cut -d' ' -f1,3 | sed 's/ \(.......\).*/ \1/') \
		<(grep -v '^#' <<<"$new_lock" | cut -d' ' -f1,3 | sed 's/ \(.......\).*/ \1/') || true)
	if ((!dry_run)); then printf '%s\n' "$new_lock" >"$LOCK"; fi
fi

for dir in "$PLUGINS"/*/; do
	dir=${dir%/}
	id=${dir##*/}
	[[ -L $dir ]] && continue
	if [[ ! -d $dir/.git ]]; then
		warn "$id is not a git repo, so a new machine won't get it"
		continue
	fi
	url=$(git -C "$dir" remote get-url origin 2>/dev/null || true)
	[[ $url == *"github.com/$OWNER/"* || $url == *"github.com:$OWNER/"* ]] || continue
	if [[ -n $(git -C "$dir" status --porcelain) ]]; then
		warn "$id has uncommitted changes (new machines get the last pushed commit)"
	elif [[ -z $(git -C "$dir" branch -r --contains HEAD 2>/dev/null) ]]; then
		warn "$id: commit $(git -C "$dir" rev-parse --short HEAD) is not pushed yet"
	fi
done

if ((auto)); then
	# Warnings repeat every run while they hold; only notify when they change.
	mkdir -p "${STATE%/*}"
	current=$(printf '%s\n' "${warnings[@]}")
	previous=$(cat "$STATE" 2>/dev/null || true)
	printf '%s' "$current" >"$STATE"
	body=""
	((${#captured[@]})) && body+=$(printf '• %s\n' "${captured[@]}")$'\n'
	if [[ -n $current && $current != "$previous" ]]; then
		body+=$(printf '⚠ %s\n' "${warnings[@]}")$'\n'
	fi
	if [[ -n $body ]]; then
		notify-send -a dotfiles -i folder-sync "~/.dotfiles" \
			"${body}Review with git status and commit when ready." 2>/dev/null || true
	fi
	exit 0
fi
if ((!${#captured[@]})); then echo "  nothing to capture" >&2; fi
if ((!dry_run)); then git -C "$DOTFILES" status --short; fi
