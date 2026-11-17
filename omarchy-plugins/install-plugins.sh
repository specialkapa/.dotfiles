#!/usr/bin/env bash
#
# install-plugins.sh — recreate this machine's Omarchy plugins on another one.
#
#   ./install-plugins.sh            install/pin everything (idempotent)
#   ./install-plugins.sh --dry-run  show what would happen
#
# What it does:
#   1. installs the packages the plugins need,
#   2. clones every plugin in plugins.lock at its pinned commit (existing clones
#      are moved to that commit if they are clean). That includes my own plugins,
#      which live in their own GitHub repos (cloned over https, pushed over ssh),
#   3. links the Superwhisper panel shipped by superwhisper-bin,
#   4. registers the Spotify Downloader native messaging host with Brave.
#
# Which plugins are enabled, and their settings, live in
# ~/.config/omarchy/shell.json (the `omarchy` package).
set -euo pipefail

HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PLUGINS="$HOME/.config/omarchy/plugins"
LOCK="$HERE/plugins.lock"
OWNER=specialkapa # my own plugins: push over ssh
dry_run=0
[[ ${1:-} == "-n" || ${1:-} == "--dry-run" ]] && dry_run=1

info() { echo -e "\033[94m==>\033[0m $*" >&2; }
warn() { echo -e "\033[0;33m$*\033[0m" >&2; }
run() { if ((dry_run)); then echo "  [dry-run] $*" >&2; else "$@"; fi; }

# Packages needed by the plugins (repo packages; hypr-rdp is handled by
# remote-access/setup.sh because it comes from the AUR).
#   specialkapa.spotify-dl: yt-dlp ffmpeg mpd rmpc mpd-mpris wl-clipboard libnotify jq
#   specialkapa.visualizer: cava
#   superwhisper.panel:     superwhisper-bin
#   specialkapa.solar-nightlight: ddcutil (ships the i2c udev rule + i2c-dev module load)
#                           brightnessctl hyprsunset python
PACKAGES=(yt-dlp ffmpeg mpd rmpc mpd-mpris wl-clipboard libnotify jq cava superwhisper-bin git
	ddcutil brightnessctl hyprsunset python)

info "Plugin packages"
if omarchy pkg missing "${PACKAGES[@]}"; then
	run omarchy pkg add "${PACKAGES[@]}"
else
	echo "  all present" >&2
fi

run mkdir -p "$PLUGINS"

info "Plugins (plugins.lock)"
while read -r id url commit; do
	[[ -z $id || $id == \#* ]] && continue
	dir="$PLUGINS/$id"
	if [[ ! -d $dir ]]; then
		echo "  adding $id" >&2
		run omarchy plugin add "$url" --yes
	fi
	if ((dry_run)); then
		echo "  [dry-run] pin $id at ${commit:0:7}" >&2
		continue
	fi
	if [[ ! -d $dir/.git ]]; then
		warn "  $id: $dir is not a git clone; leaving it alone"
		continue
	fi
	head=$(git -C "$dir" rev-parse HEAD)
	if [[ $url == "https://github.com/$OWNER/"* ]]; then
		# Mine: stay on the branch (I develop in these clones), push over ssh.
		git -C "$dir" remote set-url --push origin "git@github.com:${url#https://github.com/}"
		echo "  $id on $(git -C "$dir" branch --show-current) at ${head:0:7} (mine; lock says ${commit:0:7})" >&2
		continue
	fi
	if [[ $head == "$commit" ]]; then
		echo "  $id at ${commit:0:7}" >&2
	elif [[ -n $(git -C "$dir" status --porcelain) ]]; then
		warn "  $id has local changes; not moving it from ${head:0:7} to ${commit:0:7}"
	else
		git -C "$dir" cat-file -e "$commit^{commit}" 2>/dev/null || git -C "$dir" fetch --quiet origin || true
		if git -C "$dir" cat-file -e "$commit^{commit}" 2>/dev/null; then
			git -C "$dir" -c advice.detachedHead=false checkout --quiet "$commit"
			echo "  $id pinned at ${commit:0:7} (was ${head:0:7})" >&2
		else
			warn "  $id: ${commit:0:7} was never pushed; staying on ${head:0:7}"
		fi
	fi
done <"$LOCK"

info "Superwhisper panel"
SW=/opt/superwhisper/assets/omarchy-plugin/superwhisper-panel
if [[ -d $SW ]]; then
	if [[ $(readlink "$PLUGINS/superwhisper-panel" 2>/dev/null) != "$SW" ]]; then
		run ln -sfn "$SW" "$PLUGINS/superwhisper-panel"
	fi
	echo "  linked" >&2
else
	warn "  $SW not found (is superwhisper-bin installed?)"
fi

info "Spotify Downloader browser host"
if [[ -d $HOME/.config/BraveSoftware/Brave-Browser ]]; then
	run "$PLUGINS/specialkapa.spotify-dl/bin/install-browser-host" brave
else
	warn "  Brave profile not found yet; after first launching Brave run:"
	warn "  ~/.config/omarchy/plugins/specialkapa.spotify-dl/bin/install-browser-host"
fi

echo "Done. Run 'omarchy restart shell' if plugins were added." >&2
