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
   - `stow` every package (plus `omarchy` on the Omarchy profile only),
   - run the profile-specific steps (WSL: generate the Windows `wezterm` loader; Omarchy/Linux: point
     `btop` at the catppuccin theme instead of Omarchy's).
3. install the `neovim` dependencies. Refer to [README](./nvim/.config/nvim/README.md) for details.

## Omarchy notes

- `btop`, `fastfetch`, `nvim` and `wezterm` use the configs/themes from this repo, regardless of the
  Omarchy theme. Omarchy's theme switcher only *reloads* `btop`, so it won't undo this.
- `omarchy-refresh-fastfetch` (and a few Omarchy migrations) copy Omarchy's default over
  `~/.config/fastfetch/config.jsonc`. Because that file is a link, the copy lands in this repo — if
  `git status` shows it changed, `git checkout` it.
- The `omarchy` package (bar layout, dock, idle timers and plugin settings in
  `~/.config/omarchy/shell.json`, plus `shell.toml`, `notify-rules.json`, the command bar's
  `extensions/commandbar.json`, `defaults/agent` and `themed/` templates) is only linked on the
  Omarchy profile. Changes made from the bar UI usually write through the link into this repo, but
  Omarchy migrations, `omarchy plugin enable/disable` and some UI saves replace the link with a plain
  file. The `omarchy-autocapture` package (systemd user units, enabled by `setup.sh`) handles that
  automatically: `dotfiles-capture.path` watches `~/.config/omarchy`, its plugins folder and the
  hyprmoncfg profiles, and `dotfiles-capture.timer` runs every 30 min. Both run
  [`capture-omarchy.sh --auto`](./capture-omarchy.sh), which moves the newer plain file into the
  repo and re-links it, and sends a desktop notification listing what it captured. It never
  commits: review `git status` and commit yourself. Run `./capture-omarchy.sh` by hand any time;
  logs: `journalctl --user -u dotfiles-capture`.
- Plugins: see [`omarchy-plugins/`](./omarchy-plugins/README.md). Every plugin is a git clone listed
  in `plugins.lock` (mine live in their own repos: `specialkapa/omarchy-{media,notifications,
  spotify-dl,visualizer}`) and `setup.sh` clones them into place. Auto-capture keeps the lock
  current and warns when a plugin isn't in git or one of mine has unpushed changes.
- `local-bin` (Omarchy-only) holds `~/.local/bin/web-search-here`, used by the command bar, and
  `~/.local/bin/send-to-agent`, which pastes `@file` mentions into a live session of the Omarchy
  default AI agent (tmux, WezTerm, Kitty or any terminal with its own window).
- `nautilus` (Omarchy-only) adds **Send to <agent>** to the Files right-click menu
  (`nautilus-python` extension) and the **Ctrl+Alt+C** shortcut (a Nautilus script plus
  `~/.config/nautilus/scripts-accels`). Omarchy's own extensions (LocalSend, transcode) stay
  unmanaged. Run `nautilus -q` after changing them.
- `yazi` (Omarchy-only) is the yazi file manager config. `theme.toml` links to the copy Omarchy
  renders from `omarchy/.config/omarchy/themed/yazi-theme.toml.tpl` on every `omarchy theme set`,
  so yazi follows the current theme (the link is relative, so the repo must live at
  `~/.dotfiles`). Extra keys under `c`: `c i` copy image, `c t` copy file contents, `c a` send to
  the agent (as does **Ctrl+Alt+C**, like Nautilus), `c z` zip with a name prompt (the `mkzip`
  plugin). `.ica` files open in Citrix Workspace.
- `mpd` and `rmpc` (Omarchy-only) hold the music stack used by the Spotify Downloader and the bar
  visualizer: `mpd.conf` (library `~/Music/Spotify`, PipeWire output plus a `/tmp/mpd.fifo` feed for
  rmpc's visualizer), a `mpd-mpris` drop-in that restarts it with MPD, and rmpc's `config.ron`.
  `setup.sh` creates MPD's directories and enables `mpd` and `mpd-mpris`. The database, state and
  playlists (`~/.local/share/mpd`, `~/.local/state/mpd`) are not tracked; rmpc reads its config
  only at launch.
- Remote access (SSH + Remote Desktop from my iPhone over Tailscale, firewall-locked to it): see
  [`remote-access/`](./remote-access/README.md). `setup.sh` asks before running it.
- The `hyprmoncfg` package (also Omarchy-only) holds my monitor profiles: `laptop` (panel only),
  `desk-mirror` (the panel mirrors the Dell U2722DE), `desk-dual` (U2722DE + SE2416H, panel
  off) and `laptop-portable` (the SHD S1 portable monitor, 1080p at scale 1.5, to the right of the
  panel, which stays at 0,0 as primary). None of them has a workspace plan (`"workspaces": {"enabled": false}`), so no workspace is
  pinned to a monitor. Run `hyprmoncfg manage` once on a new machine so the daemon switches
  profiles automatically. Profiles saved from the TUI (new ones, or ones that replace their link
  with a plain file) are captured into this repo automatically; save new ones with planning off.
- The `hypr` package (Omarchy-only) links `~/.config/hypr/global-workspaces.lua`, which replaces
  Omarchy's per-monitor workspaces 1–10 with global ones: `SUPER + 1…0` always mean workspaces
  1–10, and a workspace opens on the focused monitor and stays there while it exists. `setup.sh`
  adds the line that loads it to Omarchy's `~/.config/hypr/hyprland.lua`.

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
