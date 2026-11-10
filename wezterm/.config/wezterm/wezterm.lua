-- wezterm.lua — main configuration.
--
-- IMPORTANT: WezTerm is a *Windows* application and does not read this file from
-- here directly. The real entrypoint is a tiny loader at
--   C:\Users\KostasPapazafeiropou\.wezterm.lua
-- which `dofile()`s this file over the \\wsl.localhost\Ubuntu mount and registers
-- it for hot-reload. So this repo stays the single source of truth, and edits
-- here are picked up live. See that loader for details.
--
-- This package is also stow-able (`stow wezterm`) into ~/.config/wezterm so the
-- path exists in a conventional spot, but the Windows loader points at the repo
-- path either way.

local wezterm = require("wezterm")
local mux = wezterm.mux
local act = wezterm.action
local config = wezterm.config_builder()

-- ── Startup: spawn a maximized window on launch ───────────────────────────────
wezterm.on("gui-startup", function()
	local tab, pane, window = mux.spawn_window({})
	window:gui_window():maximize()
end)

-- tabline.wez: lualine-style tab bar + status line. Fetched from git on first
-- run (WezTerm clones it into its plugin dir). Configured near the bottom.
local tabline = wezterm.plugin.require("https://github.com/michaelbrusegard/tabline.wez")

-- ── Shell / startup ─────────────────────────────────────────────────────────
-- Open straight into the WSL distro instead of a Windows shell. The distro name
-- is baked into the Windows loader at generation time (it knows $WSL_DISTRO_NAME)
-- and handed over via wezterm.GLOBAL, so this file stays machine-agnostic.
local wsl_distro = (wezterm.GLOBAL and wezterm.GLOBAL.wsl_distro) or "Ubuntu"
config.default_domain = "WSL:" .. wsl_distro

-- Define the WSL domain explicitly so we can pin its working directory to the
-- Linux home. Without this, new tabs inherit WezTerm.exe's *Windows* cwd and land
-- on /mnt/c/... — `~` is expanded by `wsl.exe --cd`, which WezTerm uses to spawn.
config.wsl_domains = {
	{
		name = "WSL:" .. wsl_distro,
		distribution = wsl_distro,
		default_cwd = "~",
	},
}

-- ── Ad-hoc PowerShell (default stays WSL bash) ───────────────────────────────
-- default_domain above keeps every new tab in WSL. These launch_menu entries let
-- us spawn a Windows shell *on demand* without changing that default. Each entry
-- pins domain = "local" (the Windows-native domain) — without it WezTerm would try
-- to run powershell.exe *inside* the WSL distro (the default domain) and fail.
-- Reach them three ways:
--   • Ctrl+Shift+L         → the launch-menu palette (pick an entry)
--   • the ⌄ new-tab button → dropdown lists these entries
--   • LEADER p s / LEADER p w  (see keybindings below) → spawn directly
-- pwsh.exe is PowerShell 7+ (if installed); powershell.exe is the built-in 5.1.
config.launch_menu = {
	{ label = "PowerShell", args = { "powershell.exe" }, domain = { DomainName = "local" } },
	{ label = "PowerShell 7 (pwsh)", args = { "pwsh.exe" }, domain = { DomainName = "local" } },
	{ label = "Command Prompt", args = { "cmd.exe" }, domain = { DomainName = "local" } },
}

-- ── GPU / rendering ──────────────────────────────────────────────────────────
-- OpenGL (via ANGLE→D3D11 on Windows) instead of WebGpu: WebGpu's swapchain
-- renders opaque on this setup, swallowing window_background_opacity. OpenGL
-- composites transparency reliably and is just as fast for terminal text — the
-- WebGpu edge is imperceptible here. webgpu_power_preference is ignored on OpenGL
-- but kept harmlessly in case we switch back.
config.front_end = "OpenGL"
config.webgpu_power_preference = "HighPerformance"
config.max_fps = 120 -- raise the redraw ceiling so streaming/spinners stay fluid
config.animation_fps = 60

-- ── Font (must be a Nerd Font — nvim relies on glyph icons) ──────────────────
config.font = wezterm.font_with_fallback({
	"FiraCode Nerd Font",
	"Symbols Nerd Font Mono", -- explicit glyph fallback, just in case
})
config.font_size = 11.0
config.harfbuzz_features = { "calt=1", "liga=1", "clig=1" } -- FiraCode ligatures on

-- ── Theme: track the Windows light/dark setting, matching nvim's catppuccin
--    `flavour = 'auto'` (latte in light, mocha in dark). WezTerm re-evaluates the
--    config when the OS appearance changes, so this switches live. ─────────────
local function scheme_for(appearance)
	if appearance:find("Dark") then
		return "Catppuccin Mocha"
	end
	return "Catppuccin Latte"
end
config.color_scheme = scheme_for(wezterm.gui.get_appearance())

-- ── Window chrome ────────────────────────────────────────────────────────────
-- Keep the bar visible even with a single tab so the status line always shows.
config.hide_tab_bar_if_only_one_tab = false
-- Retro tab bar: respects custom per-tab colors + powerline separators (the
-- fancy bar ignores most of the format-tab-title styling). Set back to true for
-- the rounded native look.
config.use_fancy_tab_bar = false
config.tab_max_width = 32
config.window_padding = { left = 6, right = 6, top = 4, bottom = 2 }
config.window_decorations = "RESIZE" -- thin border, native resize, no title bar
config.adjust_window_size_when_changing_font_size = false

-- ── Transparency ─────────────────────────────────────────────────────────────
-- 0.85 = clearly see-through; Acrylic adds the Windows 11 blur behind it so text
-- stays legible. Swap 'Acrylic' for 'Mica'/'Tabbed' to taste, or 'Disabled' for
-- flat transparency. Has no effect on Windows 10 (it'll just be plain opacity).
config.window_background_opacity = 0.86
-- Acrylic blur is opt-in: it needs Windows 11 with "Transparency effects" ON
-- (Settings ▸ Personalization ▸ Colors), no Battery Saver, and it can fail to
-- compose under the WebGpu front-end — when it fails it leaves the window fully
-- opaque. Plain opacity above is the reliable baseline. Uncomment to try blur:
-- config.win32_system_backdrop = "Acrylic"

-- ── Behaviour ────────────────────────────────────────────────────────────────
config.scrollback_lines = 10000
config.audible_bell = "Disabled"
config.window_close_confirmation = "NeverPrompt"
-- Refresh the status line (mode badge + pomodoro countdown) twice a second so
-- entering/leaving a key table and the pomodoro tick reflect promptly.
config.status_update_interval = 500

-- Adjust window opacity live via per-window config overrides. Starts from the
-- base 0.85 set above, steps by `delta`, and clamps to [0.3, 1.0] so the window
-- can't vanish or invert. `delta = nil` resets to the base.
local BASE_OPACITY = 0.85
local function adjust_opacity(delta)
	return wezterm.action_callback(function(window)
		local overrides = window:get_config_overrides() or {}
		if delta == nil then
			overrides.window_background_opacity = nil -- fall back to base
		else
			local current = overrides.window_background_opacity or BASE_OPACITY
			current = current + delta
			current = math.max(0.3, math.min(1.0, current))
			overrides.window_background_opacity = current
		end
		window:set_config_overrides(overrides)
	end)
end

-- ── Pomodoro (25/5) ──────────────────────────────────────────────────────────
-- State lives in wezterm.GLOBAL so it survives this file's hot-reload within a
-- running session. nil = idle; otherwise a table:
--   { phase = "work"|"break", end_time = <epoch when phase ends>, paused = bool,
--     remaining = <secs left at pause>, expired = bool (hit 0, awaiting ack) }
-- GLOBAL nested tables are read-modify-WRITTEN whole (pomo_set), not mutated in
-- place — the reliable pattern for wezterm.GLOBAL. These control functions don't
-- touch the `p` palette, so they can live above it (the key table references them).
local POMO = { work = 25 * 60, brk = 5 * 60 }
local function pomo_get()
	return wezterm.GLOBAL.pomodoro
end
local function pomo_set(t)
	wezterm.GLOBAL.pomodoro = t
end

local function pomo_start(phase)
	pomo_set({
		phase = phase,
		end_time = os.time() + (phase == "work" and POMO.work or POMO.brk),
		paused = false,
		expired = false,
	})
end

-- s: start (idle) / pause / resume / start-next-after-expiry, depending on state.
local function pomo_toggle()
	local s = pomo_get()
	if not s then
		pomo_start("work")
	elseif s.expired then
		pomo_start(s.phase == "work" and "break" or "work")
	elseif s.paused then
		s.end_time = os.time() + (s.remaining or 0)
		s.paused = false
		s.remaining = nil
		pomo_set(s)
	else
		s.remaining = math.max(0, s.end_time - os.time())
		s.paused = true
		pomo_set(s)
	end
end

-- n: jump straight to the other phase, running.
local function pomo_skip()
	local s = pomo_get()
	pomo_start((s and s.phase == "work") and "break" or "work")
end

-- r: back to idle.
local function pomo_reset()
	wezterm.GLOBAL.pomodoro = nil
end

-- Dedicated, pomodoro-only beep — NOT the global audible_bell (which would also
-- change the inactive-tab output-bell glyph behaviour, and can't be fired from a
-- timer event anyway). Shells out to a one-off Windows beep like the open-uri
-- handler does; no-ops off a Windows host.
local function pomo_beep()
	if not os.getenv("USERPROFILE") then
		return
	end
	pcall(function()
		wezterm.background_child_process({
			"powershell.exe",
			"-NoProfile",
			"-Command",
			"[console]::beep(880,250);[console]::beep(660,250)",
		})
	end)
end

-- Detect the phase boundary exactly once and ring. Runs every status_update_interval
-- (500ms) alongside tabline's own update-status handler — WezTerm fires all handlers.
wezterm.on("update-status", function()
	local s = pomo_get()
	if not s or s.paused or s.expired then
		return
	end
	if (s.end_time - os.time()) <= 0 then
		s.expired = true
		pomo_set(s)
		pomo_beep()
	end
end)

-- ── Leader key ───────────────────────────────────────────────────────────────
-- Ctrl+Space is the prefix for WezTerm's own commands. Until it's pressed, every
-- keystroke flows straight through to the shell/nvim, so the modal actions below
-- (LEADER r/f/p) no longer collide with anything running inside the terminal.
-- Heads-up: Ctrl+Space is nvim-cmp's default completion trigger — WezTerm now
-- swallows it, so rebind cmp's mapping in nvim (e.g. to <C-y> / <C-n>) if you use
-- it. The 1s timeout means a slow second keypress just cancels the prefix.
config.leader = { key = "Space", mods = "CTRL", timeout_milliseconds = 1000 }

-- ── Seamless nvim ⇄ WezTerm pane navigation ──────────────────────────────────
-- Ctrl+h/j/k/l moves between *both* nvim splits and WezTerm panes. WezTerm checks
-- whether the focused pane is running nvim: if so it forwards the keystroke and
-- nvim's own <C-h/j/k/l> → :wincmd maps move between splits; otherwise WezTerm
-- switches panes itself. This is why the old Alt+Arrow pane nav — which shadowed
-- shell/nvim word-motion — is gone.
--
-- Detection is via the IS_NVIM pane user variable, which nvim sets over the pty on
-- startup (see the autocmd in nvim's core/keymaps.lua) and clears on exit. We do
-- NOT use get_foreground_process_info(): on WSL that only ever reports `wslhost.exe`,
-- never `nvim`, so process-name detection silently fails and every key falls through
-- to a plain pane switch. The user var rides the pty and is reliable everywhere.
-- Note: crossing from nvim's *outer edge* into an adjacent WezTerm pane isn't handled
-- here (that needs an nvim-side plugin); within nvim and between WezTerm panes works.
local function is_vim(pane)
	return pane:get_user_vars().IS_NVIM == "true"
end

local nav_dirs = { h = "Left", j = "Down", k = "Up", l = "Right" }
local function build_nav_keys()
	local keys = {}
	for key, dir in pairs(nav_dirs) do
		keys[#keys + 1] = {
			key = key,
			mods = "CTRL",
			action = wezterm.action_callback(function(win, pane)
				if is_vim(pane) then
					win:perform_action(act.SendKey({ key = key, mods = "CTRL" }), pane)
				else
					win:perform_action(act.ActivatePaneDirection(dir), pane)
				end
			end),
		}
	end
	return keys
end

-- ── Mode activation + idle auto-clear ────────────────────────────────────────
-- A key table with one_shot=false + timeout_milliseconds auto-pops after 1s of
-- inactivity (the timer resets on each matching key). The pop happens, but WezTerm
-- doesn't reliably repaint the status bar while the window is idle, so the mode
-- badge can linger until you next interact. activate_mode wraps the activation and
-- kicks off poll_mode_badge: a self-terminating timer that, while *any* key table
-- is active, forces a tabline refresh a few times a second (set_status →
-- set_left_status forces a repaint). call_after timers fire independent of the
-- render loop, so the badge clears during idle too. Forward-declared because the
-- closure is built when config.keys is constructed (above mode_label's definition);
-- the upvalues are assigned later, before any keypress can invoke them.
local refresh_sections, poll_mode_badge
local function activate_mode(name)
	return wezterm.action_callback(function(window, pane)
		window:perform_action(
			act.ActivateKeyTable({ name = name, one_shot = false, timeout_milliseconds = 1000 }),
			pane
		)
		poll_mode_badge(window)
	end)
end

-- Rename the active tab inline. Extracted from the Ctrl+Shift+, binding so both it
-- and the LEADER ? cheatsheet (below) can fire the exact same prompt.
local rename_tab_action = act.PromptInputLine({
	description = "Rename tab:",
	action = wezterm.action_callback(function(window, _, line)
		if line and line ~= "" then
			window:active_tab():set_title(line)
		end
	end),
})

-- ── Keybindings (Windows-Terminal-flavoured, layered on the stock defaults) ──
-- Only the bindings below are overridden; everything else keeps WezTerm's
-- defaults (Ctrl+Shift+T new tab, Ctrl+Shift+W close, Ctrl+Shift+Z zoom pane,
-- Ctrl+Shift+C/V copy/paste, Ctrl+Shift+P command palette, etc.).
config.keys = {
	-- Opacity: more opaque / more transparent / reset to base. phys:RightBracket
	-- and phys:LeftBracket dodge the '{'/'}' that Shift produces.
	{ key = "phys:RightBracket", mods = "CTRL|SHIFT", action = adjust_opacity(0.05) },
	{ key = "phys:LeftBracket", mods = "CTRL|SHIFT", action = adjust_opacity(-0.05) },
	{ key = "phys:Backslash", mods = "CTRL|SHIFT", action = adjust_opacity(nil) },

	-- Splits, mirroring Windows Terminal: Alt+Shift+- splits down (stacked),
	-- Alt+Shift+= ("+") splits right (side-by-side). We match the *physical* keys
	-- (phys:Minus / phys:Equal) so Shift turning '-'→'_' and '='→'+' doesn't break
	-- the match.
	{ key = "phys:Minus", mods = "ALT|SHIFT", action = act.SplitVertical({ domain = "CurrentPaneDomain" }) },
	{ key = "phys:Equal", mods = "ALT|SHIFT", action = act.SplitHorizontal({ domain = "CurrentPaneDomain" }) },

	-- Pane navigation lives on Ctrl+h/j/k/l via the seamless nvim integration
	-- (build_nav_keys, appended to this table below). The old Alt+Arrow binds were
	-- removed so Alt+Arrow word-motion works again in the shell and nvim.

	-- Rename the active tab inline (Ctrl+Shift+,). phys:Comma matches the physical
	-- key so Shift turning ',' into '<' doesn't break it. (Note: it's the comma
	-- key, not the period key.) The action lives in rename_tab_action above so the
	-- LEADER ? cheatsheet can reuse it.
	{ key = "phys:Comma", mods = "CTRL|SHIFT", action = rename_tab_action },

	-- Command palette — same as WezTerm's default, but bound explicitly so it can't
	-- depend on default-binding state. Must be phys:P, not "P": with an uppercase
	-- letter WezTerm treats the Shift as baked into the character and drops SHIFT
	-- from the mods, so `key="P", mods="CTRL|SHIFT"` registers as plain Ctrl+P *and*
	-- replaces the working default — leaving the palette unreachable. Same Shift trap
	-- the phys: bindings above avoid. Verify with `wezterm show-keys`.
	{ key = "phys:P", mods = "CTRL|SHIFT", action = act.ActivateCommandPalette },

	-- Enter modal key tables via the leader (LEADER then the letter). While a table
	-- is active, bare keys do the mode's actions and Esc/q exit; the status line
	-- shows the mode badge.
	--   LEADER r → resize panes (h/j/k/l or arrows)
	--   LEADER f → font size + opacity
	--   LEADER p → pomodoro control panel (s start/pause, n skip, r reset)
	-- Each mode auto-pops back to normal after 1s of inactivity (timer resets on each
	-- keypress, so an in-use mode stays put). activate_mode also forces the badge to
	-- clear on idle — see its definition above. Matches the leader timeout, so an
	-- enabled-but-unused mode never lingers.
	{ key = "r", mods = "LEADER", action = activate_mode("resize_pane") },
	{ key = "f", mods = "LEADER", action = activate_mode("font_zoom") },
	{ key = "p", mods = "LEADER", action = activate_mode("pomodoro") },

	-- Copy mode (COPY badge) and search (SEARCH badge), tmux-style on the leader:
	-- LEADER [ enters copy mode, LEADER / starts search. The stock Ctrl+Shift+X /
	-- Ctrl+Shift+F chords still work too — these are additive. Inside copy mode the
	-- built-in vim motions (h/j/k/l, v, y) apply.
	{ key = "[", mods = "LEADER", action = act.ActivateCopyMode },
	{ key = "/", mods = "LEADER", action = act.Search("CurrentSelectionOrEmptyString") },

	-- Ad-hoc Windows shells (default stays WSL bash — see launch_menu above):
	--   LEADER w → new PowerShell tab (pwsh.exe if present, else powershell.exe)
	--   LEADER L → the launch-menu palette (same as Ctrl+Shift+L), to pick cmd/etc.
	{
		key = "w",
		mods = "LEADER",
		action = act.SpawnCommandInNewTab({ args = { "powershell.exe" }, domain = { DomainName = "local" } }),
	},
	{ key = "L", mods = "LEADER", action = act.ShowLauncherArgs({ flags = "LAUNCH_MENU_ITEMS" }) },
}

-- Append the seamless Ctrl+h/j/k/l navigation keys defined above.
for _, k in ipairs(build_nav_keys()) do
	table.insert(config.keys, k)
end

-- ── LEADER ? : keybinding cheatsheet ─────────────────────────────────────────
-- A fuzzy-searchable overlay of our custom bindings — the answer to "what did I map
-- that to again?". Stock defaults are omitted (discover those via Ctrl+Shift+P). It's
-- more than a reminder: selecting an entry *runs* its action, so the sheet doubles as
-- a launcher. Each row pairs a human label with the real action object; InputSelector
-- hands back the chosen id (its 1-based index) and we perform_action that entry's
-- action. Rows with action = nil are pure reference lines — Enter just dismisses.
-- Keep this list in sync when you add/change a binding above.
local cheatsheet = {
	{ keys = "LEADER r", desc = "Resize-pane mode (h/j/k/l or arrows)", action = activate_mode("resize_pane") },
	{ keys = "LEADER f", desc = "Font-size + opacity mode (j/k · -/= · 0 reset · h/l opacity)", action = activate_mode("font_zoom") },
	{ keys = "LEADER p", desc = "Pomodoro mode (s start/pause · n skip · r reset)", action = activate_mode("pomodoro") },
	{ keys = "LEADER [", desc = "Copy mode (vim motions · v select · y yank)", action = act.ActivateCopyMode },
	{ keys = "LEADER /", desc = "Search scrollback", action = act.Search("CurrentSelectionOrEmptyString") },
	{ keys = "LEADER w", desc = "New PowerShell tab", action = act.SpawnCommandInNewTab({ args = { "powershell.exe" }, domain = { DomainName = "local" } }) },
	{ keys = "LEADER L", desc = "Launch menu (pick cmd / pwsh / …)", action = act.ShowLauncherArgs({ flags = "LAUNCH_MENU_ITEMS" }) },
	{ keys = "Alt+Shift+-", desc = "Split pane down (stacked)", action = act.SplitVertical({ domain = "CurrentPaneDomain" }) },
	{ keys = "Alt+Shift+=", desc = "Split pane right (side by side)", action = act.SplitHorizontal({ domain = "CurrentPaneDomain" }) },
	{ keys = "Ctrl+Shift+]", desc = "More opaque", action = adjust_opacity(0.05) },
	{ keys = "Ctrl+Shift+[", desc = "More transparent", action = adjust_opacity(-0.05) },
	{ keys = "Ctrl+Shift+\\", desc = "Reset opacity", action = adjust_opacity(nil) },
	{ keys = "Ctrl+Shift+,", desc = "Rename tab", action = rename_tab_action },
	{ keys = "Ctrl+Shift+P", desc = "Command palette (all commands)", action = act.ActivateCommandPalette },
	{ keys = "Ctrl+Shift+T", desc = "New tab", action = act.SpawnTab("CurrentPaneDomain") },
	{ keys = "Ctrl+Shift+W", desc = "Close tab", action = act.CloseCurrentTab({ confirm = true }) },
	{ keys = "Ctrl+Shift+Z", desc = "Zoom / unzoom pane", action = act.TogglePaneZoomState },
	{ keys = "Ctrl+h/j/k/l", desc = "Move between panes / nvim splits (reference)", action = nil },
	{ keys = "Ctrl+Space", desc = "Leader prefix — press, then a LEADER key above (reference)", action = nil },
}

local function open_cheatsheet()
	local choices = {}
	for i, e in ipairs(cheatsheet) do
		choices[i] = { id = tostring(i), label = string.format("%-14s  %s", e.keys, e.desc) }
	end
	return act.InputSelector({
		title = "Keybindings — type to filter · Enter to run",
		fuzzy = true,
		choices = choices,
		action = wezterm.action_callback(function(window, pane, id, _label)
			if not id then
				return -- cancelled (Esc)
			end
			local entry = cheatsheet[tonumber(id)]
			if entry and entry.action then
				window:perform_action(entry.action, pane)
			end
		end),
	})
end

-- Bind the cheatsheet on LEADER ?. '?' is Shift+/, and Windows/WezTerm is
-- inconsistent about whether the SHIFT is reported alongside the resolved '?'
-- character — so register BOTH mod combos, plus the physical-key form, to be safe.
-- (Building the selector once and reusing it keeps all three in sync.)
local cheatsheet_action = open_cheatsheet()
table.insert(config.keys, { key = "?", mods = "LEADER", action = cheatsheet_action })
table.insert(config.keys, { key = "?", mods = "LEADER|SHIFT", action = cheatsheet_action })
table.insert(config.keys, { key = "phys:Slash", mods = "LEADER|SHIFT", action = cheatsheet_action })

-- ── Modal key tables ─────────────────────────────────────────────────────────
-- Each is entered by a chord above and stays active (one_shot=false) until you
-- Esc/q out. The active table name drives the status mode badge below. Keys not
-- listed fall through to the terminal, so Esc out before typing normally.
config.key_tables = {
	-- Resize the focused pane with h/j/k/l or arrows; repeats while active.
	resize_pane = {
		{ key = "h", action = act.AdjustPaneSize({ "Left", 2 }) },
		{ key = "j", action = act.AdjustPaneSize({ "Down", 2 }) },
		{ key = "k", action = act.AdjustPaneSize({ "Up", 2 }) },
		{ key = "l", action = act.AdjustPaneSize({ "Right", 2 }) },
		{ key = "LeftArrow", action = act.AdjustPaneSize({ "Left", 2 }) },
		{ key = "DownArrow", action = act.AdjustPaneSize({ "Down", 2 }) },
		{ key = "UpArrow", action = act.AdjustPaneSize({ "Up", 2 }) },
		{ key = "RightArrow", action = act.AdjustPaneSize({ "Right", 2 }) },
		{ key = "Escape", action = "PopKeyTable" },
		{ key = "q", action = "PopKeyTable" },
		{ key = "Enter", action = "PopKeyTable" },
	},
	-- Font size (j/k or -/=, 0 resets) and opacity (h/l or [/], \\ resets).
	font_zoom = {
		{ key = "k", action = act.IncreaseFontSize },
		{ key = "j", action = act.DecreaseFontSize },
		{ key = "=", action = act.IncreaseFontSize },
		{ key = "+", action = act.IncreaseFontSize },
		{ key = "-", action = act.DecreaseFontSize },
		{ key = "0", action = act.ResetFontSize },
		{ key = "l", action = adjust_opacity(0.05) },
		{ key = "h", action = adjust_opacity(-0.05) },
		{ key = "\\", action = adjust_opacity(nil) },
		{ key = "Escape", action = "PopKeyTable" },
		{ key = "q", action = "PopKeyTable" },
	},
	-- Pomodoro: s start/pause, n skip to next phase, r reset. The timer state is in
	-- wezterm.GLOBAL, independent of this table, so it keeps running after you Esc out.
	pomodoro = {
		{ key = "s", action = wezterm.action_callback(pomo_toggle) },
		{ key = "n", action = wezterm.action_callback(pomo_skip) },
		{ key = "r", action = wezterm.action_callback(pomo_reset) },
		{ key = "Escape", action = "PopKeyTable" },
		{ key = "q", action = "PopKeyTable" },
	},
}

-- ── Tabline: lualine-style tab bar + status line (tabline.wez plugin) ────────
-- The plugin registers its own update-status + format-tab-title, so we no longer
-- hand-roll those. Theme tracks the same OS light/dark switch as color_scheme by
-- reusing scheme_for(). apply_to_config() (below) wires it into config.

-- Mode component: friendly labels for our key tables + the WezTerm built-ins,
-- so section A reads RESIZE/FONT/COPY/SEARCH instead of the raw table name.
-- Returns nil in plain normal mode — the update-status handler reads that as "hide
-- section A entirely" (a "" string would leave a stray coloured stub + separator,
-- the same tabline length-gating gotcha as the workspace section).
local leader_prefix = utf8.char(0x1f30a) -- 🌊 shown while the leader prefix is armed
local function mode_label(window)
	-- Leader armed (until the next key or the timeout): just the wave glyph, so
	-- there's visual confirmation the chord was caught.
	if window:leader_is_active() then
		return leader_prefix
	end
	local m = window:active_key_table()
	if m == "resize_pane" then
		return "RESIZE"
	elseif m == "font_zoom" then
		return "FONT"
	elseif m == "copy_mode" then
		return "COPY"
	elseif m == "search_mode" then
		return "SEARCH"
	elseif m == "pomodoro" then
		return "POMO"
	end
	return nil -- normal mode: section A hidden entirely
end

-- ── Mouse: Ctrl+click to open links (Windows-Terminal muscle memory) ─────────
-- WezTerm's default opens links on a *plain* click; this adds Ctrl+click on top
-- (defaults are kept, so plain-click still works too). The Ctrl+Down → Nop stops
-- a selection from starting on the press so the click registers cleanly.
config.mouse_bindings = {
	{
		event = { Up = { streak = 1, button = "Left" } },
		mods = "CTRL",
		action = act.OpenLinkAtMouseCursor,
	},
	{
		event = { Down = { streak = 1, button = "Left" } },
		mods = "CTRL",
		action = act.Nop,
	},
}

-- Open http(s) links ourselves. WezTerm's built-in opener fails from a WSL pane:
-- with OSC 7 on, the pane's cwd is a \\wsl.localhost\... UNC path, which the OS
-- open call rejects as a working directory, so links silently don't open. We hand
-- the URL to Windows' FileProtocolHandler via rundll32 (cwd-independent), and
-- return false to suppress the broken default. Other schemes use the default.
wezterm.on("open-uri", function(_, _, uri)
	-- DIAGNOSTIC (temporary): record every invocation + spawn result so we can tell
	-- whether the event even fires and whether the spawn raised. Writes to the same
	-- Windows cache dir the other features use. Remove once links are confirmed working.
	local function dbg(msg)
		pcall(function()
			local home = os.getenv("USERPROFILE")
			if not home then
				return
			end
			local f = io.open(home .. "\\.cache\\wezterm-openuri.log", "a")
			if f then
				f:write(os.date("%H:%M:%S") .. " " .. msg .. "\n")
				f:close()
			end
		end)
	end
	dbg("open-uri fired: " .. tostring(uri))
	if uri:match("^https?://") then
		local ok, err = pcall(wezterm.background_child_process, { "explorer.exe", uri })
		dbg("explorer spawn ok=" .. tostring(ok) .. " err=" .. tostring(err))
		return false
	end
end)

-- Compact Catppuccin palette, adaptive to the OS light/dark setting, used to
-- rebuild the pre-tabline look via theme_overrides below.
local catppuccin = {
	mocha = {
		crust = "#11111b",
		mantle = "#181825",
		surface0 = "#313244",
		surface1 = "#45475a",
		subtext0 = "#a6adc8",
		text = "#cdd6f4",
		mauve = "#c4a5fb",
		peach = "#fab387",
		violet = "#a78bfa",
		orchid = "#ddbcff",
		red = "#f38ba8",
		yellow = "#f9e2af",
		green = "#a6e3a1",
	},
	latte = {
		crust = "#dce0e8",
		mantle = "#e6e9ef",
		surface0 = "#ccd0da",
		surface1 = "#bcc0cc",
		subtext0 = "#6c6f85",
		text = "#4c4f69",
		mauve = "#8839ef",
		peach = "#fe640b",
		violet = "#6c43d9",
		orchid = "#9d4edd",
		red = "#d20f39",
		yellow = "#df8e1d",
		green = "#40a02b",
	},
}
local p = wezterm.gui.get_appearance():find("Dark") and catppuccin.mocha or catppuccin.latte

-- Purple-family scheme: violet NORMAL badge + workspace, deeper purple active
-- tab (mauve), muted surface inactive, surface1 hover, mantle bar, peach accent
-- for active modes. violet/orchid are deeper-purple shades for variety.
--
-- The `z` key colours the right-side pomodoro section. tabline defaults section Z
-- to the `a` (badge) colour — a filled violet/peach block. We pin z to the same
-- colours as `c` (the mantle bar background) so the pomodoro text sits flush on
-- the bar with NO highlight block, and its left slant separator (fg = z.bg,
-- bg = c.bg) becomes mantle-on-mantle → invisible. pomo_status sets its own
-- per-state foreground, so z.fg here is just the fallback.
local normal_section = {
	a = { fg = p.crust, bg = p.violet },
	b = { fg = p.violet, bg = p.surface0 },
	c = { fg = p.text, bg = p.mantle },
	z = { fg = p.text, bg = p.mantle },
}
local peach_section = {
	a = { fg = p.crust, bg = p.peach },
	b = { fg = p.peach, bg = p.surface0 },
	c = { fg = p.text, bg = p.mantle },
	z = { fg = p.text, bg = p.mantle },
}

-- Pomodoro countdown, read from wezterm.GLOBAL (set by the control functions and the
-- update-status boundary handler above). Empty when idle. Colours: work text → peach in
-- the last minute, break green, paused muted, and a red/yellow flash once expired (until
-- you start the next phase). Glyph: timer for work, coffee for break.
local function pomo_status()
	local s = pomo_get()
	if not s then
		return ""
	end
	local secs
	if s.paused then
		secs = s.remaining or 0
	elseif s.expired then
		secs = 0
	else
		secs = math.max(0, s.end_time - os.time())
	end
	local glyph = (s.phase == "work") and wezterm.nerdfonts.md_timer or wezterm.nerdfonts.md_coffee
	local col
	if s.expired then
		col = (os.time() % 2 == 0) and p.red or p.yellow -- flash until acknowledged
	elseif s.paused then
		col = p.subtext0
	elseif s.phase == "work" then
		col = (secs <= 60) and p.peach or p.text -- warm up in the final minute
	else
		col = p.green
	end
	local pause = s.paused and (" " .. (wezterm.nerdfonts.md_pause or "")) or ""
	return wezterm.format({
		{ Foreground = { Color = col } },
		{ Text = string.format("%s %02d:%02d%s", glyph or "", math.floor(secs / 60), secs % 60, pause) },
	})
end

-- Show the workspace section (tabline_b) only when more than one workspace exists;
-- otherwise hide it entirely (the default lone "default" workspace is just noise).
-- tabline re-reads config.sections every render, so flipping this table live
-- adds/removes the whole section — background block AND separators — with no
-- artifacts. NOTE: windows and separate WezTerm instances are NOT workspaces, so
-- this only lights up once you create a *named* workspace. Registered before
-- tabline.setup so it runs before tabline's own render handler each cycle (no
-- one-frame lag). Returning "" from a function component would NOT work here:
-- tabline gates sections on array length, so an empty-string component still draws
-- a stray coloured stub + separator.
-- NOTE: require only tabline.config here, NOT tabline.component — component.lua
-- reads config.opts at load time, which tabline.setup() hasn't populated yet, so
-- requiring it now crashes. The poll uses the plugin's public tabline.refresh()
-- (which loads the component lazily, after setup) instead.
local tabline_config = require("tabline.config")

-- Recompute the dynamic sections (A = mode, B = workspace) from current state.
-- Used by both the periodic update-status event and poll_mode_badge's timer.
refresh_sections = function(window)
	if not tabline_config.sections then
		return -- setup hasn't populated sections yet
	end
	-- Section B (workspace): only with 2+ workspaces (see comment above).
	local multi = #wezterm.mux.get_workspace_names() > 1
	tabline_config.sections.tabline_b = multi and { "workspace" } or {}
	-- Section A (mode): hidden entirely in plain normal mode; shows the 🌊 leader
	-- glyph while the prefix is armed, or the key-table label (RESIZE/FONT/…) when a
	-- mode is active. mode_label returns nil in normal mode → empty section (NOTE:
	-- must stay nil-safe — `nil .. " "` would throw and abort the handler, leaving a
	-- stale badge). The Text element inherits section A's attributes (tabline colours
	-- them by the real mode: violet normal, peach in a key table).
	local m = mode_label(window)
	tabline_config.sections.tabline_a = m and { { Text = " " .. m .. " " } } or {}
	-- Section Z (pomodoro): the ONLY right-side component now. Gate it like A/B —
	-- present only while a pomodoro is running, else hidden entirely. A static
	-- { pomo_status } would leave a stray coloured stub + separator on the right
	-- edge when idle (pomo_status returns ""), the same length-gating gotcha.
	tabline_config.sections.tabline_z = pomo_get() and { pomo_status } or {}
end

-- While any key table is active, force a tabline refresh a few times a second so the
-- mode badge clears promptly once the table auto-pops — even if WezTerm isn't
-- repainting an otherwise-idle window. Self-terminating; guarded so only one loop
-- runs per window. call_after timers fire independent of the render loop.
local mode_poll = {} -- [window-id] = true while a poll loop is running for it
poll_mode_badge = function(window)
	local id = window:window_id()
	if mode_poll[id] then
		return
	end
	mode_poll[id] = true
	local function tick()
		local ok, active = pcall(function()
			refresh_sections(window)
			tabline.refresh(window) -- forces set_status → set_left_status → repaint
			return window:active_key_table() ~= nil
		end)
		if ok and active then
			wezterm.time.call_after(0.25, tick)
		else
			mode_poll[id] = nil -- table popped (or window gone): stop polling
		end
	end
	wezterm.time.call_after(0.25, tick)
end

wezterm.on("update-status", function(window)
	refresh_sections(window)
end)

tabline.setup({
	options = {
		icons_enabled = true,
		theme = scheme_for(wezterm.gui.get_appearance()),
		tabs_enabled = true,
		-- No slanted separators: tabs are plain rectangular blocks. The active tab is
		-- a solid mauve block, inactive tabs a muted surface0 block (see theme_overrides
		-- below), sitting directly adjacent with no diagonal glyph between them — the
		-- colour change alone delineates them. Empty strings disable tabline's
		-- separator glyph entirely.
		tab_separators = {
			left = "",
			right = "",
		},
		-- Likewise no slant on the section separators (mode/workspace badge, pomodoro
		-- block): plain block edges, no diagonal glyph.
		section_separators = {
			left = "",
			right = "",
		},
		theme_overrides = {
			normal_mode = normal_section,
			-- Active modes glow peach, like the old mode badge.
			copy_mode = peach_section,
			search_mode = peach_section,
			resize_pane_mode = peach_section,
			font_zoom_mode = peach_section,
			pomodoro_mode = peach_section,
			tab = {
				active = { fg = p.crust, bg = p.mauve },
				-- Inactive tabs are a muted filled block (surface0), distinct from
				-- both the mantle bar and the mauve active tab — the bufferline
				-- 'slant' look. Hover lifts them a touch (surface1).
				inactive = { fg = p.subtext0, bg = p.surface0 },
				inactive_hover = { fg = p.text, bg = p.surface1 },
			},
		},
	},
	sections = {
		-- Sections A (mode) and B (workspace) are governed live by the update-status
		-- handler above (hidden in normal mode / single workspace). These are just the
		-- initial values before the first render tick.
		tabline_a = {},
		tabline_b = { "workspace" },
		tabline_c = { " " },
		tab_active = {
			"index",
			{ "parent", padding = 0 },
			"/",
			{ "cwd", padding = { left = 0, right = 1 } },
			{ "zoomed", padding = 0 },
		},
		tab_inactive = {
			-- Mirror tab_active so an inactive tab keeps the same directory label
			-- instead of the `process` name — which on WSL is always the useless
			-- "wsl"/wslhost, and which also stamps a leading app icon on the tab.
			-- index + parent/cwd carry no icon-bearing components, so inactive tabs
			-- read exactly like the active one, with no leading glyph.
			"index",
			{ "parent", padding = 0 },
			"/",
			{ "cwd", padding = { left = 0, right = 1 } },
		},
		-- Right side stripped down to just the pomodoro countdown (the clock,
		-- domain, and PR counter were removed). tabline_z holds it, flush to the
		-- right edge, but is governed live by refresh_sections above: present only
		-- while a pomodoro runs, {} (hidden) when idle. These are just the initial
		-- values before the first render tick — idle at startup, so all empty.
		tabline_x = {},
		tabline_y = {},
		tabline_z = {},
	},
	extensions = {},
})

tabline.apply_to_config(config)

return config
