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
config.window_background_opacity = 0.85
-- Acrylic blur is opt-in: it needs Windows 11 with "Transparency effects" ON
-- (Settings ▸ Personalization ▸ Colors), no Battery Saver, and it can fail to
-- compose under the WebGpu front-end — when it fails it leaves the window fully
-- opaque. Plain opacity above is the reliable baseline. Uncomment to try blur:
-- config.win32_system_backdrop = "Acrylic"

-- ── Behaviour ────────────────────────────────────────────────────────────────
config.scrollback_lines = 10000
config.audible_bell = "Disabled"
config.window_close_confirmation = "NeverPrompt"
-- Refresh the status line (and thus the mode badge + clock) twice a second so
-- entering/leaving a key table reflects promptly.
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

-- ── Seamless nvim ⇄ WezTerm pane navigation (letieu/wezterm-move.nvim) ────────
-- Ctrl+h/j/k/l moves between *both* nvim splits and WezTerm panes. WezTerm checks
-- whether the focused pane is running nvim/vim: if so it forwards the keystroke
-- and the wezterm-move.nvim plugin drives the nvim side (it `wincmd`s between
-- splits and shells out to `wezterm.exe cli activate-pane-direction` once nvim is
-- at its edge); otherwise WezTerm switches panes itself. This is why the old
-- Alt+Arrow pane nav — which shadowed shell/nvim word-motion — is gone. Requires
-- the nvim plugin for the forwarding half; if process detection ever misfires the
-- worst case is a harmless pane switch instead of a split move.
local function is_vim(pane)
	local info = pane:get_foreground_process_info()
	local name = info and info.name
	return name == "nvim" or name == "vim"
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
	-- key, not the period key.)
	{
		key = "phys:Comma",
		mods = "CTRL|SHIFT",
		action = act.PromptInputLine({
			description = "Rename tab:",
			action = wezterm.action_callback(function(window, _, line)
				if line and line ~= "" then
					window:active_tab():set_title(line)
				end
			end),
		}),
	},

	-- Command palette — same as WezTerm's default, but bound explicitly so it can't
	-- depend on default-binding state (and to confirm it's not being shadowed here).
	{ key = "P", mods = "CTRL|SHIFT", action = act.ActivateCommandPalette },

	-- Enter modal key tables via the leader (LEADER then the letter). While a table
	-- is active, bare keys do the mode's actions and Esc/q exit; the status line
	-- shows the mode badge.
	--   LEADER r → resize panes (h/j/k/l or arrows)
	--   LEADER f → font size + opacity
	--   LEADER p → pomodoro control panel (s start/pause, n skip, r reset)
	{ key = "r", mods = "LEADER", action = act.ActivateKeyTable({ name = "resize_pane", one_shot = false }) },
	{ key = "f", mods = "LEADER", action = act.ActivateKeyTable({ name = "font_zoom", one_shot = false }) },
	{ key = "p", mods = "LEADER", action = act.ActivateKeyTable({ name = "pomodoro", one_shot = false }) },

	-- Copy mode (COPY badge) and search (SEARCH badge), tmux-style on the leader:
	-- LEADER [ enters copy mode, LEADER / starts search. The stock Ctrl+Shift+X /
	-- Ctrl+Shift+F chords still work too — these are additive. Inside copy mode the
	-- built-in vim motions (h/j/k/l, v, y) apply.
	{ key = "[", mods = "LEADER", action = act.ActivateCopyMode },
	{ key = "/", mods = "LEADER", action = act.Search("CurrentSelectionOrEmptyString") },
}

-- Append the seamless Ctrl+h/j/k/l navigation keys defined above.
for _, k in ipairs(build_nav_keys()) do
	table.insert(config.keys, k)
end

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
local function mode_label(window)
	-- Show LEADER while the prefix is armed (until the next key or the timeout), so
	-- there's visual confirmation the chord was caught.
	if window:leader_is_active() then
		return "LEADER"
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
	return "NORMAL"
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
	if uri:match("^https?://") then
		wezterm.background_child_process({ "rundll32.exe", "url.dll,FileProtocolHandler", uri })
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
local normal_section = {
	a = { fg = p.crust, bg = p.violet },
	b = { fg = p.violet, bg = p.surface0 },
	c = { fg = p.text, bg = p.mantle },
}
local peach_section = {
	a = { fg = p.crust, bg = p.peach },
	b = { fg = p.peach, bg = p.surface0 },
	c = { fg = p.text, bg = p.mantle },
}

-- Battery component coloured by charge level: red ≤20%, yellow ≤50%, green above
-- (and green while charging). Custom function because the built-in battery
-- component can't recolour per level. Returns FormatItems; empty on desktops.
local function battery_status()
	local info = wezterm.battery_info()
	local b = info and info[1]
	if not b then
		return ""
	end
	local pct = math.floor((b.state_of_charge or 0) * 100 + 0.5)
	local charging = (b.state == "Charging" or b.state == "Full")
	local col = p.green
	if not charging then
		if pct <= 20 then
			col = p.red
		elseif pct <= 50 then
			col = p.yellow
		end
	end
	local glyph
	if charging then
		glyph = wezterm.nerdfonts.md_battery_charging
	else
		local tens = math.floor(pct / 10) * 10
		if tens >= 100 then
			glyph = wezterm.nerdfonts.md_battery
		elseif tens <= 0 then
			glyph = wezterm.nerdfonts.md_battery_alert_variant_outline
		else
			glyph = wezterm.nerdfonts["md_battery_" .. tens]
		end
	end
	glyph = glyph or wezterm.nerdfonts.md_battery or ""
	return wezterm.format({
		{ Foreground = { Color = col } },
		{ Text = glyph .. " " .. pct .. "% " },
	})
end

-- Next Outlook calendar event, read from a cache file refreshed on shell startup
-- (scripts/refresh-next-event.sh → %USERPROFILE%\.cache\wezterm-next-event). Just
-- a file read + countdown — no process spawning in the render path. Reddens as
-- the meeting nears. On a non-Windows host (where the Outlook/WSL pipeline can't
-- run) it shows a muted "cal n/a" reminder so future-me knows to port it; with a
-- host but no event/cache yet it renders nothing.
local function next_event()
	local home = os.getenv("USERPROFILE") -- Windows host home; nil off-Windows
	if not home then
		return wezterm.format({
			{ Foreground = { Color = p.yellow } },
			{ Text = (wezterm.nerdfonts.md_calendar_alert or "") .. " cal n/a" },
		})
	end
	local ok, line = pcall(function()
		local f = io.open(home .. "\\.cache\\wezterm-next-event", "r")
		if not f then
			return nil
		end
		local l = f:read("*l")
		f:close()
		return l
	end)
	if not ok or not line or line == "" then
		return ""
	end
	local epoch, subject = line:match("^(%d+)|(.+)$")
	if not epoch then
		return ""
	end
	local mins = math.floor((tonumber(epoch) - os.time()) / 60)
	if mins < -2 then
		return "" -- already started a while ago; drop it
	end
	local when
	if mins <= 0 then
		when = "now"
	elseif mins < 60 then
		when = mins .. "m"
	else
		when = math.floor(mins / 60) .. "h" .. string.format("%02dm", mins % 60)
	end
	local col = p.subtext0
	if mins <= 5 then
		col = p.red
	elseif mins <= 15 then
		col = p.peach
	end
	return wezterm.format({
		{ Foreground = { Color = col } },
		{
			Text = (" " .. wezterm.nerdfonts.md_calendar_clock or "")
				.. " "
				.. wezterm.truncate_right(subject, 22)
				.. " "
				.. when
				.. " ",
		},
	})
end

-- Count of GitHub PRs awaiting my review, read from a cache refreshed on shell
-- startup (scripts/refresh-gh-prs.sh — works anywhere gh exists). File read only,
-- no spawning at render. Cache states: a number (count), or "auth"/"perm"/"err"
-- → a concise message, or empty/missing → hidden (e.g. gh not installed).
local function gh_prs()
	local win = os.getenv("USERPROFILE")
	local home = win or os.getenv("HOME")
	if not home then
		return ""
	end
	local sep = win and "\\" or "/"
	local ok, val = pcall(function()
		local f = io.open(home .. sep .. ".cache" .. sep .. "wezterm-gh-prs", "r")
		if not f then
			return nil
		end
		local l = f:read("*l")
		f:close()
		return l
	end)
	if not ok or not val or val == "" then
		return "" -- gh missing / no cache yet → hide the section
	end
	local icon = wezterm.nerdfonts.oct_git_pull_request or ""
	if val == "auth" then
		return wezterm.format({ { Foreground = { Color = p.yellow } }, { Text = icon .. " gh: login" } })
	elseif val == "perm" then
		return wezterm.format({ { Foreground = { Color = p.yellow } }, { Text = icon .. " gh: no scope" } })
	elseif val == "err" then
		return wezterm.format({ { Foreground = { Color = p.yellow } }, { Text = icon .. " gh: err" } })
	end
	local n = tonumber(val)
	if not n then
		return ""
	end
	local col = (n > 0) and p.peach or p.subtext0
	return wezterm.format({ { Foreground = { Color = col } }, { Text = icon .. " " .. n } })
end

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

-- Combine pomodoro + battery + next_event into ONE section-X component so tabline
-- doesn't draw a component separator between them (keeps the clock's section
-- separators). Order: pomodoro, battery, PRs, next-event. Empty parts are skipped so
-- there are no stray spaces or separators — an absent part leaves the rest untouched.
local function right_extras(window, pane)
	local parts = {}
	for _, v in ipairs({ pomo_status(), battery_status(window, pane), gh_prs(window, pane), next_event(window, pane) }) do
		if v ~= "" then
			parts[#parts + 1] = v
		end
	end
	return table.concat(parts, " ")
end

tabline.setup({
	options = {
		icons_enabled = true,
		theme = scheme_for(wezterm.gui.get_appearance()),
		tabs_enabled = true,
		-- Slanted tabs using the forward-diagonal pair (upper-left + lower-right),
		-- which matches tabline's separator colouring direction. If this still
		-- renders with notches/gaps, the slant glyphs are a font-rendering issue —
		-- fall back to the reliable full-cell hard arrows:
		--   left = wezterm.nerdfonts.pl_left_hard_divider,
		--   right = wezterm.nerdfonts.pl_right_hard_divider,
		tab_separators = {
			left = wezterm.nerdfonts.ple_upper_left_triangle,
			right = wezterm.nerdfonts.ple_lower_right_triangle,
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
				inactive = { fg = p.subtext0, bg = p.surface0 },
				inactive_hover = { fg = p.text, bg = p.surface1 },
			},
		},
	},
	sections = {
		tabline_a = {
			function(window)
				return "  " .. mode_label(window)
			end,
		},
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
			"index",
			{ "process", padding = { left = 0, right = 1 } },
			{ "output", padding = 0, icon = { wezterm.nerdfonts.md_bell_ring, color = { fg = p.orchid } } },
		},
		-- battery + calendar merged into one component (right_extras) so there's no
		-- separator between them; calendar still sits between battery and the clock.
		-- The clock (Y) keeps its own section separators.
		tabline_x = { right_extras },
		tabline_y = { "datetime" },
		tabline_z = { "domain" },
	},
	extensions = {},
})

tabline.apply_to_config(config)

return config
