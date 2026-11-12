# dotfiles

This is where I maintain my dotfiles. The approach I am using this blog post
https://www.jakewiesler.com/blog/managing-dotfiles which leverages the `stow` package.

> [!NOTE] 
> [$HOME](../..) should be the target directory.

> [!NOTE] 
> [$HOME/.dotfiles](..) is the `stow` directory.

# instructions

The same `main` branch is used on every machine. `setup.sh` detects which one it is running on and
handles the differences:

| profile   | machine                                 | detected by                      |
| --------- | --------------------------------------- | -------------------------------- |
| `wsl`     | work laptop: Windows + WSL2 Ubuntu      | `microsoft`/`wsl` in `/proc/version` |
| `omarchy` | personal laptop: Omarchy (Arch)         | `~/.local/share/omarchy` exists  |
| `linux`   | anything else                           | fallback                         |

> [!IMPORTANT]
> On a TNP laptop you might have to do other things first, e.g. run `atlasformer`. Not needed on
> personal machines.

1. clone this repository into `$HOME/.dotfiles`.
2. run:

   ```bash
   cd $HOME/.dotfiles
   ./setup.sh            # or: ./setup.sh --dry-run to preview
   ```

   It will:
   - confirm the detected profile (override with `--profile wsl|omarchy|linux`),
   - install `stow` (and FiraCode Nerd Font on native Linux) if missing,
   - ask for the git name/email for this machine and write them to `~/.gitconfig.local` (not
     committed; included from [`.gitconfig`](./git/.gitconfig)),
   - move anything in `$HOME` that would block a link to `~/.dotfiles-backup/<timestamp>/`,
   - `stow` every package,
   - run the profile-specific steps (WSL: generate the Windows `wezterm` loader; Omarchy/Linux: point
     `btop` at the catppuccin theme instead of Omarchy's).
3. install the `neovim` dependencies. Refer to [README](./nvim/.config/nvim/README.md) for details.

## Omarchy notes

- `btop`, `fastfetch`, `nvim` and `wezterm` use the configs/themes from this repo, regardless of the
  Omarchy theme. Omarchy's theme switcher only *reloads* `btop`, so it won't undo this.
- `omarchy-refresh-fastfetch` (and a few Omarchy migrations) copy Omarchy's default over
  `~/.config/fastfetch/config.jsonc`. Because that file is a link, the copy lands in this repo — if
  `git status` shows it changed, `git checkout` it.

# prompt (`starship`)

All machines use [`starship`](https://starship.rs) with [`starship.toml`](./starship/.config/starship.toml),
a port of the old `oh-my-posh` "minimal" theme (same layout and colours). `setup.sh` installs `starship`
if missing and, except on Omarchy (which already does it), adds `eval "$(starship init bash)"` to
`~/.bashrc`, commenting out any old `oh-my-posh init` line (backup: `~/.bashrc.pre-starship`).

The icon on the left comes from `starship`'s `os` module: Ubuntu on WSL, and the Hyprland logo on Arch.
Omarchy's own logo isn't usable: it sits at U+E900 in the `omarchy` font, a codepoint Nerd Fonts also
use, and `wezterm` can't route a single codepoint to a specific font.

# `wezterm` (Windows + WSL)

On native Linux `wezterm` reads `~/.config/wezterm/wezterm.lua` directly (linked by `setup.sh`);
nothing else to do. The Windows-only bits are gated on `is_windows` in that file.

`wezterm` runs as a **Windows** app, so it does not read its config from WSL the normal way. The real
config is version-controlled here at [`wezterm.lua`](./wezterm/.config/wezterm/wezterm.lua), and a
small Windows-side loader at `C:\Users\<username>\.wezterm.lua` dotfiles it over
`\\wsl.localhost\Ubuntu\...` and registers it for hot-reload (see the header of that file for the
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
   mount instead of `\\wsl.localhost\`; swap it in the generated loader if `wezterm` can't find the
   config.

# TODO

- [ ] `golangci-cli` is installed
- [ ] ensure `sqlc` is installed
- [ ] ensure `goose` is installed
