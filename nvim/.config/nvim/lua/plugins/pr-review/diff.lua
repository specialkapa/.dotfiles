-- Side-by-side diff view for a single PR file.
--
-- Two real scratch buffers (base | head) are shown in a vertical split inside a
-- dedicated review tab, with Neovim's native diff mode for syntax highlighting and
-- ]c/[c hunk navigation. Because we load the FULL file blob on each side, a buffer
-- line number maps directly to the file line number GitHub expects: head buffer ->
-- side=RIGHT, base buffer -> side=LEFT.
--
-- Comments are rendered as rounded-border boxes (virt_lines) anchored on their line;
-- a thread groups a root comment with its replies. Red/green diff colors and folding
-- of unchanged regions are scoped to the review windows via a highlight namespace.
local M = {}

local ns = vim.api.nvim_create_namespace 'PrReviewComments'

-- Per-window highlight namespaces for the diff colors. Native vimdiff paints a buffer's
-- *exclusive* lines with DiffAdd on BOTH sides, so a single global override would colour
-- removed lines green too. Instead each side gets its own namespace: the base (old) side
-- reds, the head (new) side greens. nvim_win_set_hl_ns falls back to the global theme for
-- every group we don't define, so non-diff regions keep the active colorscheme.
local diff_ns_base = vim.api.nvim_create_namespace 'PrReviewDiffBase'
local diff_ns_head = vim.api.nvim_create_namespace 'PrReviewDiffHead'

-- Diff colours lifted from the Claude Code CLI diff previews (dark + light variants).
local CC_DARK = {
  add = '#225c2b', add_dim = '#47584a', add_word = '#38a660', -- additions: line / dimmed / changed-word
  rem = '#7a2936', rem_dim = '#69484d', rem_word = '#b3596b', -- removals:  line / dimmed / changed-word
}
local CC_LIGHT = {
  add = '#69db7c', add_dim = '#c7e1cb', add_word = '#2f9d44',
  rem = '#ffa8b4', rem_dim = '#fdd2d8', rem_word = '#d1454b',
}

-- Define the Diff* groups inside the two per-window namespaces. Only `bg` is set so the
-- theme's syntax-highlight foreground still shows through the coloured lines; the filler
-- placeholders (DiffDelete) hide their `-` dashes by matching fg to bg for a clean band.
local function setup_diff_colors()
  local P = vim.o.background == 'light' and CC_LIGHT or CC_DARK
  -- head (new) side: greens
  vim.api.nvim_set_hl(diff_ns_head, 'DiffAdd', { bg = P.add })
  vim.api.nvim_set_hl(diff_ns_head, 'DiffChange', { bg = P.add_dim })
  vim.api.nvim_set_hl(diff_ns_head, 'DiffText', { bg = P.add_word })
  vim.api.nvim_set_hl(diff_ns_head, 'DiffDelete', { bg = P.rem_dim, fg = P.rem_dim })
  -- base (old) side: reds
  vim.api.nvim_set_hl(diff_ns_base, 'DiffAdd', { bg = P.rem })
  vim.api.nvim_set_hl(diff_ns_base, 'DiffChange', { bg = P.rem_dim })
  vim.api.nvim_set_hl(diff_ns_base, 'DiffText', { bg = P.rem_word })
  vim.api.nvim_set_hl(diff_ns_base, 'DiffDelete', { bg = P.add_dim, fg = P.add_dim })
end

local ASTRONAUT = ''
local MAXW = 72 -- cap on the inner text width of a comment box

-- Persistent window/buffer handles so switching files reuses the same layout.
-- right_is_scratch is false in checkout mode, where the head buffer is the real file.
local view = { tab = nil, left_win = nil, right_win = nil, left_buf = nil, right_buf = nil, right_is_scratch = true }

-- Real on-disk buffers we attached review keymaps/marks to (checkout mode), so we can
-- strip our additions from them on close (a scratch buffer is just wiped instead).
local real_bufs = {}

-- Set by show_file so the keymaps / target helpers know what they are looking at.
local ctx = nil

local function dw(s)
  return vim.fn.strdisplaywidth(s)
end

local ui = require 'utils.ui'

local function setup_highlights()
  -- comment-thread accents take the theme's diagnostic *colors* but force italic off
  -- (the comment-box titles use these, and some themes italicize Diagnostic* groups)
  local function accent(name, candidates)
    for _, g in ipairs(candidates) do
      local fg = ui.hl_fg(g)
      if fg then
        return vim.api.nvim_set_hl(0, name, { fg = fg, italic = false })
      end
    end
    ui.link_first(name, candidates)
  end
  accent('PrReviewPosted', { 'DiagnosticInfo', 'Function', 'Directory' }) -- blue: posted
  accent('PrReviewPending', { 'DiagnosticWarn', 'WarningMsg' }) -- yellow: queued
  accent('PrReviewResolved', { 'DiagnosticOk', 'DiagnosticHint', 'String' }) -- green: resolved
  ui.ensure_hl('PrReviewBody', { link = 'Normal' })
  ui.link_first('PrReviewWinbarDim', { 'Comment', 'NonText' }) -- base side / muted text

  -- winbar mode badges: derive the badge background from the theme's accent colors and
  -- the text from Normal's background, so they read as solid pills in any colorscheme
  local nbg = ui.hl_bg 'Normal'
  local view_c = ui.hl_fg 'DiagnosticInfo' or ui.hl_fg 'Function'
  local ok_c = ui.hl_fg 'DiagnosticOk' or ui.hl_fg 'DiagnosticHint' or ui.hl_fg 'String'
  if view_c then
    vim.api.nvim_set_hl(0, 'PrReviewModeView', { fg = nbg, bg = view_c, bold = true })
  else
    ui.link_first('PrReviewModeView', { 'PmenuSel', 'Visual' })
  end
  if ok_c then
    vim.api.nvim_set_hl(0, 'PrReviewModeCheckout', { fg = nbg, bg = ok_c, bold = true })
  else
    ui.link_first('PrReviewModeCheckout', { 'PmenuSel', 'Visual' })
  end
  -- diff line colours match the Claude Code CLI previews, scoped per-window (see below)
  setup_diff_colors()
end

-- Foldtext for the unchanged regions native diff folds away. Exposed globally so the
-- 'foldtext' window option (a vim expression) can call it.
function _G.PrReviewFoldText()
  local count = vim.v.foldend - vim.v.foldstart + 1
  return string.format('  󰘖  %d unchanged lines  ⋯', count)
end

-- Split content into buffer lines. A trailing newline would otherwise yield a stray
-- empty final line, so strip exactly one.
local function to_lines(content)
  if content == nil or content == '' then
    return nil
  end
  if content:sub(-1) == '\n' then
    content = content:sub(1, -2)
  end
  return vim.split(content, '\n', { plain = true })
end

-- Parse a unified-diff `patch` into the sets of line numbers GitHub will accept a
-- comment on, per side. right = new-file lines in the diff, left = old-file lines.
function M.parse_patch(patch)
  local right, left = {}, {}
  if not patch then
    return { right = right, left = left }
  end
  local old_ln, new_ln = 0, 0
  for line in (patch .. '\n'):gmatch '([^\n]*)\n' do
    local oa, na = line:match '^@@%s+%-(%d+),?%d*%s+%+(%d+),?%d*%s+@@'
    if oa then
      old_ln = tonumber(oa)
      new_ln = tonumber(na)
    elseif line:sub(1, 1) == '+' then
      right[new_ln] = true
      new_ln = new_ln + 1
    elseif line:sub(1, 1) == '-' then
      left[old_ln] = true
      old_ln = old_ln + 1
    elseif line:sub(1, 1) == ' ' or line == '' then
      right[new_ln] = true
      left[old_ln] = true
      new_ln = new_ln + 1
      old_ln = old_ln + 1
    end
    -- "\ No newline at end of file" and the +++/--- headers are ignored
  end
  return { right = right, left = left }
end

-- Hard-wrap a (possibly multi-line) comment body to `width` display columns.
local function wrap_body(body, width)
  local out = {}
  for _, line in ipairs(vim.split(body or '', '\n', { plain = true })) do
    if line == '' then
      out[#out + 1] = ''
    end
    while dw(line) > width do
      -- split at the last space within width, else hard-cut
      local cut = width
      local prefix = vim.fn.strcharpart(line, 0, cut)
      local sp = prefix:match '^.*()%s%S*$'
      if sp and sp > 1 then
        out[#out + 1] = line:sub(1, sp - 1)
        line = line:sub(sp + 1)
      else
        out[#out + 1] = prefix
        line = line:sub(#prefix + 1)
      end
    end
    if line ~= '' then
      out[#out + 1] = line
    end
  end
  if #out == 0 then
    out[1] = ''
  end
  return out
end

-- Build the rounded-border box (a list of virt_lines) for one comment thread.
local function box_lines(thread)
  local hl = 'PrReviewPosted'
  if thread.resolved then
    hl = 'PrReviewResolved'
  elseif thread.pending then
    hl = 'PrReviewPending'
  end

  -- logical rows: each comment contributes a header (or separator) + wrapped body
  local rows = {}
  for i, c in ipairs(thread.comments) do
    rows[#rows + 1] = { kind = i == 1 and 'header' or 'sep', text = ASTRONAUT .. ' ' .. (c.user or 'you') }
    for _, bl in ipairs(wrap_body(c.body, MAXW)) do
      rows[#rows + 1] = { kind = 'body', text = bl }
    end
  end

  -- header/sep lines carry fixed "─ <text> " decoration plus the closing dash slot, so
  -- they need one column beyond their text for the box to stay rectangular; body lines
  -- need only their own width. Without the +1, a header wider than every body forces the
  -- dash count negative and the top corner overshoots the bottom corner.
  local w = 0
  for _, r in ipairs(rows) do
    local contrib = r.kind == 'body' and dw(r.text) or dw(r.text) + 1
    w = math.max(w, contrib)
  end
  w = math.min(math.max(w, 12), MAXW)

  local function header_line(text, lc, rc)
    -- match the body width (│ + space + w + space + │ = w+4): corner + "─ " + text
    -- + " " + dashes + corner must also total w+4, so dashes = w - dw(text) - 1
    local dashes = w - dw(text) - 1
    return lc .. '─ ' .. text .. ' ' .. string.rep('─', math.max(0, dashes)) .. rc
  end

  local out = {}
  for _, r in ipairs(rows) do
    if r.kind == 'header' then
      out[#out + 1] = { { header_line(r.text, '╭', '╮'), hl } }
    elseif r.kind == 'sep' then
      out[#out + 1] = { { header_line(r.text, '├', '┤'), hl } }
    else
      local padded = r.text .. string.rep(' ', math.max(0, w - dw(r.text)))
      out[#out + 1] = { { '│ ', hl }, { padded, 'PrReviewBody' }, { ' │', hl } }
    end
  end
  out[#out + 1] = { { '╰' .. string.rep('─', w + 2) .. '╯', hl } }
  return out
end

local function sign_for(thread)
  if thread.resolved then
    return '', 'PrReviewResolved'
  elseif thread.pending then
    return '', 'PrReviewPending'
  end
  return '', 'PrReviewPosted'
end

-- Place a comment thread on the given buffer at line (1-based).
local function place_thread(buf, line, thread)
  local total = vim.api.nvim_buf_line_count(buf)
  if not line or line < 1 or line > total then
    return
  end
  local sign, sign_hl = sign_for(thread)
  pcall(vim.api.nvim_buf_set_extmark, buf, ns, line - 1, 0, {
    sign_text = sign,
    sign_hl_group = sign_hl,
    virt_lines = box_lines(thread),
    virt_lines_above = false,
  })
end

-- Re-render all comment threads for the current file.
function M.render_threads()
  if not ctx then
    return
  end
  for _, buf in ipairs { view.left_buf, view.right_buf } do
    if buf and vim.api.nvim_buf_is_valid(buf) then
      vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
    end
  end
  for _, thread in ipairs(ctx.threads or {}) do
    local buf = thread.side == 'LEFT' and view.left_buf or view.right_buf
    if buf then
      place_thread(buf, thread.line, thread)
    end
  end
end

-- The (path, line, side) under the cursor, or nil if the cursor is not in a diff buffer.
function M.current_target()
  if not ctx then
    return nil
  end
  local win = vim.api.nvim_get_current_win()
  local line = vim.api.nvim_win_get_cursor(win)[1]
  if win == view.right_win then
    return { path = ctx.file.filename, line = line, side = 'RIGHT' }
  elseif win == view.left_win then
    return { path = ctx.file.filename, line = line, side = 'LEFT' }
  end
  return nil
end

-- Is `target` on a line that is part of the diff (so GitHub will accept a comment)?
function M.is_commentable(target)
  if not ctx or not ctx.ranges then
    return true -- no patch info; let GitHub decide
  end
  local set = target.side == 'LEFT' and ctx.ranges.left or ctx.ranges.right
  return set[target.line] == true
end

local function buf_setup(buf, lines, ft, name)
  vim.api.nvim_buf_set_option(buf, 'modifiable', true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines or { '' })
  vim.api.nvim_buf_set_option(buf, 'modifiable', false)
  vim.api.nvim_buf_set_option(buf, 'buftype', 'nofile')
  vim.api.nvim_buf_set_option(buf, 'buflisted', false)
  if ft then
    vim.api.nvim_buf_set_option(buf, 'filetype', ft)
  end
  pcall(vim.api.nvim_buf_set_name, buf, name)
end

-- Enable native diff + folding of unchanged regions on a diff window, and apply the
-- side-specific diff-colour namespace so additions read green / removals red.
local function setup_diff_window(win, hl_ns)
  vim.api.nvim_win_set_hl_ns(win, hl_ns)
  vim.api.nvim_win_call(win, function()
    vim.cmd 'diffthis'
    vim.opt_local.foldmethod = 'diff'
    vim.opt_local.foldenable = true
    vim.opt_local.foldlevel = 0
    vim.opt_local.foldcolumn = '1'
    -- keep line numbers (the inherited statuscolumn) in the diff, but hide the
    -- end-of-buffer ~ markers
    vim.opt_local.fillchars:append 'foldopen:▾,foldclose:▸,fold: ,eob: '
    vim.opt_local.foldtext = 'v:lua.PrReviewFoldText()'
    vim.opt_local.cursorline = true
  end)
end

-- The review keymaps as (lhs, handler-key, desc). A single source of truth so we can
-- both apply them and strip them back off real file buffers on close.
local KEYMAPS = {
  { '<leader>rc', 'comment', 'PR: comment on line' },
  { '<leader>re', 'edit', 'PR: edit comment' },
  { '<leader>rx', 'delete', 'PR: delete comment' },
  { '<leader>rp', 'reply', 'PR: reply to comment' },
  { '<leader>ro', 'resolve', 'PR: resolve/unresolve thread' },
  { '<leader>rs', 'start_review', 'PR: start review' },
  { '<leader>ra', 'approve', 'PR: approve' },
  { '<leader>rr', 'reject', 'PR: request changes' },
  { '<leader>rd', 'comment_only', 'PR: comment-only review (no verdict)' },
  { '<leader>rX', 'discard', 'PR: discard review (drop queued comments)' },
  { ']f', 'next_file', 'PR: next file' },
  { '[f', 'prev_file', 'PR: previous file' },
  { '<leader>rf', 'files', 'PR: file navigator (float)' },
  { '<leader>rt', 'panel', 'PR: toggle file panel (side)' },
  { 'q', 'close', 'PR: close review' },
}

local function apply_keymaps(buf, handlers)
  for _, m in ipairs(KEYMAPS) do
    vim.api.nvim_buf_set_keymap(buf, 'n', m[1], '', { noremap = true, silent = true, callback = handlers[m[2]], desc = m[3] })
  end
  -- fold toggle isn't a session handler, just a normal-mode za
  vim.api.nvim_buf_set_keymap(buf, 'n', '<Tab>', '', {
    noremap = true,
    silent = true,
    callback = function()
      vim.cmd 'normal! za'
    end,
    desc = 'PR: toggle fold',
  })
end

-- Remove our buffer-local keymaps (used to clean real file buffers on close).
local function clear_keymaps(buf)
  for _, m in ipairs(KEYMAPS) do
    pcall(vim.api.nvim_buf_del_keymap, buf, 'n', m[1])
  end
  pcall(vim.api.nvim_buf_del_keymap, buf, 'n', '<Tab>')
end

-- Show one file in the side-by-side diff. `data` carries everything the view needs:
--   file = { filename, status, patch, ... }
--   base_content, head_content  (strings or nil)
--   threads                     (comment threads for this file)
--   handlers                    (functions bound to the buffer-local keymaps)
function M.show_file(data)
  setup_highlights()

  local ft = vim.filetype.match { filename = data.file.filename } or ''
  local base_lines = to_lines(data.base_content) or { '' }
  local fname = data.file.filename
  -- checkout mode: head side is the real on-disk file (LSP, editable)
  local head_real = data.head_local and data.head_path ~= nil

  local need_layout = not (
    view.tab
    and vim.api.nvim_tabpage_is_valid(view.tab)
    and view.left_win
    and vim.api.nvim_win_is_valid(view.left_win)
    and view.right_win
    and vim.api.nvim_win_is_valid(view.right_win)
  )

  if need_layout then
    vim.cmd 'tabnew'
    view.tab = vim.api.nvim_get_current_tabpage()
    view.left_win = vim.api.nvim_get_current_win()
    vim.cmd 'vsplit'
    view.right_win = vim.api.nvim_get_current_win()
    view.left_buf, view.right_buf, view.right_is_scratch = nil, nil, true
  end

  -- outgoing buffers: wipe only the scratch ones (never a user's real file buffer)
  local old_left, old_right, old_right_scratch = view.left_buf, view.right_buf, view.right_is_scratch

  -- LEFT (base): always a scratch buffer holding the base-side content
  view.left_buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_win_set_buf(view.left_win, view.left_buf)
  buf_setup(view.left_buf, base_lines, ft, 'pr://base/' .. fname)

  -- RIGHT (head): real file in checkout mode, else a scratch buffer
  if head_real then
    vim.api.nvim_win_call(view.right_win, function()
      vim.cmd('edit ' .. vim.fn.fnameescape(data.head_path))
    end)
    view.right_buf = vim.api.nvim_win_get_buf(view.right_win)
    view.right_is_scratch = false
    real_bufs[view.right_buf] = true
  else
    local head_lines = to_lines(data.head_content) or { '' }
    view.right_buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_win_set_buf(view.right_win, view.right_buf)
    buf_setup(view.right_buf, head_lines, ft, 'pr://head/' .. fname)
    view.right_is_scratch = true
  end

  if old_left and old_left ~= view.left_buf and vim.api.nvim_buf_is_valid(old_left) then
    pcall(vim.api.nvim_buf_delete, old_left, { force = true })
  end
  if old_right and old_right ~= view.right_buf and old_right_scratch and vim.api.nvim_buf_is_valid(old_right) then
    pcall(vim.api.nvim_buf_delete, old_right, { force = true })
  end

  ctx = {
    file = data.file,
    threads = data.threads,
    ranges = M.parse_patch(data.file.patch),
  }

  setup_diff_window(view.left_win, diff_ns_base)
  setup_diff_window(view.right_win, diff_ns_head)

  -- mode indicator + context, scoped to the review windows (gone when the tab closes)
  if data.winbar_head then
    pcall(vim.api.nvim_set_option_value, 'winbar', data.winbar_head, { win = view.right_win })
  end
  if data.winbar_base then
    pcall(vim.api.nvim_set_option_value, 'winbar', data.winbar_base, { win = view.left_win })
  end

  apply_keymaps(view.left_buf, data.handlers)
  apply_keymaps(view.right_buf, data.handlers)

  M.render_threads()

  -- focus the head side; that is where most comments land
  vim.api.nvim_set_current_win(view.right_win)
end

-- Update the cached threads (after a post/submit/refresh) and re-render.
function M.set_threads(threads)
  if ctx then
    ctx.threads = threads
    M.render_threads()
  end
end

function M.is_open()
  return view.tab ~= nil and vim.api.nvim_tabpage_is_valid(view.tab)
end

-- Close the review tab and reset all view state.
function M.close()
  -- strip our review keymaps + comment marks from any real file buffers (checkout mode),
  -- so they behave like normal files again after the review closes
  for buf in pairs(real_bufs) do
    if vim.api.nvim_buf_is_valid(buf) then
      clear_keymaps(buf)
      pcall(vim.api.nvim_buf_clear_namespace, buf, ns, 0, -1)
    end
  end
  real_bufs = {}

  if view.tab and vim.api.nvim_tabpage_is_valid(view.tab) then
    pcall(function()
      vim.cmd('tabclose ' .. vim.api.nvim_tabpage_get_number(view.tab))
    end)
  end
  view = { tab = nil, left_win = nil, right_win = nil, left_buf = nil, right_buf = nil, right_is_scratch = true }
  ctx = nil
end

return M
