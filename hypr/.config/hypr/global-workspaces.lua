-- Global workspaces with no monitor rules, on every monitor setup.
--
-- Omarchy gives each monitor its own workspaces 1-10 (default/hypr/monitor-workspaces.lua).
-- hyprmoncfg only replaces that when a profile has a workspace plan, and my profiles
-- have none. So this does the same handoff hyprmoncfg would, minus the rules:
--   * SUPER + 1..0 always mean workspaces 1..10, whichever monitor has focus.
--   * No workspace is pinned to a monitor: Hyprland creates it on the focused monitor
--     the first time you go to it, and it stays there while it exists.
--   * Switching to a workspace that lives on another monitor focuses that monitor.
--
-- Loaded from ~/.config/hypr/hyprland.lua after Omarchy's defaults and bindings.
if type(o) == "table" and type(o.workspaces) == "table" and type(o.workspaces.reconcile) == "function" and type(o.rebind) == "function" then
  -- Omarchy's monitor events call reconcile through the module table; stop it moving
  -- workspaces into per-monitor blocks.
  o.workspaces.enabled = false
  o.workspaces.reconcile = function() end

  local function action(expression, fn)
    o.bind_expressions[fn] = expression
    return fn
  end

  function o.workspaces.focus(workspace)
    return action("o.workspaces.focus(" .. string.format("%q", tostring(workspace)) .. ")", function()
      hl.dispatch(hl.dsp.focus({ workspace = tostring(workspace) }))
    end)
  end

  function o.workspaces.move_window(workspace, follow)
    return action("o.workspaces.move_window(" .. workspace .. ", " .. tostring(follow ~= false) .. ")", function()
      hl.dispatch(hl.dsp.window.move({ workspace = tostring(workspace), follow = follow ~= false }))
    end)
  end

  function o.workspaces.move_to_monitor(direction)
    return action("o.workspaces.move_to_monitor(" .. string.format("%q", direction) .. ")", function()
      local target = hl.get_monitor(direction)
      if target then
        hl.dispatch(hl.dsp.workspace.move({ monitor = target.name }))
      end
    end)
  end

  for workspace = 1, 10 do
    local key = "code:" .. tostring(workspace + 9)
    o.rebind("SUPER + " .. key, "Switch to workspace " .. workspace, o.workspaces.focus(workspace))
    o.rebind("SUPER + SHIFT + " .. key, "Move window to workspace " .. workspace, o.workspaces.move_window(workspace))
    o.rebind("SUPER + SHIFT + ALT + " .. key, "Move window silently to workspace " .. workspace, o.workspaces.move_window(workspace, false))
  end

  o.rebind("SUPER + TAB", "Next workspace", o.workspaces.focus("e+1"))
  o.rebind("SUPER + SHIFT + TAB", "Previous workspace", o.workspaces.focus("e-1"))
  o.rebind("SUPER + CTRL + TAB", "Former workspace", o.workspaces.focus("previous"))
  o.rebind("SUPER + mouse_down", "Scroll active workspace forward", o.workspaces.focus("e+1"))
  o.rebind("SUPER + mouse_up", "Scroll active workspace backward", o.workspaces.focus("e-1"))

  for key, direction in pairs({ LEFT = "l", RIGHT = "r", UP = "u", DOWN = "d" }) do
    o.rebind("SUPER + SHIFT + ALT + " .. key, "Move workspace to " .. key:lower() .. " monitor", o.workspaces.move_to_monitor(direction))
  end
end
