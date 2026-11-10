-- Telescope picker that lists the files touched by the last commit (HEAD),
-- mirroring the feel of `<leader>gs` (git status) but scoped to a single
-- commit. The preview shows that file's slice of the commit diff; selecting a
-- file opens it in the current window.

local pickers = require 'telescope.pickers'
local finders = require 'telescope.finders'
local conf = require('telescope.config').values
local actions = require 'telescope.actions'
local action_state = require 'telescope.actions.state'
local previewers = require 'telescope.previewers'
local utils = require 'telescope.utils'

local M = {}

-- git's --name-status codes; map to a short glyph for the list column.
local STATUS_GLYPH = {
  A = '+', -- added
  M = '~', -- modified
  D = '_', -- deleted
  R = '»', -- renamed
  C = '»', -- copied
  T = '~', -- type changed
}

function M.pick()
  -- Anchor everything to the repo root, NOT vim's cwd. `git show --name-status`
  -- always prints paths relative to the repo root, but git pathspecs (used in
  -- the preview) and `:edit` resolve relative to cwd. If nvim was launched in a
  -- subdir those two disagree and the preview/open break — so resolve the root
  -- once and run every git op (and open every file) against it.
  local root = utils.get_os_command_output({ 'git', 'rev-parse', '--show-toplevel' }, vim.fn.getcwd())[1]
  if not root or root == '' then
    vim.notify('Not a git repository', vim.log.levels.WARN)
    return
  end
  local cwd = root

  -- Short summary of HEAD (hash + subject) for the picker title.
  local subject = utils.get_os_command_output({ 'git', 'log', '-1', '--pretty=%h %s' }, cwd)[1] or ''

  -- `--name-status` gives one "STATUS\tpath" line per file in HEAD.
  local out, ret = utils.get_os_command_output({
    'git',
    'show',
    '--name-status',
    '--pretty=format:',
    'HEAD',
  }, cwd)

  if ret ~= 0 then
    vim.notify('Not a git repository (or no commits yet)', vim.log.levels.WARN)
    return
  end

  local entries = {}
  for _, line in ipairs(out) do
    if line ~= '' then
      -- Renames/copies look like "R100\told\tnew"; take the last field as path.
      local parts = vim.split(line, '\t', { plain = true })
      local status = parts[1]:sub(1, 1)
      local path = parts[#parts]
      table.insert(entries, {
        status = status,
        path = path,
        display = string.format('%s  %s', STATUS_GLYPH[status] or '?', path),
        ordinal = path,
      })
    end
  end

  if vim.tbl_isempty(entries) then
    vim.notify('Last commit touched no files', vim.log.levels.INFO)
    return
  end

  pickers
    .new({
      sorting_strategy = 'ascending',
      layout_strategy = 'horizontal',
      layout_config = {
        prompt_position = 'top',
        width = 0.9,
        height = 0.8,
        preview_width = 0.6,
      },
    }, {
      prompt_title = 'files in last commit — ' .. subject,
      finder = finders.new_table {
        results = entries,
        entry_maker = function(entry)
          return {
            value = entry,
            path = entry.path,
            ordinal = entry.ordinal,
            display = entry.display,
          }
        end,
      },
      sorter = conf.generic_sorter {},
      previewer = previewers.new_buffer_previewer {
        title = 'commit diff',
        define_preview = function(self, entry)
          -- Diff of just this file within HEAD (compared to its parent).
          local diff = utils.get_os_command_output({
            'git',
            'show',
            'HEAD',
            '--',
            entry.value.path,
          }, cwd)
          vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, diff)
          vim.bo[self.state.bufnr].filetype = 'diff'
        end,
      },
      attach_mappings = function(prompt_bufnr)
        actions.select_default:replace(function()
          local entry = action_state.get_selected_entry()
          actions.close(prompt_bufnr)
          -- Deleted files no longer exist on disk; nothing to open. Paths are
          -- repo-root-relative, so open them absolute — otherwise `:edit`
          -- resolves against cwd and misses when nvim runs from a subdir.
          if entry and entry.value.status ~= 'D' then
            vim.cmd('edit ' .. vim.fn.fnameescape(cwd .. '/' .. entry.value.path))
          end
        end)
        return true
      end,
    })
    :find()
end

return M
