local M = {}

local TOOL = 'json2struct'
local INSTALL_PKG = 'github.com/yudppp/json2struct/cmd/json2struct@latest'

local FIELD_ORDER = { 'url', 'name', 'prefix', 'suffix' }
local FIELD_LABELS = {
  url = 'URL*:      ',
  name = 'name:      ',
  prefix = 'prefix:    ',
  suffix = 'suffix:    ',
}
local INDENT = '  '
local LABEL_WIDTH = 11
local VALUE_COL = #INDENT + LABEL_WIDTH

local FLAGS = { 'short', 'local', 'omitempty', 'example' }

local NS = vim.api.nvim_create_namespace 'json2struct_form'

local HELP_ROWS = {
  { '<CR>', 'submit' },
  { '<Esc> / q', 'cancel' },
  { '<Space>', 'toggle flag' },
  { '<Tab>', 'next field' },
  { '<S-Tab>', 'previous field' },
  { '?', 'show this help' },
}

local function tool_installed()
  return vim.fn.executable(TOOL) == 1
end

local function install_then(cb)
  if tool_installed() then
    cb()
    return
  end
  if vim.fn.executable 'go' ~= 1 then
    vim.notify('json2struct: `go` not found on PATH; install json2struct manually', vim.log.levels.ERROR)
    return
  end
  vim.notify('json2struct: not found, running `go install ' .. INSTALL_PKG .. '`...', vim.log.levels.INFO)
  vim.fn.jobstart({ 'go', 'install', INSTALL_PKG }, {
    on_exit = function(_, code)
      vim.schedule(function()
        if code ~= 0 or not tool_installed() then
          vim.notify(
            'json2struct: install failed (exit ' .. code .. '). Ensure `$(go env GOPATH)/bin` is on PATH.',
            vim.log.levels.ERROR
          )
          return
        end
        vim.notify('json2struct: installed', vim.log.levels.INFO)
        cb()
      end)
    end,
  })
end

local function build_layout(state)
  local lines = {}
  local meta = {
    fields = {},
    flags = {},
    sections = {},
    labels = {},
    asterisks = {},
    field_value_col = VALUE_COL,
    flag_box_col = #INDENT,
  }

  local function add(text)
    lines[#lines + 1] = text or ''
    return #lines
  end

  add ''
  meta.sections[#meta.sections + 1] = { row = add(INDENT .. 'Input'), col_start = #INDENT, col_end = #INDENT + 5 }
  add ''

  for _, f in ipairs(FIELD_ORDER) do
    local label = INDENT .. FIELD_LABELS[f]
    local colon = label:find ':' or (#label)
    local row = add(label .. (state[f] or ''))
    meta.fields[f] = row
    meta.labels[#meta.labels + 1] = { row = row, col_start = #INDENT, col_end = colon - 1 }
    if f == 'url' then
      meta.asterisks[#meta.asterisks + 1] = { row = row, col_start = #INDENT + 3, col_end = #INDENT + 4 }
    end
  end

  add ''
  meta.sections[#meta.sections + 1] = { row = add(INDENT .. 'Options'), col_start = #INDENT, col_end = #INDENT + 7 }
  add ''

  for _, flag in ipairs(FLAGS) do
    local prefix = INDENT .. (state[flag] and '[x] ' or '[ ] ')
    local row = add(prefix .. flag)
    meta.flags[flag] = row
  end

  add ''
  local footer_key = '?'
  local footer_desc = 'show keybindings'
  local footer_text = INDENT .. footer_key .. '  ' .. footer_desc
  local footer_row = add(footer_text)
  meta.footer = {
    row = footer_row,
    key_start = #INDENT,
    key_end = #INDENT + #footer_key,
    desc_start = #INDENT + #footer_key + 2,
    desc_end = #footer_text,
  }

  return lines, meta
end

local function apply_highlights(buf, meta)
  vim.api.nvim_buf_clear_namespace(buf, NS, 0, -1)

  for _, s in ipairs(meta.sections) do
    vim.api.nvim_buf_set_extmark(buf, NS, s.row - 1, s.col_start, {
      end_row = s.row - 1,
      end_col = s.col_end,
      hl_group = 'Title',
    })
  end

  for _, l in ipairs(meta.labels) do
    vim.api.nvim_buf_set_extmark(buf, NS, l.row - 1, l.col_start, {
      end_row = l.row - 1,
      end_col = l.col_end,
      hl_group = 'Label',
    })
  end

  for _, a in ipairs(meta.asterisks) do
    vim.api.nvim_buf_set_extmark(buf, NS, a.row - 1, a.col_start, {
      end_row = a.row - 1,
      end_col = a.col_end,
      hl_group = 'DiagnosticError',
    })
  end

  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  for _, row in pairs(meta.flags) do
    local line = lines[row]
    if line then
      local box_start = meta.flag_box_col
      local box_text = line:sub(box_start + 1, box_start + 3)
      local hl = box_text == '[x]' and 'DiagnosticOk' or 'Comment'
      vim.api.nvim_buf_set_extmark(buf, NS, row - 1, box_start, {
        end_row = row - 1,
        end_col = box_start + 3,
        hl_group = hl,
      })
    end
  end

  if meta.footer then
    local f = meta.footer
    vim.api.nvim_buf_set_extmark(buf, NS, f.row - 1, f.key_start, {
      end_row = f.row - 1,
      end_col = f.key_end,
      hl_group = 'Special',
    })
    vim.api.nvim_buf_set_extmark(buf, NS, f.row - 1, f.desc_start, {
      end_row = f.row - 1,
      end_col = f.desc_end,
      hl_group = 'Comment',
    })
  end
end

local function parse_buffer(buf, meta)
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local state = {}
  for key, row in pairs(meta.fields) do
    local line = lines[row] or ''
    local val = line:match ':%s*(.*)$' or ''
    state[key] = (val:gsub('^%s+', ''):gsub('%s+$', ''))
  end
  for key, row in pairs(meta.flags) do
    local line = lines[row] or ''
    local box = line:sub(meta.flag_box_col + 1, meta.flag_box_col + 3)
    state[key] = box == '[x]'
  end
  return state
end

local function build_args(state)
  local args = { TOOL }
  if state.name and state.name ~= '' then
    args[#args + 1] = '-name=' .. state.name
  end
  if state.prefix and state.prefix ~= '' then
    args[#args + 1] = '-prefix=' .. state.prefix
  end
  if state.suffix and state.suffix ~= '' then
    args[#args + 1] = '-suffix=' .. state.suffix
  end
  if state.short then
    args[#args + 1] = '-short'
  end
  if state['local'] then
    args[#args + 1] = '-local'
  end
  if state.omitempty then
    args[#args + 1] = '-omitempty'
  end
  if state.example then
    args[#args + 1] = '-example'
  end
  return args
end

local function run(target_buf, insert_row_0idx, state)
  vim.notify('json2struct: fetching ' .. state.url, vim.log.levels.INFO)

  local body_chunks = {}
  local curl_err = {}
  vim.fn.jobstart({ 'curl', '-fsSL', state.url }, {
    stdout_buffered = true,
    stderr_buffered = true,
    on_stdout = function(_, d)
      body_chunks = d
    end,
    on_stderr = function(_, d)
      curl_err = d
    end,
    on_exit = function(_, code)
      vim.schedule(function()
        if code ~= 0 then
          local msg = table.concat(curl_err, '\n')
          vim.notify('json2struct: curl failed (exit ' .. code .. ')' .. (msg ~= '' and ': ' .. msg or ''), vim.log.levels.ERROR)
          return
        end
        local json = table.concat(body_chunks, '\n')
        if json == '' then
          vim.notify('json2struct: response was empty', vim.log.levels.WARN)
          return
        end

        local args = build_args(state)
        local out = {}
        local err = {}
        local job = vim.fn.jobstart(args, {
          stdout_buffered = true,
          stderr_buffered = true,
          on_stdout = function(_, d)
            out = d
          end,
          on_stderr = function(_, d)
            err = d
          end,
          on_exit = function(_, c2)
            vim.schedule(function()
              if c2 ~= 0 then
                local msg = table.concat(err, '\n')
                vim.notify('json2struct: tool failed (exit ' .. c2 .. ')' .. (msg ~= '' and ': ' .. msg or ''), vim.log.levels.ERROR)
                return
              end
              while #out > 0 and out[#out] == '' do
                table.remove(out)
              end
              if #out == 0 then
                vim.notify('json2struct: no output produced', vim.log.levels.WARN)
                return
              end
              if not vim.api.nvim_buf_is_valid(target_buf) then
                vim.notify('json2struct: target buffer no longer exists', vim.log.levels.ERROR)
                return
              end
              local clamped = math.min(insert_row_0idx, vim.api.nvim_buf_line_count(target_buf))
              vim.api.nvim_buf_set_lines(target_buf, clamped, clamped, false, out)
              vim.notify('json2struct: inserted ' .. #out .. ' lines', vim.log.levels.INFO)
            end)
          end,
        })
        if job <= 0 then
          vim.notify('json2struct: failed to spawn json2struct', vim.log.levels.ERROR)
          return
        end
        vim.fn.chansend(job, json)
        vim.fn.chanclose(job, 'stdin')
      end)
    end,
  })
end

local function open_help()
  local left_width = 0
  for _, row in ipairs(HELP_ROWS) do
    if #row[1] > left_width then
      left_width = #row[1]
    end
  end

  local lines = { '' }
  for _, row in ipairs(HELP_ROWS) do
    lines[#lines + 1] = INDENT .. row[1] .. string.rep(' ', left_width - #row[1] + 3) .. row[2]
  end
  lines[#lines + 1] = ''

  local width = 0
  for _, line in ipairs(lines) do
    if #line > width then
      width = #line
    end
  end
  width = math.max(width + 4, 32)
  local height = #lines

  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].buftype = 'nofile'
  vim.bo[buf].bufhidden = 'wipe'
  vim.bo[buf].swapfile = false
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)

  local ui = vim.api.nvim_list_uis()[1] or { width = vim.o.columns, height = vim.o.lines }
  local win = vim.api.nvim_open_win(buf, true, {
    relative = 'editor',
    width = width,
    height = height,
    col = math.floor((ui.width - width) / 2),
    row = math.floor((ui.height - height) / 2),
    style = 'minimal',
    border = 'rounded',
    title = { { ' help ', 'FloatTitle' } },
    title_pos = 'center',
  })

  vim.wo[win].winhighlight = 'NormalFloat:NormalFloat,FloatBorder:FloatBorder'

  for i, row in ipairs(HELP_ROWS) do
    local lnum = i
    local line_text = lines[lnum + 1] or ''
    vim.api.nvim_buf_set_extmark(buf, NS, lnum, #INDENT, {
      end_row = lnum,
      end_col = #INDENT + #row[1],
      hl_group = 'Special',
    })
    vim.api.nvim_buf_set_extmark(buf, NS, lnum, #INDENT + left_width + 3, {
      end_row = lnum,
      end_col = #line_text,
      hl_group = 'Comment',
    })
  end

  local function close()
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
  end

  local opts = { buffer = buf, nowait = true, silent = true }
  vim.keymap.set('n', 'q', close, opts)
  vim.keymap.set('n', '<Esc>', close, opts)
  vim.keymap.set('n', '?', close, opts)
end

function M.open_form()
  install_then(function()
    local target_buf = vim.api.nvim_get_current_buf()
    local insert_row_0idx = vim.api.nvim_win_get_cursor(0)[1]

    local state = {
      url = '',
      name = 'data',
      prefix = '',
      suffix = '',
      short = false,
      ['local'] = false,
      omitempty = false,
      example = false,
    }

    local lines, meta = build_layout(state)
    local width = 56
    local height = #lines

    local buf = vim.api.nvim_create_buf(false, true)
    vim.bo[buf].buftype = 'nofile'
    vim.bo[buf].bufhidden = 'wipe'
    vim.bo[buf].swapfile = false
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)

    local ui = vim.api.nvim_list_uis()[1] or { width = vim.o.columns, height = vim.o.lines }
    local win = vim.api.nvim_open_win(buf, true, {
      relative = 'editor',
      width = width,
      height = height,
      col = math.floor((ui.width - width) / 2),
      row = math.floor((ui.height - height) / 2),
      style = 'minimal',
      border = 'rounded',
      title = ' json2struct ',
      title_pos = 'center',
    })

    vim.wo[win].winhighlight = 'NormalFloat:NormalFloat,FloatBorder:FloatBorder'

    apply_highlights(buf, meta)
    vim.api.nvim_win_set_cursor(win, { meta.fields.url, meta.field_value_col })

    local nav_targets = {}
    for _, f in ipairs(FIELD_ORDER) do
      nav_targets[#nav_targets + 1] = { row = meta.fields[f], col = meta.field_value_col }
    end
    for _, fl in ipairs(FLAGS) do
      nav_targets[#nav_targets + 1] = { row = meta.flags[fl], col = meta.flag_box_col }
    end

    local function close()
      if vim.api.nvim_win_is_valid(win) then
        vim.api.nvim_win_close(win, true)
      end
    end

    local function submit()
      local s = parse_buffer(buf, meta)
      if not s.url or s.url == '' then
        vim.notify('json2struct: URL is required', vim.log.levels.ERROR)
        return
      end
      close()
      run(target_buf, insert_row_0idx, s)
    end

    local function toggle_flag()
      local row = vim.api.nvim_win_get_cursor(win)[1]
      local line = vim.api.nvim_buf_get_lines(buf, row - 1, row, false)[1]
      if not line then
        return
      end
      local box_start = meta.flag_box_col
      local box_text = line:sub(box_start + 1, box_start + 3)
      local new
      if box_text == '[ ]' then
        new = '[x]'
      elseif box_text == '[x]' then
        new = '[ ]'
      else
        return
      end
      vim.api.nvim_buf_set_text(buf, row - 1, box_start, row - 1, box_start + 3, { new })
      apply_highlights(buf, meta)
    end

    local function jump_to(target)
      local line = vim.api.nvim_buf_get_lines(buf, target.row - 1, target.row, false)[1] or ''
      local col = math.min(target.col, math.max(0, #line))
      vim.api.nvim_win_set_cursor(win, { target.row, col })
    end

    local function find_nav_index(row)
      for i, t in ipairs(nav_targets) do
        if t.row == row then
          return i
        end
      end
      return nil
    end

    local function next_field()
      local row = vim.api.nvim_win_get_cursor(win)[1]
      local i = find_nav_index(row)
      if not i then
        jump_to(nav_targets[1])
        return
      end
      jump_to(nav_targets[(i % #nav_targets) + 1])
    end

    local function prev_field()
      local row = vim.api.nvim_win_get_cursor(win)[1]
      local i = find_nav_index(row)
      if not i then
        jump_to(nav_targets[#nav_targets])
        return
      end
      jump_to(nav_targets[((i - 2) % #nav_targets) + 1])
    end

    local opts = { buffer = buf, nowait = true, silent = true }
    vim.keymap.set('n', '<CR>', submit, opts)
    vim.keymap.set('n', '<Esc>', close, opts)
    vim.keymap.set('n', 'q', close, opts)
    vim.keymap.set('n', '<Space>', toggle_flag, opts)
    vim.keymap.set('n', '<Tab>', next_field, opts)
    vim.keymap.set('n', '<S-Tab>', prev_field, opts)
    vim.keymap.set('n', '?', open_help, opts)
  end)
end

return M
