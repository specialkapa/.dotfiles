-- Telescope picker that lists the git hunks (changed regions) in the focused
-- buffer, mirroring the feel of `<leader>/` but scoped to *changes* instead of
-- every line. Hunks come from gitsigns; selecting one jumps the cursor to it.

local pickers = require 'telescope.pickers'
local finders = require 'telescope.finders'
local conf = require('telescope.config').values
local actions = require 'telescope.actions'
local action_state = require 'telescope.actions.state'
local previewers = require 'telescope.previewers'

local M = {}

-- gitsigns labels hunks by type; map to a short, readable glyph for the list.
local TYPE_GLYPH = {
  add = '+',
  change = '~',
  delete = '_',
}

-- Build a one-line summary for a hunk entry, e.g. "   12 ~  +1 -3".
local function describe(hunk)
  local glyph = TYPE_GLYPH[hunk.type] or '?'
  local added = hunk.added and hunk.added.count or 0
  local removed = hunk.removed and hunk.removed.count or 0
  local start = hunk.added and hunk.added.start or (hunk.removed and hunk.removed.start) or 0
  return string.format('%5d %s  +%d -%d', start, glyph, added, removed)
end

function M.pick()
  local gitsigns = require 'gitsigns'
  local bufnr = vim.api.nvim_get_current_buf()
  local hunks = gitsigns.get_hunks(bufnr)

  if not hunks or vim.tbl_isempty(hunks) then
    vim.notify('No git hunks in this buffer', vim.log.levels.INFO)
    return
  end

  local entries = {}
  for _, hunk in ipairs(hunks) do
    -- Line to jump to: first line of the added range, or the line above a pure
    -- deletion (which has no added lines of its own).
    local lnum = hunk.added and hunk.added.count > 0 and hunk.added.start or math.max(1, (hunk.added and hunk.added.start or 1))
    table.insert(entries, {
      value = hunk,
      ordinal = describe(hunk) .. ' ' .. table.concat(hunk.lines or {}, ' '),
      display = describe(hunk),
      lnum = lnum,
    })
  end

  pickers
    .new({
      sorting_strategy = 'ascending',
      layout_strategy = 'horizontal',
      layout_config = {
        prompt_position = 'top',
        width = 0.5,
        height = 0.4,
        preview_width = 0.80,
      },
    }, {
      prompt_title = 'hunks in buffer',
      finder = finders.new_table {
        results = entries,
        entry_maker = function(entry)
          return {
            value = entry.value,
            ordinal = entry.ordinal,
            display = entry.display,
            lnum = entry.lnum,
          }
        end,
      },
      sorter = conf.generic_sorter {},
      previewer = previewers.new_buffer_previewer {
        title = 'diff preview',
        define_preview = function(self, entry)
          -- gitsigns stores the unified-diff body for each hunk in `hunk.lines`.
          local lines = entry.value.lines or {}
          vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, lines)
          vim.bo[self.state.bufnr].filetype = 'diff'
        end,
      },
      attach_mappings = function(prompt_bufnr)
        actions.select_default:replace(function()
          local entry = action_state.get_selected_entry()
          actions.close(prompt_bufnr)
          if entry and entry.lnum then
            vim.api.nvim_win_set_cursor(0, { entry.lnum, 0 })
            vim.cmd 'normal! zz'
          end
        end)
        return true
      end,
    })
    :find()
end

return M
