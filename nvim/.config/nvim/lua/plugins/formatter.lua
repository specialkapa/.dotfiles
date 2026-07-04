-- Formatting via conform.nvim, plus a bespoke Python "format only git-modified lines"
-- handler on save.
--
-- Standard filetypes go through conform (async format-after-save). Python is handled
-- separately by the git-hunk logic below, relocated out of the old none-ls setup: it used
-- to run as a null-ls on_attach BufWritePre handler leaning on lsp-format-modifications for
-- the git plumbing. Both dependencies are gone; the VCS logic is reimplemented with direct
-- `git` shell-outs, and the trigger is now an async BufWritePost autocmd (the save itself is
-- non-blocking; ruff runs just after via vim.schedule, then we write the reformatted buffer
-- back to disk under a recursion guard).
--
-- Python behavior preserved exactly:
--   * untracked file           -> full-file `ruff format --line-length 100`
--   * tracked file             -> format the whole file, but only APPLY the formatting
--                                 changes that overlap lines you modified vs the git index
--   * merge conflicts          -> skipped with a warning
--   * import sorting (ruff `I`) -> intentionally NOT run here (matches old behavior; use
--                                 <leader>ri for on-demand import sorting)

local LINE_LENGTH = '100'

-- vim.diff opts: result_type 'indices' yields hunks as {start_a, count_a, start_b, count_b}.
local diff_opts = { result_type = 'indices', algorithm = 'histogram', ignore_whitespace = false }

-- Guard so the write-back below never re-enters the Python handler.
local writing = false

---Run `git -C <dir> <args...>`, returning (stdout, exit_code).
local function git(dir, args)
  local cmd = { 'git', '-C', dir }
  vim.list_extend(cmd, args)
  local out = vim.fn.system(cmd)
  return out, vim.v.shell_error
end

---Minimal VCS info for a buffer's file, replacing lsp-format-modifications.vcs.git.
---@return table|nil info, string|nil err
local function vcs_info(bufname)
  local dir = vim.fn.fnamemodify(bufname, ':h')

  local _, in_tree = git(dir, { 'rev-parse', '--is-inside-work-tree' })
  if in_tree ~= 0 then
    return nil, 'not a git repository'
  end

  local _, tracked_code = git(dir, { 'ls-files', '--error-unmatch', '--', bufname })
  local is_tracked = tracked_code == 0

  local unmerged = git(dir, { 'ls-files', '-u', '--', bufname })
  local has_conflicts = vim.trim(unmerged) ~= ''

  return { dir = dir, is_tracked = is_tracked, has_conflicts = has_conflicts }, nil
end

---Lines of the file as staged in the git index (the comparee), matching the buffer edits
---you've made since your last `git add`.
---@return string[]|nil lines, string|nil err
local function comparee_lines(dir, bufname)
  local rel, rel_code = git(dir, { 'ls-files', '--full-name', '--', bufname })
  if rel_code ~= 0 then
    return nil, 'failed to resolve repo-relative path'
  end
  rel = vim.trim(rel)

  local content, show_code = git(dir, { 'show', ':' .. rel })
  if show_code ~= 0 then
    return nil, 'failed to read git index version'
  end

  content = content:gsub('\n$', '')
  return vim.split(content, '\n', { plain = true }), nil
end

---Format `input` through ruff over stdin. Returns (output, err).
local function ruff_format(input, bufname)
  local output = vim.fn.system({
    'ruff',
    'format',
    '--line-length',
    LINE_LENGTH,
    '--stdin-filename',
    bufname == '' and 'stdin.py' or bufname,
    '-',
  }, input)
  if vim.v.shell_error ~= 0 then
    return nil, output
  end
  return output, nil
end

---Core Python formatter. Mutates the buffer in place; returns true if it changed anything.
---@return boolean changed
local function format_python(bufnr)
  if vim.fn.executable 'ruff' == 0 then
    vim.notify('ruff executable not found in PATH; skipped formatting', vim.log.levels.WARN)
    return false
  end

  local bufname = vim.api.nvim_buf_get_name(bufnr)
  local info, info_err = vcs_info(bufname)
  if not info then
    vim.notify(info_err .. ', skipping modified-only formatting', vim.log.levels.WARN)
    return false
  end

  local buf_lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local buf_content = table.concat(buf_lines, '\n')

  -- Untracked file: no git base to diff against, so format the whole file.
  if not info.is_tracked then
    local output, err = ruff_format(buf_content, bufname)
    if not output then
      vim.notify('ruff format failed: ' .. err, vim.log.levels.ERROR)
      return false
    end
    if output == buf_content then
      return false
    end
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, vim.split(output, '\n', { plain = true, trimempty = false }))
    return true
  end

  if info.has_conflicts then
    vim.notify('file has merge conflicts; skipping modified-only formatting', vim.log.levels.WARN)
    return false
  end

  local base_lines, base_err = comparee_lines(info.dir, bufname)
  if not base_lines then
    vim.notify('failed to resolve git base: ' .. base_err, vim.log.levels.ERROR)
    return false
  end
  local comparee_content = table.concat(base_lines, '\n')

  -- Lines the buffer changed relative to the git index -> the ranges we're allowed to touch.
  local modifications = vim.diff(comparee_content, buf_content, diff_opts)
  if not modifications or vim.tbl_isempty(modifications) then
    return false
  end

  local allowed_ranges = {}
  for _, hunk in ipairs(modifications) do
    local new_start, new_count = hunk[3], hunk[4]
    if new_count > 0 then
      table.insert(allowed_ranges, { start_line = new_start, end_line = new_start + new_count - 1 })
    end
  end
  if vim.tbl_isempty(allowed_ranges) then
    return false
  end

  local formatted_output, fmt_err = ruff_format(buf_content, bufname)
  if not formatted_output then
    vim.notify('ruff format failed: ' .. fmt_err, vim.log.levels.ERROR)
    return false
  end

  local formatted_lines = vim.split(formatted_output, '\n', { plain = true, trimempty = false })
  local formatted_content = table.concat(formatted_lines, '\n')

  local formatter_hunks = vim.diff(buf_content, formatted_content, diff_opts)
  if not formatter_hunks or vim.tbl_isempty(formatter_hunks) then
    return false
  end

  local function overlaps(range_start, range_count)
    local range_end = range_start + math.max(range_count, 1) - 1
    for _, allowed in ipairs(allowed_ranges) do
      if range_end >= allowed.start_line and range_start <= allowed.end_line then
        return true
      end
    end
    return false
  end

  -- Apply bottom-up so earlier edits don't shift the line numbers of later ones.
  table.sort(formatter_hunks, function(a, b)
    return a[1] > b[1]
  end)

  local changed = false
  for _, hunk in ipairs(formatter_hunks) do
    local old_start, old_count, new_start, new_count = hunk[1], hunk[2], hunk[3], hunk[4]
    if overlaps(old_start, old_count) then
      local replacement = {}
      for i = new_start, new_start + new_count - 1 do
        table.insert(replacement, formatted_lines[i] or '')
      end

      local start_idx = old_start - 1
      local end_idx = start_idx + old_count
      vim.api.nvim_buf_set_lines(bufnr, start_idx, end_idx, false, replacement)
      changed = true
    end
  end

  return changed
end

---Silently write the buffer back to disk after an async reformat. `noautocmd` keeps this
---from re-triggering our own BufWritePost handler (or conform/nvim-lint).
local function write_back(bufnr)
  if writing or not vim.api.nvim_buf_is_valid(bufnr) or not vim.bo[bufnr].modified then
    return
  end
  writing = true
  vim.api.nvim_buf_call(bufnr, function()
    vim.cmd 'silent! noautocmd write'
  end)
  writing = false
end

---Register the async Python "format only git-modified lines" autocmd.
local function setup_python_format()
  local augroup = vim.api.nvim_create_augroup('PythonHunkFormat', { clear = true })
  vim.api.nvim_create_autocmd('BufWritePost', {
    group = augroup,
    pattern = '*.py',
    callback = function(args)
      local bufnr = args.buf
      -- Async: the save has already completed, so this never blocks the write.
      vim.schedule(function()
        if writing or not vim.api.nvim_buf_is_valid(bufnr) then
          return
        end
        if format_python(bufnr) then
          write_back(bufnr)
        end
      end)
    end,
  })
end

return {
  'stevearc/conform.nvim',
  event = { 'BufReadPre', 'BufNewFile' },
  cmd = 'ConformInfo',
  config = function()
    require('conform').setup {
      formatters_by_ft = {
        lua = { 'stylua' }, -- reads .stylua.toml
        html = { 'prettier' },
        json = { 'prettier' },
        yaml = { 'prettier' },
        markdown = { 'prettier' },
        vimwiki = { 'prettier' },
        sh = { 'shfmt' },
        terraform = { 'terraform_fmt' },
        -- python: intentionally omitted; handled by the git-hunk autocmd below.
        -- go: intentionally omitted; gopls (gofumpt) handles it in lua/plugins/lsp.lua.
      },
      formatters = {
        prettier = { prepend_args = { '--print-width', '100', '--prose-wrap', 'always' } },
        shfmt = { prepend_args = { '-i', '4' } },
      },
      -- Async: the file saves immediately, the formatter applies just after (BufWritePost).
      -- lsp_format defaults to 'never', so conform never formats python via the ruff LSP.
      format_after_save = { lsp_format = 'never' },
    }

    setup_python_format()
  end,
}
