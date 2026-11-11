#!/usr/bin/env bash
#
# setup.sh — link these dotfiles into $HOME with stow, on any of my machines.
#
#   ./setup.sh                    detect the machine, confirm, then set up
#   ./setup.sh --profile omarchy  skip detection (wsl | omarchy | linux)
#   ./setup.sh --yes              no prompts (git identity must already be known)
#   ./setup.sh --dry-run          show what would happen, change nothing
#
# Profiles:
#   wsl      Windows + WSL2 Ubuntu (work laptop). WezTerm runs on Windows.
#   omarchy  Omarchy (Arch + Hyprland). Native WezTerm; my themes override Omarchy's.
#   linux    Any other Linux.
#
# Anything already in $HOME that would block a link is moved to
# ~/.dotfiles-backup/<timestamp>/ first, never deleted.

# Refuse to be sourced: `set -e` below would leak into (and later close) your shell.
if (return 0 2>/dev/null); then
	echo "Run this script (e.g. ./$(basename "${BASH_SOURCE[0]}")), don't source it." >&2
	return 1
fi

set -euo pipefail

DOTFILES="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKUP_DIR="$HOME/.dotfiles-backup/$(date +%Y%m%d-%H%M%S)"

# Same set everywhere; profiles differ in the extra steps, not in what's linked.
PACKAGES=(bat btop fastfetch gh-dash git git-graph lazygit nvim opencode starship vim vimwiki wezterm)

# Directories that are a whole config of their own: an existing one is backed up
# as a unit instead of being merged file-by-file with the repo's (which would
# leave stale plugin files from the old config lying around).
WHOLE_DIRS=(.config/nvim)

BTOP_THEME="catppuccin_mocha"

profile=""
assume_yes=0
dry_run=0

red() { echo -e "\033[91;1m$*\033[0m" >&2; }
green() { echo -e "\033[92;1m$*\033[0m" >&2; }
yellow() { echo -e "\033[0;33m$*\033[0m" >&2; }
info() { echo -e "\033[94m==>\033[0m $*" >&2; }
command_exists() { command -v "$1" >/dev/null 2>&1; }

run() {
	if ((dry_run)); then
		echo "  [dry-run] $*" >&2
	else
		"$@"
	fi
}

usage() {
	sed -n '3,16p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

while (($#)); do
	case $1 in
	--profile)
		profile=${2:-}
		shift 2
		;;
	--profile=*)
		profile=${1#*=}
		shift
		;;
	-y | --yes)
		assume_yes=1
		shift
		;;
	-n | --dry-run)
		dry_run=1
		shift
		;;
	-h | --help)
		usage
		exit 0
		;;
	*)
		red "unknown argument: $1"
		usage
		exit 1
		;;
	esac
done

# ── Detection ────────────────────────────────────────────────────────────────
detect_profile() {
	if grep -qiE '(microsoft|wsl)' /proc/version 2>/dev/null; then
		echo wsl
	elif [[ -d $HOME/.local/share/omarchy ]]; then
		echo omarchy
	else
		echo linux
	fi
}

confirm() { # confirm "question" -> 0 for yes (default yes)
	((assume_yes)) && return 0
	local answer
	read -r -p "$1 [Y/n]: " answer
	[[ -z $answer || $answer =~ ^[Yy] ]]
}

choose_profile() {
	local detected
	detected=$(detect_profile)
	if [[ -n $profile ]]; then
		info "Profile: $profile (from --profile; detected: $detected)"
	else
		profile=$detected
		if ! confirm "Detected machine profile '$profile'. Continue with it?"; then
			read -r -p "Profile to use (wsl/omarchy/linux): " profile
		fi
	fi
	case $profile in
	wsl | omarchy | linux) ;;
	*)
		red "unknown profile: $profile"
		exit 1
		;;
	esac
}

# ── Prerequisites ────────────────────────────────────────────────────────────
pkg_install() {
	if command_exists pacman; then
		run sudo pacman -S --needed --noconfirm "$@"
	elif command_exists apt-get; then
		run sudo apt-get install -y "$@"
	elif command_exists brew; then
		run brew install "$@"
	else
		red "no supported package manager to install: $*"
		return 1
	fi
}

ensure_prereqs() {
	if ! command_exists stow; then
		info "Installing stow"
		pkg_install stow
	fi
	ensure_delta
	ensure_starship
	# Nerd Font for WezTerm/nvim icons. On WSL it must be installed on *Windows*
	# instead (see README), so only handle native Linux here.
	if [[ $profile != wsl ]] && ! fc-list 2>/dev/null | grep -qi 'FiraCode Nerd Font'; then
		if command_exists pacman; then
			info "Installing FiraCode Nerd Font"
			pkg_install ttf-firacode-nerd
		else
			yellow "FiraCode Nerd Font not found; install it so WezTerm renders icons."
		fi
	fi
}

# delta is the git pager in git/.gitconfig: without it `git diff/log/show` fail.
# Package is `git-delta` everywhere; prefer the system package manager.
ensure_delta() {
	if command_exists delta; then
		return 0
	fi
	info "Installing delta (git pager)"
	if command_exists pacman; then
		pkg_install git-delta
	elif command_exists brew; then
		run brew install git-delta
	elif command_exists apt-get && apt-cache show git-delta >/dev/null 2>&1; then
		pkg_install git-delta # Ubuntu 24.04+; older releases fall through
	elif command_exists cargo; then
		run cargo install --locked git-delta
	else
		red "Could not install delta: no pacman/brew/apt git-delta/cargo. git diff will fail."
		return 1
	fi
	if ((!dry_run)) && ! command_exists delta; then
		red "delta still not on PATH after install (open a new shell?)."
		return 1
	fi
}

# Prompt: starship everywhere (config in starship/.config/starship.toml).
ensure_starship() {
	if command_exists starship; then
		return 0
	fi
	info "Installing starship"
	if command_exists pacman; then
		pkg_install starship
	elif command_exists brew; then
		run brew install starship
	else
		run mkdir -p "$HOME/.local/bin"
		if ((!dry_run)); then
			curl -sS https://starship.rs/install.sh | sh -s -- -y -b "$HOME/.local/bin"
		fi
	fi
}

# Omarchy already runs `starship init` from its own bash rc; elsewhere add it to
# ~/.bashrc once, and switch off the old oh-my-posh init if it's still there.
enable_starship_in_bashrc() {
	local rc="$HOME/.bashrc" marker="# dotfiles: starship prompt"
	touch "$rc"
	if grep -qE '^[^#]*oh-my-posh init' "$rc"; then
		info "Commenting out the old oh-my-posh init in $rc (backup: $rc.pre-starship)"
		run cp "$rc" "$rc.pre-starship"
		run sed -i -E 's/^([^#]*oh-my-posh init.*)$/# \1  # replaced by starship/' "$rc"
	fi
	if ! grep -qF "$marker" "$rc"; then
		info "Adding starship init to $rc"
		if ((dry_run)); then
			echo "  [dry-run] append starship init to $rc" >&2
		else
			printf '\n%s\neval "$(starship init bash)"\n' "$marker" >>"$rc"
		fi
	fi
}

# ── Git identity (kept out of the repo in ~/.gitconfig.local) ────────────────
setup_git_identity() {
	local local_cfg="$HOME/.gitconfig.local"
	local cur_name cur_email name email
	cur_name=$(git config -f "$local_cfg" user.name 2>/dev/null || git config --global user.name 2>/dev/null || true)
	cur_email=$(git config -f "$local_cfg" user.email 2>/dev/null || git config --global user.email 2>/dev/null || true)

	if ((assume_yes)); then
		name=$cur_name
		email=$cur_email
	else
		info "Git identity for this machine (stored in $local_cfg, not committed)"
		read -r -p "  Name  [${cur_name}]: " name
		read -r -p "  Email [${cur_email}]: " email
		name=${name:-$cur_name}
		email=${email:-$cur_email}
	fi

	if [[ -z $name || -z $email ]]; then
		red "Git name and email are required (run without --yes to be asked)."
		exit 1
	fi
	run git config -f "$local_cfg" user.name "$name"
	run git config -f "$local_cfg" user.email "$email"
	green "Git identity: $name <$email>"
}

# ── Stow ─────────────────────────────────────────────────────────────────────
backup() { # backup <path relative to $HOME>
	local rel=$1
	yellow "  backing up ~/$rel -> $BACKUP_DIR/$rel"
	run mkdir -p "$(dirname "$BACKUP_DIR/$rel")"
	run mv "$HOME/$rel" "$BACKUP_DIR/$rel"
}

# Move aside anything in $HOME that would stop `stow <pkg>` from linking.
clear_conflicts() {
	local pkg=$1 src rel target dir
	local -a moved=()
	for dir in "${WHOLE_DIRS[@]}"; do
		if [[ -d $DOTFILES/$pkg/$dir && -d $HOME/$dir && ! -L $HOME/$dir ]]; then
			backup "$dir"
			moved+=("$dir/")
		fi
	done
	# Only dot-entries are linked; anything else at the package root is ignored
	# by stow (see wezterm/.stow-local-ignore).
	while IFS= read -r -d '' src; do
		rel=${src#"$DOTFILES/$pkg/"}
		for dir in "${moved[@]}"; do
			[[ $rel == "$dir"* ]] && continue 2
		done
		target="$HOME/$rel"
		[[ -e $target || -L $target ]] || continue
		# Already pointing at this repo (re-run) -> nothing to do.
		[[ $(readlink -f "$target") == "$(readlink -f "$src")" ]] && continue
		backup "$rel"
	done < <(find "$DOTFILES/$pkg" -mindepth 1 -path "$DOTFILES/$pkg/.*" \( -type f -o -type l \) -print0)
}

stow_all() {
	info "Linking packages into $HOME"
	local pkg
	for pkg in "${PACKAGES[@]}"; do
		clear_conflicts "$pkg"
		if ((dry_run)); then
			echo "  [dry-run] stow -R $pkg" >&2
		else
			stow -d "$DOTFILES" -t "$HOME" -R "$pkg"
			green "  linked $pkg"
		fi
	done
}

# ── Profile-specific steps ───────────────────────────────────────────────────
use_my_btop_theme() {
	# Omarchy's btop.conf points at its theme (`current`); point it at mine instead.
	# Omarchy's theme switcher only *reloads* btop, so this choice sticks.
	local conf="$HOME/.config/btop/btop.conf"
	if [[ -f $conf ]]; then
		info "btop: color_theme = $BTOP_THEME"
		run sed -i "s/^color_theme = .*/color_theme = \"$BTOP_THEME\"/" "$conf"
	else
		yellow "btop.conf not found yet; run btop once, then set color_theme = \"$BTOP_THEME\"."
	fi
}

profile_wsl() {
	enable_starship_in_bashrc
	if confirm "Generate the Windows-side WezTerm loader now?"; then
		run "$DOTFILES/wezterm/install-windows-loader.sh"
	fi
}

profile_omarchy() {
	use_my_btop_theme
	yellow "Note: Omarchy's 'refresh fastfetch' (and some migrations) copy their default"
	yellow "over ~/.config/fastfetch/config.jsonc, which writes *through* the link into"
	yellow "this repo. If 'git status' ever shows that file changed, 'git checkout' it."
}

profile_linux() {
	use_my_btop_theme
	enable_starship_in_bashrc
}

# ── Main ─────────────────────────────────────────────────────────────────────
choose_profile
ensure_prereqs
setup_git_identity
stow_all
"profile_$profile"

if [[ -d $BACKUP_DIR ]]; then
	yellow "Previous files were saved in $BACKUP_DIR"
fi
green "Done ($profile). For nvim dependencies run: ~/.config/nvim/scripts/install.sh"
