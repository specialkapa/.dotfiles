-- Small UI helpers shared across plugins (floating-window styling, highlights).
local M = {}

-- Rounded floating-window border used across the git / PR-review floats.
M.BORDER = { '╭', '─', '╮', '│', '╯', '─', '╰', '│' }

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
