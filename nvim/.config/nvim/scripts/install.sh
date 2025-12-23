#!/usr/bin/env bash
set -euo pipefail

#------------------------------------------------------------------------------
# Displays an error message in bold red text with an icon.
#------------------------------------------------------------------------------
show_error() {
    echo -e "\033[91;1m $1\033[0m" >&2
}

#------------------------------------------------------------------------------
# Displays a success message in bold green text with a checkmark.
#------------------------------------------------------------------------------
show_success() {
    echo -e "\033[92;1m $1\033[0m" >&2
}

#------------------------------------------------------------------------------
# Displays a warning message in yellow text with an icon.
#------------------------------------------------------------------------------
show_warning() {
    echo -e "\033[0;33m $1\033[0m" >&2
}

#------------------------------------------------------------------------------
# Tiny helper to check if a command exists.
#------------------------------------------------------------------------------
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

#------------------------------------------------------------------------------
# Installs a package using apt-get and attempts a fallback method on failure.
#------------------------------------------------------------------------------
install_with_apt() {
    local package=$1

    sudo apt-get update
    if ! sudo apt-get install -y "$package"; then
        show_warning "Primary apt-get install failed for $package. Trying fallback method..."
        sudo apt-get update &&
            sudo apt-get install -y lsb-release &&
            sudo apt-get clean all &&
            sudo apt-get install -y "$package"
    fi
}

#------------------------------------------------------------------------------
# Installs a package using pacman with non-interactive flags.
#------------------------------------------------------------------------------
install_with_pacman() {
    local package=$1
    sudo pacman -Sy --noconfirm "$package"
}

#------------------------------------------------------------------------------
# Ensures a Homebrew package is installed, installing it if missing.
#------------------------------------------------------------------------------
install_with_brew() {
    local package=$1

    if brew list --formula "$package" >/dev/null 2>&1 ||
        brew list --cask "$package" >/dev/null 2>&1; then
        echo "$package is already installed with Homebrew."
        return 0
    fi

    if brew info --formula "$package" >/dev/null 2>&1; then
        brew install "$package"
    elif brew info --cask "$package" >/dev/null 2>&1; then
        brew install --cask "$package"
    else
        show_error "$package is not available in Homebrew repositories."
        return 1
    fi
}

#------------------------------------------------------------------------------
# Ensures a Cargo package is installed, installing it if necessary.
#------------------------------------------------------------------------------
install_cargo_package() {
    local package=$1

    if ! command_exists cargo; then
        show_error "cargo is not available. Install Rust and Cargo first."
        return 1
    fi

    if cargo install --list 2>/dev/null | grep -q "^$package v"; then
        show_warning "$package is already installed with Cargo."
        return 0
    fi

    if cargo install "$package"; then
        show_success "Cargo package $package installation complete."
    else
        show_error "Failed to install Cargo package $package."
        return 1
    fi
}

#------------------------------------------------------------------------------
# Detects the available package manager and delegates to the appropriate strategy.
#------------------------------------------------------------------------------
install_package_strategy() {
    local package=$1

    if command_exists apt-get; then
        install_with_apt "$package"
    elif command_exists pacman; then
        install_with_pacman "$package"
    elif command_exists brew; then
        install_with_brew "$package"
    else
        show_error "Unsupported package manager. None of apt-get, pacman, or brew found."
        return 1
    fi
}

#------------------------------------------------------------------------------
# Installs a package using the detected package manager if it is not already installed.
#------------------------------------------------------------------------------
install_if_not_exists() {
    local package=$1
    local binary=${2:-$package}

    if ! command_exists "$binary"; then
        echo "$package is not installed. Installing now."
        if install_package_strategy "$package"; then
            local message="$package installation complete!"
            if command_exists show_success; then
                show_success "$message"
            else
                echo "$message"
            fi
        else
            show_error "Failed to install $package."
            return 1
        fi
    else
        show_warning "$package is already installed."
    fi
}

cd "$HOME"

if command_exists nvim; then
    read -r -p "Neovim is already installed. Wipe existing configuration and reinstall? [y/N]: " wipe_choice
    if [[ "$wipe_choice" =~ ^[Yy]$ ]]; then
        rm -rf "$HOME/.config/nvim"
        rm -rf "$HOME/.local/share/nvim"
        rm -rf "$HOME/.local/state/nvim"
        rm -rf "$HOME/.cache/nvim"
    fi
fi

if curl -LsSf https://astral.sh/uv/install.sh | sh; then
    show_success "uv installation complete."
else
    show_error "uv installation failed."
fi

if command_exists opencode; then
    show_warning "opencode is already installed."
else
    if curl -fsSL https://opencode.ai/install | bash; then
        show_success "opencode installation complete."
    else
        show_error "opencode installation failed."
    fi
fi

if curl https://sh.rustup.rs -sSf | sh -s -- -y; then
    show_success "cargo/rust installation complete."
else
    show_error "cargo/rust installation failed."
fi

if curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.3/install.sh | bash; then
    show_success "nvm installation complete."
else
    show_error "nvm installation failed."
fi

if [ -s "$HOME/.nvm/nvm.sh" ]; then
    # shellcheck disable=SC1090
    . "$HOME/.nvm/nvm.sh"
fi

source $HOME/.bashrc

if command_exists nvm && nvm install node; then
    show_success "node installation via nvm complete."
else
    show_error "node installation via nvm failed."
fi

if ! command_exists brew; then
    if /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"; then
        echo >>/home/tnpadmin/.bashrc
        echo 'eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"' >>/home/tnpadmin/.bashrc
        eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
        show_success "homebrew installation complete."
    else
        show_error "homebrew installation failed."
    fi
fi

install_cargo_package grip-grab
install_cargo_package git-graph
install_if_not_exists ripgrep rg
install_if_not_exists fzf
install_if_not_exists fd-find fd
install_if_not_exists eza
install_with_brew lazygit
install_with_brew lazydocker
install_if_not_exists neovim nvim
install_with_brew git-delta
install_with_brew bat
install_with_brew stow
install_with_brew codex

if ! command_exists "atuin"; then
    echo "$package is not installed. Installing now."
    curl --proto '=https' --tlsv1.2 -LsSf https://setup.atuin.sh | sh
    source $HOME/.bashrc
    if command_exists "atuin"; then
        show_success "atuin installation complete."
    else
        show_error "Failed to install atuin."
        return 1
    fi
else
    show_warning "atuin is already installed."
fi

if [ -d "$HOME/.local/share/nvim/lazy-rocks" ]; then
    rm -rf "$HOME/.local/share/nvim/lazy-rocks"
fi

if command_exists apt-get; then
    sudo apt install -y lua5.1 luarocks build-essential curl
elif command_exists pacman; then
    sudo pacman -S lua51 luarocks base-devel curl

git config --global core.pager delta
git config --global interactive.diffFilter 'delta --color-only'
git config --global delta.navigate true
git config --global delta.dark true
git config --global delta.side-by-side true
git config --global delta.line-numbers true
git config --global delta.hyperlinks true
git config --global merge.conflictStyle zdiff3
git config --global autocrlf input

if [ ! -d "$HOME/.config" ]; then
    mkdir "$HOME/.config"
fi

cd "$HOME/.config"
git clone git@github.com:specialkapa/nvim-config.git nvim
