local M = {}

local utils = require('telescope.utils')
local make_entry = require('telescope.make_entry')
local strings = require('plenary.strings')
local devicons = require('nvim-web-devicons')
local entry_display = require('telescope.pickers.entry_display')

local filetype_icon_width = strings.strdisplaywidth(devicons.get_icon('fname', { default = true }))

local function get_path_and_tail(filename)
  if not filename or filename == '' then
    return '', ''
  end

  local tail = utils.path_tail(filename)
  local path_without_tail = strings.truncate(filename, #filename - #tail, '')
  local path_to_display = utils.transform_path({ path_display = { 'truncate' } }, path_without_tail)

  return tail, path_to_display
end

function M.pretty_files_picker(picker_and_options)
  if type(picker_and_options) ~= 'table' or picker_and_options.picker == nil then
    vim.notify("Expected { picker = 'find_files', options = { ... } }", vim.log.levels.WARN)
    return
  end

  local opts = picker_and_options.options or {}
  local original_entry_maker = make_entry.gen_from_file(opts)

  opts.entry_maker = function(line)
    local entry = original_entry_maker(line)

    local displayer = entry_display.create {
      separator = ' ',
      items = {
        { width = filetype_icon_width },
        { width = nil },
        { remaining = true },
      },
    }

    entry.display = function(e)
      local tail, path_to_display = get_path_and_tail(e.value)
      local icon, icon_highlight = utils.get_devicons(tail)

      return displayer {
        { icon, icon_highlight },
        tail .. ' ',
        { path_to_display, 'TelescopeResultsComment' },
      }
    end

    return entry
  end

  if picker_and_options.picker == 'find_files' then
    require('telescope.builtin').find_files(opts)
  elseif picker_and_options.picker == 'git_files' then
    require('telescope.builtin').git_files(opts)
  elseif picker_and_options.picker == 'oldfiles' then
    require('telescope.builtin').oldfiles(opts)
  elseif picker_and_options.picker == '' then
    vim.notify('Picker was not specified', vim.log.levels.WARN)
  else
    vim.notify('Unsupported picker for pretty_files_picker: ' .. picker_and_options.picker, vim.log.levels.WARN)
  end
end

function M.pretty_grep_picker(picker_and_options)
  if type(picker_and_options) ~= 'table' or picker_and_options.picker == nil then
    vim.notify("Expected { picker = 'live_grep', options = { ... } }", vim.log.levels.WARN)
    return
  end

  local opts = picker_and_options.options or {}
  local original_entry_maker = make_entry.gen_from_vimgrep(opts)

  opts.entry_maker = function(line)
    local entry = original_entry_maker(line)

    local displayer = entry_display.create {
      separator = ' ',
      items = {
        { width = filetype_icon_width },
        { width = nil },
        { width = nil },
        { remaining = true },
      },
    }

    entry.display = function(e)
      local tail, path_to_display = get_path_and_tail(e.filename)
      local icon, icon_highlight = utils.get_devicons(tail)
      local coordinates = ''

      if not opts.disable_coordinates and e.lnum then
        coordinates = e.col and string.format(' -> %s:%s', e.lnum, e.col) or string.format(' -> %s', e.lnum)
      end

      local text = opts.file_encoding and vim.iconv(e.text, opts.file_encoding, 'utf8') or e.text

      return displayer {
        { icon, icon_highlight },
        tail .. coordinates .. ' ',
        { path_to_display, 'TelescopeResultsComment' },
        text,
      }
    end

    return entry
  end

  if picker_and_options.picker == 'live_grep' then
    require('telescope.builtin').live_grep(opts)
  elseif picker_and_options.picker == 'grep_string' then
    require('telescope.builtin').grep_string(opts)
  elseif picker_and_options.picker == '' then
    vim.notify('Picker was not specified', vim.log.levels.WARN)
  else
    vim.notify('Unsupported picker for pretty_grep_picker: ' .. picker_and_options.picker, vim.log.levels.WARN)
  end
end

return M
