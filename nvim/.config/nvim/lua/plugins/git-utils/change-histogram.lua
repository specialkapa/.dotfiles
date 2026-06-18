local M = {}

local MAX_ROWS = 30
local BAR_W = 18
local FILE_W = 50 -- initial file-column width cap (the window can be resized wider)
local MIN_FILE_W = 10 -- never shrink the file column below this
local DIV = ' │ '
-- lower-half block: bars sit in the bottom of their line, leaving a gap above
-- so vertically-stacked bars read as separate, thinner bands without blank rows
local BAR_CHAR = '▄'

local hl_ns = vim.api.nvim_create_namespace 'GitChangeHistogram'

-- Per-repo result cache keyed on the HEAD sha, so reopening is instant until you
-- commit. (A moving base branch can make this slightly stale within a session;
-- the next commit invalidates it.)
local cache = {}

local function trim(value)
  if not value then
    return ''
  end
  return (value:gsub('\r', '')):gsub('^%s+', ''):gsub('%s+$', '')
end

local function ensure_hl(name, opts)
  if vim.fn.hlexists(name) == 0 then
    vim.api.nvim_set_hl(0, name, opts)
  end
end

-- Run git asynchronously (off the UI thread). cb(code, stdout, stderr) runs in a
-- fast event context: further run_git/pure-Lua is fine, but editor API must be
-- wrapped in vim.schedule.
local function run_git(args, cb)
  vim.system(vim.list_extend({ 'git' }, args), { text = true }, function(res)
    cb(res.code, res.stdout or '', res.stderr or '')
  end)
end

-- One numstat line == one (commit, file) pair, and a file appears at most once per
-- commit, so the number of numstat rows for a path is its commit count. Lines is
-- the absolute churn (insertions + deletions) summed across those commits.
local function parse_numstat(out)
  local stats = {}
  for line in out:gmatch '[^\n]+' do
    if line:find('\t', 1, true) then
      local add, del, path = line:match '^(%S+)\t(%S+)\t(.+)$'
      if path then
        local entry = stats[path]
        if not entry then
          entry = { path = path, commits = 0, lines = 0 }
          stats[path] = entry
        end
        entry.commits = entry.commits + 1
        entry.lines = entry.lines + (tonumber(add) or 0) + (tonumber(del) or 0)
      end
    end
  end

  local rows = {}
  for _, entry in pairs(stats) do
    rows[#rows + 1] = entry
  end
  table.sort(rows, function(a, b)
    if a.commits ~= b.commits then
      return a.commits > b.commits
    end
    return a.lines > b.lines
  end)
  return rows
end

-- Run `git log --numstat` over a range and hand the parsed rows to cb. If the range
-- is empty and on_empty is given, call that instead (used for the branch->90d fallback).
local function collect_log(root, range_args, label, cb, on_empty)
  local args = { '-C', root, 'log', '--no-renames', '--numstat', '--format=' }
  vim.list_extend(args, range_args)
  run_git(args, function(code, out)
    if code ~= 0 then
      return cb(nil)
    end
    local rows = parse_numstat(out)
    if #rows == 0 and on_empty then
      return on_empty()
    end
    cb { rows = rows, total = #rows, range_label = label }
  end)
end

-- Resolve the base branch (one for-each-ref, robust without origin/HEAD), then chart
-- merge-base(HEAD, base)..HEAD; fall back to the last 90 days when there's no base or
-- no branch-unique commits.
local function resolve_and_collect(root, cb)
  run_git({
    '-C',
    root,
    'for-each-ref',
    '--format=%(refname:short)',
    'refs/remotes/origin/main',
    'refs/remotes/origin/master',
    'refs/heads/main',
    'refs/heads/master',
  }, function(_, out)
    local existing = {}
    for line in (out or ''):gmatch '[^\n]+' do
      existing[trim(line)] = true
    end
    local base
    for _, cand in ipairs { 'origin/main', 'origin/master', 'main', 'master' } do
      if existing[cand] then
        base = cand
        break
      end
    end

    if not base then
      return collect_log(root, { '--since=90 days ago' }, 'last 90 days', cb)
    end

    run_git({ '-C', root, 'merge-base', 'HEAD', base }, function(code, mb_out)
      local merge_base = trim(mb_out)
      if code ~= 0 or merge_base == '' then
        return collect_log(root, { '--since=90 days ago' }, 'last 90 days', cb)
      end
      collect_log(root, { merge_base .. '..HEAD' }, base .. '..HEAD', cb, function()
        collect_log(root, { '--since=90 days ago' }, 'last 90 days', cb)
      end)
    end)
  end)
end

local function make_bar(value, maxval, width)
  if maxval <= 0 or value <= 0 then
    return '', 0
  end
  local cells = math.floor(value / maxval * width + 0.5)
  cells = math.max(1, math.min(width, cells))
  return string.rep(BAR_CHAR, cells), cells
end

-- Pick a heat tier (1=cool .. 5=hot) from a value relative to its column's max.
-- Each bar is colored by its OWN metric so both histograms stay internally honest.
local function heat_group(value, maxval)
  if maxval <= 0 then
    return 'GitChangeHistHeat1'
  end
  local tier = math.max(1, math.min(5, math.ceil(value / maxval * 5)))
  return 'GitChangeHistHeat' .. tier
end

-- Left-truncate long paths with an ellipsis so the basename stays visible.
local function fit_label(path, width)
  local cells = vim.fn.strdisplaywidth(path)
  if cells <= width then
    return path, cells
  end
  local s = path
  while #s > 1 and vim.fn.strdisplaywidth('…' .. s) > width do
    s = s:sub(2)
  end
  s = '…' .. s
  return s, vim.fn.strdisplaywidth(s)
end

-- Build and show the float from already-computed data. Runs on the main thread.
local function render(root, origin_win, data)
  local rows = data.rows
  local total = data.total
  local truncated = total > MAX_ROWS

  local max_commits, max_lines, max_label, cw, lines_w = 0, 0, 4, 1, 1
  for _, r in ipairs(rows) do
    max_commits = math.max(max_commits, r.commits)
    max_lines = math.max(max_lines, r.lines)
    max_label = math.max(max_label, vim.fn.strdisplaywidth(r.path))
    cw = math.max(cw, #tostring(r.commits))
    lines_w = math.max(lines_w, #tostring(r.lines))
  end
  local left_width = cw + 1 + BAR_W
  local div_w = vim.fn.strdisplaywidth(DIV)
  -- everything on a data row except the file column (so file width = total - fixed)
  local fixed_w = left_width + div_w + div_w + BAR_W + 1 + lines_w

  ensure_hl('GitChangeHistHeat1', { fg = '#56b6c2' }) -- coolest
  ensure_hl('GitChangeHistHeat2', { fg = '#98c379' })
  ensure_hl('GitChangeHistHeat3', { fg = '#e5c07b' })
  ensure_hl('GitChangeHistHeat4', { fg = '#d19a66' })
  ensure_hl('GitChangeHistHeat5', { fg = '#e06c75' }) -- hottest

  local line_to_path = {} -- line number -> path; layout is stable so this is constant

  -- Build the buffer content + highlights for a given file-column width.
  local function layout(fw)
    local content, hls = {}, {}

    -- header + separator placeholder (sized once we know the widest line); header is plain text
    content[1] = string.rep(' ', left_width - 7) .. 'commits' .. DIV .. 'file' .. string.rep(' ', math.max(0, fw - 4)) .. DIV .. 'absolute lines'
    content[2] = ''

    for _, r in ipairs(rows) do
      local parts, b = {}, 0
      local line0 = #content -- content index of the row we are about to insert (0-based line)
      local function push(text, group)
        if group and #text > 0 then
          table.insert(hls, { line0 = line0, group = group, cs = b, ce = b + #text })
        end
        parts[#parts + 1] = text
        b = b + #text
      end

      local commit_hl = heat_group(r.commits, max_commits)
      local lines_hl = heat_group(r.lines, max_lines)

      -- number and bar share the heat tier; file column is plain text
      push(string.format('%' .. cw .. 'd', r.commits), commit_hl)
      push ' '
      local lbar, lcells = make_bar(r.commits, max_commits, BAR_W)
      push(string.rep(' ', BAR_W - lcells))
      push(lbar, commit_hl)
      push(DIV)
      local label, lblcells = fit_label(r.path, fw)
      push(label)
      push(string.rep(' ', fw - lblcells))
      push(DIV)
      local rbar, rcells = make_bar(r.lines, max_lines, BAR_W)
      push(rbar, lines_hl)
      push(string.rep(' ', BAR_W - rcells))
      push ' '
      push(tostring(r.lines), lines_hl)

      content[#content + 1] = table.concat(parts)
      line_to_path[#content] = root .. '/' .. r.path
    end

    -- widest content line so far (header + data rows), used to right-align the legend
    local content_maxw = 0
    for _, line in ipairs(content) do
      content_maxw = math.max(content_maxw, vim.fn.strdisplaywidth(line))
    end

    content[#content + 1] = '' -- separator placeholder; sized once maxw is known
    local footer_sep_line = #content

    local controls = ' <CR> open file   q/<Esc> close'
    if truncated then
      controls = controls .. string.format('   (top %d of %d)', MAX_ROWS, total)
    end
    -- full-height block so the swatch lines up vertically with the surrounding text;
    -- the legend is pushed to the far right of the footer row
    local legend_lead = 'less '
    local legend = legend_lead .. string.rep('█', 5) .. ' more '
    local legend_w = vim.fn.strdisplaywidth(legend)
    local controls_w = vim.fn.strdisplaywidth(controls)
    local target_w = math.max(content_maxw, controls_w + 1 + legend_w)
    local pad = target_w - controls_w - legend_w
    local help = controls .. string.rep(' ', pad) .. legend
    content[#content + 1] = help
    local help_line0 = #content - 1
    local swatch_start = #controls + pad + #legend_lead
    for i = 1, 5 do
      local cs = swatch_start + (i - 1) * #'█'
      table.insert(hls, { line0 = help_line0, group = 'GitChangeHistHeat' .. i, cs = cs, ce = cs + #'█' })
    end

    local maxw = 0
    for _, line in ipairs(content) do
      maxw = math.max(maxw, vim.fn.strdisplaywidth(line))
    end
    content[2] = string.rep('─', maxw)
    content[footer_sep_line] = string.rep('─', maxw)

    return content, hls, maxw
  end

  -- file-column width that fills a given inner window width, clamped to a floor and
  -- to the longest path (no point growing past full paths)
  local function fw_for(inner_w)
    return math.max(MIN_FILE_W, math.min(max_label, inner_w - fixed_w))
  end

  local buf = vim.api.nvim_create_buf(false, true)

  local function set_buf(content, hls)
    vim.api.nvim_buf_set_option(buf, 'modifiable', true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, content)
    vim.api.nvim_buf_clear_namespace(buf, hl_ns, 0, -1)
    for _, hl in ipairs(hls) do
      vim.hl.range(buf, hl_ns, hl.group, { hl.line0, hl.cs }, { hl.line0, hl.ce }, {})
    end
    vim.api.nvim_buf_set_option(buf, 'modifiable', false)
  end

  local ui_w, ui_h = vim.o.columns, vim.o.lines
  -- start at the preferred width, but shrink to fit the screen so nothing overflows
  local init_fw = math.min(math.min(max_label, FILE_W), math.max(MIN_FILE_W, (ui_w - 4) - fixed_w))
  local content, hls, maxw = layout(init_fw)
  set_buf(content, hls)

  local win_w = math.min(maxw, ui_w - 4)
  local win_h = math.min(#content, ui_h - 4)

  local win = vim.api.nvim_open_win(buf, true, {
    relative = 'editor',
    width = win_w,
    height = win_h,
    row = math.floor((ui_h - win_h) / 2 - 1),
    col = math.floor((ui_w - win_w) / 2),
    style = 'minimal',
    border = { '╭', '─', '╮', '│', '╯', '─', '╰', '│' },
    title = {
      -- reuse the git blame float title colors for a consistent look
      { ' 󰊢 ', 'GitBlameFloatTitleIcon' },
      { 'git change histogram ', 'GitBlameFloatTitle' },
      { '(' .. data.range_label .. ') ', 'GitBlameFloatTitle' },
    },
    title_pos = 'left',
    focusable = true,
  })

  vim.api.nvim_buf_set_option(buf, 'buftype', 'nofile')
  vim.api.nvim_win_set_option(win, 'cursorline', true)
  vim.api.nvim_win_set_option(win, 'cursorcolumn', false)
  vim.api.nvim_win_set_option(win, 'winhl', 'Normal:NormalFloat,FloatBorder:FloatBorder')

  -- re-flow the table when the window width changes (e.g. arrow-key resizing),
  -- growing the file column so long paths stop being truncated
  local last_width = win_w
  vim.api.nvim_create_autocmd('WinResized', {
    group = vim.api.nvim_create_augroup('GitChangeHistResize_' .. win, { clear = true }),
    callback = function()
      if not vim.api.nvim_win_is_valid(win) then
        return true -- window gone: delete this autocmd
      end
      local inner_w = vim.api.nvim_win_get_width(win)
      if inner_w == last_width then
        return
      end
      last_width = inner_w
      set_buf(layout(fw_for(inner_w)))
    end,
  })

  -- park the cursor on the first file row so j/k and <CR> work immediately
  if line_to_path[3] then
    pcall(vim.api.nvim_win_set_cursor, win, { 3, 0 })
  end

  for _, key in ipairs { 'q', '<Esc>' } do
    vim.api.nvim_buf_set_keymap(buf, 'n', key, '', {
      noremap = true,
      silent = true,
      callback = function()
        if vim.api.nvim_win_is_valid(win) then
          vim.api.nvim_win_close(win, true)
        end
      end,
    })
  end

  vim.api.nvim_buf_set_keymap(buf, 'n', '<CR>', '', {
    noremap = true,
    silent = true,
    callback = function()
      local lnum = vim.api.nvim_win_get_cursor(win)[1]
      local path = line_to_path[lnum]
      if not path then
        return
      end
      if vim.fn.filereadable(path) == 0 then
        vim.notify('File no longer exists: ' .. path, vim.log.levels.WARN)
        return
      end
      if vim.api.nvim_win_is_valid(win) then
        vim.api.nvim_win_close(win, true)
      end
      if origin_win and vim.api.nvim_win_is_valid(origin_win) then
        vim.api.nvim_set_current_win(origin_win)
      end
      vim.cmd.edit(vim.fn.fnameescape(path))
    end,
  })
end

function M.show_change_histogram()
  local file_path = vim.fn.expand '%:p'
  local dir = file_path ~= '' and vim.fn.fnamemodify(file_path, ':h') or vim.fn.getcwd()
  local origin_win = vim.api.nvim_get_current_win()

  -- notify only if the work outlasts this delay (no toast on fast paths / cache hits)
  local done = false
  vim.defer_fn(function()
    if not done then
      vim.notify('Computing change histogram…', vim.log.levels.INFO, { title = 'git change histogram' })
    end
  end, 120)

  local function finish(fn)
    vim.schedule(function()
      done = true
      fn()
    end)
  end

  -- one spawn for both the repo root and the HEAD sha (cache key)
  run_git({ '-C', dir, 'rev-parse', '--show-toplevel', 'HEAD' }, function(_, out)
    local lines = vim.split(out, '\n', { trimempty = true })
    local root = lines[1] and trim(lines[1]) or ''
    if root == '' then
      return finish(function()
        vim.notify('Not in a git repository', vim.log.levels.ERROR)
      end)
    end
    local head = lines[2] and trim(lines[2]) or ''

    local cached = cache[root]
    if head ~= '' and cached and cached.head == head then
      return finish(function()
        render(root, origin_win, cached.data)
      end)
    end

    resolve_and_collect(root, function(data)
      if not data then
        return finish(function()
          vim.notify('Failed to read git history', vim.log.levels.ERROR)
        end)
      end
      if data.total == 0 then
        return finish(function()
          vim.notify('No file changes found for ' .. data.range_label, vim.log.levels.WARN)
        end)
      end
      local display = {
        rows = vim.list_slice(data.rows, 1, MAX_ROWS),
        total = data.total,
        range_label = data.range_label,
      }
      if head ~= '' then
        cache[root] = { head = head, data = display }
      end
      finish(function()
        render(root, origin_win, display)
      end)
    end)
  end)
end

return M
