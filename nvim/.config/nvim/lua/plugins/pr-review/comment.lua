-- Scratch-float editor for writing a comment body or a review summary.
--
-- The buffer is tagged with b:pr_review_comment so the @mention cmp source activates
-- only here. <C-s> (or :w-style) submits, q/<Esc> cancels.
local M = {}

local ui = require 'utils.ui'
local border = ui.BORDER

-- Register the @mention cmp source once, then enable it (alongside the buffer source)
-- for the given comment buffer. No-ops gracefully if nvim-cmp is unavailable.
local cmp_registered = false
local function attach_mentions(buf)
  local ok, cmp = pcall(require, 'cmp')
  if not ok then
    return
  end
  local src = require 'plugins.pr-review.cmp_source'
  if not cmp_registered then
    cmp.register_source('pr_mentions', src.source.new())
    cmp_registered = true
  end
  cmp.setup.buffer { sources = { { name = 'pr_mentions' }, { name = 'buffer' } } }
  -- the source itself also guards on this flag via is_available()
  vim.api.nvim_buf_set_var(buf, 'pr_review_comment', true)
end

-- Open the editor. opts = { title, initial (list of lines), on_submit(text), on_cancel }.
function M.input(opts)
  ui.link_first('PrReviewFloatTitle', { 'Title', 'Function', 'DiagnosticInfo' })

  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_option(buf, 'buftype', 'nofile')
  vim.api.nvim_buf_set_option(buf, 'filetype', 'markdown')
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, opts.initial or { '' })
  -- enable @mention completion (also sets the b:pr_review_comment flag the source uses)
  attach_mentions(buf)

  local ui_w, ui_h = vim.o.columns, vim.o.lines
  local win_w = math.min(80, ui_w - 8)
  local win_h = math.min(12, ui_h - 6)

  local win = vim.api.nvim_open_win(buf, true, {
    relative = 'editor',
    width = win_w,
    height = win_h,
    row = math.floor((ui_h - win_h) / 2 - 1),
    col = math.floor((ui_w - win_w) / 2),
    style = 'minimal',
    border = border,
    title = {
      { ' 󰆉 ', 'PrReviewFloatTitle' },
      { (opts.title or 'comment') .. ' ', 'PrReviewFloatTitle' },
      { '— <C-s> submit · q cancel · @ to mention ', 'Comment' },
    },
    title_pos = 'left',
  })
  vim.api.nvim_win_set_option(win, 'winhl', 'Normal:NormalFloat,FloatBorder:FloatBorder')
  vim.api.nvim_win_set_option(win, 'wrap', true)
  vim.api.nvim_win_set_option(win, 'linebreak', true)

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
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    local text = table.concat(lines, '\n'):gsub('%s+$', '')
    close()
    opts.on_submit(text)
  end

  local function cancel()
    close()
    if opts.on_cancel then
      opts.on_cancel()
    end
  end

  for _, mode in ipairs { 'n', 'i' } do
    vim.api.nvim_buf_set_keymap(buf, mode, '<C-s>', '', { noremap = true, silent = true, callback = submit })
  end
  for _, lhs in ipairs { 'q', '<Esc>' } do
    vim.api.nvim_buf_set_keymap(buf, 'n', lhs, '', { noremap = true, silent = true, callback = cancel })
  end

  vim.cmd 'startinsert'
end

return M
