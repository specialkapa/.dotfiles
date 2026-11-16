# omarchy plugins

Everything needed to recreate my Omarchy plugins exactly (run by `../setup.sh` on the Omarchy
profile, or on its own: `./install-plugins.sh`, `--dry-run` to preview).

| what | where it is kept | how it gets onto a machine |
| --- | --- | --- |
| My own plugins | their own GitHub repos: [omarchy-media](https://github.com/specialkapa/omarchy-media), [omarchy-notifications](https://github.com/specialkapa/omarchy-notifications), [omarchy-spotify-dl](https://github.com/specialkapa/omarchy-spotify-dl), [omarchy-visualizer](https://github.com/specialkapa/omarchy-visualizer) | `install-plugins.sh` clones them (https; pushes go over ssh) and leaves them on `main` |
| Third-party plugins | [`plugins.lock`](./plugins.lock): id, git URL, pinned commit | `install-plugins.sh` clones them and checks out the pinned commit |
| Superwhisper panel | shipped by the `superwhisper-bin` package | `install-plugins.sh` links it |
| Enabled/disabled state, bar layout, per-widget settings | `~/.config/omarchy/shell.json` (`omarchy` package) | `stow` |
| Plugin config files | `notify-rules.json`, `extensions/commandbar.json` (`omarchy` package); `web-search-here` (`local-bin` package) | `stow` |

`install-plugins.sh` also installs the packages the plugins need and registers the Spotify
Downloader's native messaging host with Brave. It is idempotent: re-running it moves clean
third-party clones to their pinned commit and leaves ones with local changes alone.

## Working on my plugins

Edit them in place in `~/.config/omarchy/plugins/specialkapa.*` (each is a normal git repo),
then commit and push there. Auto-capture (see `omarchy-autocapture` in the main README) records
the new commit in `plugins.lock` and sends a notification when a plugin of mine has uncommitted
or unpushed changes, or when a plugin folder isn't a git repo at all: those are the things a new
machine would not get. Adding, removing or updating any plugin is captured the same way; then
commit the dotfiles.

Not tracked (state or secrets, not configuration): notification mute state/unread counts
(`~/.local/state/omarchy/notifications/`), Remote Desktop credentials
(`~/.config/omarchy-remote-desktop/`, see `../remote-access`), Windows VM credentials
(`~/.config/windows/`), and the Claude Code hooks the Spaces plugin can use (`~/.claude/settings.json`).
