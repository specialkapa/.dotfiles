-- Small UI helpers shared across plugins (floating-window styling, highlights).
local M = {}

-- ─── Border style ──────────────────────────────────────────────────────────
-- Single source of truth for every float / hand-drawn box in the config. Flip
-- `STYLE` and everything restyles at once. Only the four corners differ between
-- styles; the straight edges (─ │) and T-junctions (├ ┤) are identical, so
-- hand-drawn boxes only ever need their corners from here.
local STYLE = 'single' -- 'rounded' | 'single' | 'double'

local CORNERS = {
  rounded = { tl = '╭', tr = '╮', bl = '╰', br = '╯', h = '─', v = '│' },
  single = { tl = '┌', tr = '┐', bl = '└', br = '┘', h = '─', v = '│' },
  double = { tl = '╔', tr = '╗', bl = '╚', br = '╝', h = '═', v = '║' },
}

-- Native border name for any `border = ...` plugin option or `nvim_open_win`.
M.border = STYLE

-- Corner/edge glyphs for hand-drawn boxes (virt_lines, ASCII art, …).
M.corners = CORNERS[STYLE] or CORNERS.rounded

-- 8-element border char list in Neovim's order:
-- { topleft, top, topright, right, botright, bottom, botleft, left }
local c = M.corners
M.BORDER = { c.tl, c.h, c.tr, c.v, c.br, c.h, c.bl, c.v }

-- Telescope uses its own key (`borderchars`) with a different order:
-- { top, right, bottom, left, topleft, topright, botright, botleft }
M.telescope_borderchars = { c.h, c.v, c.h, c.v, c.tl, c.tr, c.br, c.bl }

-- Same as BORDER but every glyph carries highlight group `hl` (e.g. cmp windows).
function M.border_hl(hl)
  local spec = {}
  for _, ch in ipairs(M.BORDER) do
    spec[#spec + 1] = { ch, hl }
  end
  return spec
end

-- Define a highlight group only if it doesn't already exist, so we never clobber a
-- group the colorscheme has set.
function M.ensure_hl(name, opts)
  if vim.fn.hlexists(name) == 0 then
    vim.api.nvim_set_hl(0, name, opts)
  end
end

-- Link `name` to the first of `candidates` that exists, so our colors track the active
-- colorscheme's semantic groups instead of hardcoded hex. Returns true on success.
function M.link_first(name, candidates)
  for _, group in ipairs(candidates) do
    if vim.fn.hlexists(group) == 1 then
      vim.api.nvim_set_hl(0, name, { link = group })
      return true
    end
  end
  return false
end

-- Resolved foreground color (24-bit number) of a highlight group, following links.
-- nil when unset. Used to derive accent colors from the theme.
function M.hl_fg(group)
  local ok, h = pcall(vim.api.nvim_get_hl, 0, { name = group, link = false })
  return (ok and h) and h.fg or nil
end

-- Resolved background color of a highlight group (24-bit number), or nil.
function M.hl_bg(group)
  local ok, h = pcall(vim.api.nvim_get_hl, 0, { name = group, link = false })
  return (ok and h) and h.bg or nil
end

return M
