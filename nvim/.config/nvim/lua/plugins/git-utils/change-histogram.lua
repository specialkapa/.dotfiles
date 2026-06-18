local M = {}

local MAX_ROWS = 30
local BAR_W = 18
local FILE_W = 50
local DIV = ' │ '
-- lower-half block: bars sit in the bottom of their line, leaving a gap above
-- so vertically-stacked bars read as separate, thinner bands without blank rows
local BAR_CHAR = '▄'

local hl_ns = vim.api.nvim_create_namespace 'GitChangeHistogram'

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

local function get_git_root()
  local file_path = vim.fn.expand '%:p'
  local dir = file_path ~= '' and vim.fn.fnamemodify(file_path, ':h') or vim.fn.getcwd()
  local output = vim.fn.systemlist { 'git', '-C', dir, 'rev-parse', '--show-toplevel' }
  if vim.v.shell_error ~= 0 or not output[1] or output[1] == '' then
    return nil
  end
  return trim(output[1])
end

local function get_base_branch(root)
  local out = vim.fn.systemlist { 'git', '-C', root, 'symbolic-ref', '--short', 'refs/remotes/origin/HEAD' }
  if vim.v.shell_error == 0 and out[1] and out[1] ~= '' then
    return trim(out[1])
  end
  for _, branch in ipairs { 'main', 'master' } do
    vim.fn.systemlist { 'git', '-C', root, 'rev-parse', '--verify', branch }
    if vim.v.shell_error == 0 then
      return branch
    end
  end
  return nil
end

-- Resolve which commit range to chart. Prefer commits unique to the current branch
-- (merge-base(HEAD, base)..HEAD); fall back to the last 90 days when there are none.
local function resolve_range(root)
  local base = get_base_branch(root)
  if base then
    local mb = vim.fn.systemlist { 'git', '-C', root, 'merge-base', 'HEAD', base }
    if vim.v.shell_error == 0 and mb[1] and mb[1] ~= '' then
      local merge_base = trim(mb[1])
      local count = vim.fn.systemlist { 'git', '-C', root, 'rev-list', '--count', merge_base .. '..HEAD' }
      if (tonumber((trim(count[1] or '0'))) or 0) > 0 then
        return { merge_base .. '..HEAD' }, base .. '..HEAD'
      end
    end
  end
  return { '--since=90 days ago' }, 'last 90 days'
end

-- One numstat line == one (commit, file) pair, and a file appears at most once per
-- commit, so the number of numstat rows for a path is its commit count.
local function collect_stats(root, range_args)
  local args = { 'git', '-C', root, 'log', '--no-renames', '--numstat', '--format=%H' }
  for _, a in ipairs(range_args) do
    table.insert(args, a)
  end
  local out = vim.fn.systemlist(args)
  if vim.v.shell_error ~= 0 then
    return nil
  end

  local stats = {}
  for _, line in ipairs(out) do
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
    table.insert(rows, entry)
  end
  table.sort(rows, function(a, b)
    if a.commits ~= b.commits then
      return a.commits > b.commits
    end
    return a.lines > b.lines
  end)
  return rows
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

function M.show_change_histogram()
  local root = get_git_root()
  if not root then
    vim.notify('Not in a git repository', vim.log.levels.ERROR)
    return
  end

  local range_args, range_label = resolve_range(root)
  local rows = collect_stats(root, range_args)
  if not rows then
    vim.notify('Failed to read git history', vim.log.levels.ERROR)
    return
  end
  if #rows == 0 then
    vim.notify('No file changes found for ' .. range_label, vim.log.levels.WARN)
    return
  end

  local total = #rows
  local truncated = total > MAX_ROWS
  if truncated then
    rows = vim.list_slice(rows, 1, MAX_ROWS)
  end

  local max_commits, max_lines, max_label, cw = 0, 0, 4, 1
  for _, r in ipairs(rows) do
    max_commits = math.max(max_commits, r.commits)
    max_lines = math.max(max_lines, r.lines)
    max_label = math.max(max_label, vim.fn.strdisplaywidth(r.path))
    cw = math.max(cw, #tostring(r.commits))
  end
  local fw = math.min(max_label, FILE_W)
  local left_width = cw + 1 + BAR_W

  ensure_hl('GitChangeHistHeat1', { fg = '#56b6c2' }) -- coolest
  ensure_hl('GitChangeHistHeat2', { fg = '#98c379' })
  ensure_hl('GitChangeHistHeat3', { fg = '#e5c07b' })
  ensure_hl('GitChangeHistHeat4', { fg = '#d19a66' })
  ensure_hl('GitChangeHistHeat5', { fg = '#e06c75' }) -- hottest

  local content = {}
  local hls = {}
  local line_to_path = {}

  -- header + separator placeholder (sized once we know the widest line); header is plain text
  content[1] = string.rep(' ', left_width - 7) .. 'commits' .. DIV .. 'file' .. string.rep(' ', math.max(0, fw - 4)) .. DIV .. 'lines'
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

  local origin_win = vim.api.nvim_get_current_win()

  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, content)

  local ui_w, ui_h = vim.o.columns, vim.o.lines
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
      { '(' .. range_label .. ') ', 'GitBlameFloatTitle' },
    },
    title_pos = 'left',
    focusable = true,
  })

  vim.api.nvim_buf_set_option(buf, 'buftype', 'nofile')
  vim.api.nvim_win_set_option(win, 'cursorline', true)
  vim.api.nvim_win_set_option(win, 'cursorcolumn', false)
  vim.api.nvim_win_set_option(win, 'winhl', 'Normal:NormalFloat,FloatBorder:FloatBorder')

  for _, hl in ipairs(hls) do
    vim.hl.range(buf, hl_ns, hl.group, { hl.line0, hl.cs }, { hl.line0, hl.ce }, {})
  end

  vim.api.nvim_buf_set_option(buf, 'modifiable', false)

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

return M
