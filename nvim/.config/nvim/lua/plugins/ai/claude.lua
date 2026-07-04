-- claude.lua — ad-hoc prompt box for claudecode.nvim.
--
-- Opens a floating input next to the cursor where you type a prompt, then sends
-- it to the *active* Claude session together with the file/line under the cursor
-- as context. The context is delivered as a native @mention (the same mechanism
-- as `:ClaudeCodeSend`), and the typed prompt is written to the Claude terminal
-- and submitted.
--
-- This is a plain module (not a lazy plugin spec) — it is required on demand from
-- the claudecode keymap in `plugins/ai/core.lua`.

local M = {}

-- Snapshot the cursor's context *before* the floating window opens, since opening
-- it moves the current window/cursor. send_at_mention expects 0-indexed lines.
local function capture_context()
  local bufnr = vim.api.nvim_get_current_buf()
  local file_path = vim.api.nvim_buf_get_name(bufnr)
  if file_path == '' or vim.bo[bufnr].buftype ~= '' then
    file_path = nil -- unnamed/scratch/terminal buffer: no file context to attach
  end
  local cursor = vim.api.nvim_win_get_cursor(0) -- { row (1-indexed), col (0-indexed) }
  return {
    file_path = file_path,
    line = cursor[1],
  }
end

-- Send the context @mention first, then (after the mention has had time to land in
-- Claude's input) type the prompt and submit it.
local function send(prompt, ctx)
  prompt = vim.trim(prompt)
  if prompt == '' then
    vim.notify('Claude prompt: nothing to send', vim.log.levels.WARN)
    return
  end

  local terminal = require 'claudecode.terminal'

  if ctx.file_path then
    -- 0-indexed single-line mention for the cursor's line.
    local zero = ctx.line - 1
    require('claudecode').send_at_mention(ctx.file_path, zero, zero, 'cursor-prompt')
  end

  -- The @mention is broadcast over the WebSocket with a small debounce (~50ms) and
  -- is inserted into Claude's prompt input asynchronously. Defer typing the prompt
  -- so it is appended after the mention rather than racing ahead of it.
  local delay = ctx.file_path and 200 or 0
  vim.defer_fn(function()
    local ok = terminal.send_to_terminal(prompt, { submit = true, focus = false })
    if not ok then
      vim.notify('Claude prompt: no active Claude session to send to', vim.log.levels.ERROR)
    end
  end, delay)
end

function M.open()
  local ctx = capture_context()

  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = 'wipe'
  vim.bo[buf].filetype = 'markdown'

  local width = math.max(40, math.min(80, math.floor(vim.o.columns * 0.6)))
  local height = math.max(3, math.min(10, math.floor(vim.o.lines * 0.3)))

  local title = ' ask claude '
  if ctx.file_path then
    title = string.format(' ask claude — %s:%d ', vim.fn.fnamemodify(ctx.file_path, ':t'), ctx.line)
  end

  local win = vim.api.nvim_open_win(buf, true, {
    relative = 'cursor',
    row = 1,
    col = 0,
    width = width,
    height = height,
    style = 'minimal',
    border = require('utils.ui').border,
    title = title,
    title_pos = 'center',
    footer = ' <C-s>/<CR> send · <Esc>/q cancel ',
    footer_pos = 'center',
  })
  vim.wo[win].wrap = true

  local closed = false
  local function close()
    if closed then
      return
    end
    closed = true
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
  end

  local function submit()
    local prompt = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), '\n')
    close()
    send(prompt, ctx)
  end

  local opts = { buffer = buf, nowait = true, silent = true }
  vim.keymap.set('i', '<C-s>', submit, opts)
  vim.keymap.set('n', '<C-s>', submit, opts)
  vim.keymap.set('n', '<CR>', submit, opts)
  vim.keymap.set('n', '<Esc>', close, opts)
  vim.keymap.set('n', 'q', close, opts)
  vim.keymap.set('n', '<C-c>', close, opts)

  vim.cmd.startinsert()
end

return M
