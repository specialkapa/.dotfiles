return {
  'mfussenegger/nvim-lint',
  event = { 'BufReadPre', 'BufNewFile' },
  config = function()
    local lint = require 'lint'

    -- Always-on linters. eslint_d is handled separately below so it only runs in projects
    -- that actually have an eslint config (otherwise eslint_d errors and spams diagnostics).
    lint.linters_by_ft = {
      make = { 'checkmake' },
      go = { 'golangcilint' },
    }

    local eslint_fts = {
      javascript = true,
      javascriptreact = true,
      ['javascript.jsx'] = true,
      typescript = true,
      typescriptreact = true,
      ['typescript.tsx'] = true,
    }

    local eslint_config_files = {
      '.eslintrc',
      '.eslintrc.js',
      '.eslintrc.cjs',
      '.eslintrc.json',
      '.eslintrc.yaml',
      '.eslintrc.yml',
      'eslint.config.js',
      'eslint.config.mjs',
      'eslint.config.cjs',
      'eslint.config.ts',
    }

    local function has_eslint_config(bufnr)
      local fname = vim.api.nvim_buf_get_name(bufnr)
      local dir = fname ~= '' and vim.fn.fnamemodify(fname, ':h') or vim.fn.getcwd()
      return #vim.fs.find(eslint_config_files, { upward = true, path = dir, type = 'file' }) > 0
    end

    local aug = vim.api.nvim_create_augroup('nvim-lint', { clear = true })
    vim.api.nvim_create_autocmd({ 'BufReadPost', 'BufWritePost', 'InsertLeave' }, {
      group = aug,
      callback = function(args)
        local bufnr = args.buf
        if not vim.bo[bufnr].modifiable then
          return
        end

        local ft = vim.bo[bufnr].filetype
        local names = vim.list_extend({}, lint.linters_by_ft[ft] or {})
        if eslint_fts[ft] and has_eslint_config(bufnr) then
          table.insert(names, 'eslint_d')
        end

        if #names > 0 then
          lint.try_lint(names)
        end
      end,
    })
  end,
}
