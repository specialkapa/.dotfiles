# dotfiles

This is where I maintain my dotfiles. The approach I am using this blog post
https://www.jakewiesler.com/blog/managing-dotfiles which leverages the `stow` package.

> [!NOTE] [$HOME](../..) should be the target directory.

> [!NOTE] [$HOME/.dotfiles](..) is the `stow` directory.

# instructions

When setting up a machine from scratch.

> [!IMPORTANT] You might have to do other things before any of the below steps. For example use
> `atlasformer` if using a TNP laptop.

> [!IMPORTANT] You need to install all the `neovim` dependencies. Refer to
> [README](./nvim/.config/nvim/README.md) for details.

1. clone this repository.
2. the run the following:

```bash
cd $HOME/.dotfiles
stow bat -R
stow git-graph
stow lazygit
stow nvim
stow vim
stow vimwiki
stow oh-my-posh
stow opencode
stow btop
stow gh-dash
stow wezterm
stow fastfetch
```

# wezterm (Windows + WSL)

WezTerm runs as a **Windows** app, so it does not read its config from WSL the normal way. The real
config is version-controlled here at [wezterm.lua](./wezterm/.config/wezterm/wezterm.lua), and a
small Windows-side loader at _C:\Users\<username>\.wezterm.lua_ dotfiles it over
_\\wsl.localhost\Ubuntu\..._ and registers it for hot-reload (see the header of that file for the
contract). One-time Windows setup on a fresh machine:

## prerequisites

1. `winget install wez.wezterm`
2. Install **FiraCode Nerd Font** on Windows (`winget install --id ryanoasis.nerd-fonts.firacode`,
   or drop the `.ttf`s and "Install for all users"). Installing it inside WSL does nothing for
   rendering.
3. Generate the Windows-side loader (detects the Windows home and distro automatically, backs up any
   existing `.wezterm.lua` once):

   ```bash
   ./wezterm/install-windows-loader.sh
   ```

   Re-run it after moving the repo or switching distros. Older Windows builds use the `\\wsl$\`
   mount instead of `\\wsl.localhost\`; swap it in the generated loader if WezTerm can't find the
   config.

# TODO

- [ ] `golangci-cli` is installed
- [ ] ensure `sqlc` is installed
- [ ] ensure `goose` is installed
