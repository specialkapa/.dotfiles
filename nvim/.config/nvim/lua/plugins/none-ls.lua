return {
  'nvimtools/none-ls.nvim',
  dependencies = {
    'nvimtools/none-ls-extras.nvim',
    'jayp0521/mason-null-ls.nvim', -- ensure dependencies are installed,
    'joechrisellis/lsp-format-modifications.nvim',
  },
  event = { 'BufReadPre', 'BufNewFile' },
  config = function()
    local null_ls = require 'null-ls'
    local lsp_format_modifications = require 'lsp-format-modifications'
    local vcs = require 'lsp-format-modifications.vcs'
    local util = require 'lsp-format-modifications.util'
    local formatting = null_ls.builtins.formatting -- to setup formatters
    local diagnostics = null_ls.builtins.diagnostics -- to setup linters

    -- Formatters & linters for mason to install
    require('mason-null-ls').setup {
      ensure_installed = {
        'prettier', -- ts/js formatter
        'eslint_d', -- ts/js linter
        'shfmt', -- Shell formatter
        'checkmake', -- linter for Makefiles
        'stylua', -- lua formatter; Already installed via Mason
        'ruff', -- Python linter and formatter; Already installed via Mason
      },
      automatic_installation = true,
    }

    local sources = {
      diagnostics.checkmake,
      formatting.prettier.with {
        filetypes = { 'html', 'json', 'yaml', 'markdown', 'vimwiki' },
        extra_args = { '--print-width', '100', '--prose-wrap', 'always' },
      },
      formatting.stylua,
      formatting.shfmt.with { args = { '-i', '4' } },
      formatting.terraform_fmt,
      require('none-ls.formatting.ruff').with { extra_args = { '--extend-select', 'I' } },
      require 'none-ls.formatting.ruff_format',
    }

    local augroup = vim.api.nvim_create_augroup('LspFormatting', {})
    null_ls.setup {
      -- debug = true, -- Enable debug mode. Inspect logs with :NullLsLog.
      sources = sources,
      on_attach = function(client, bufnr)
        if client.name ~= 'null-ls' or not client:supports_method 'textDocument/formatting' then
          return
        end

        vim.api.nvim_clear_autocmds { group = augroup, buffer = bufnr }

        local filetype = vim.bo[bufnr].filetype
        if filetype == 'python' then
          local diff_opts = lsp_format_modifications.default_diff_opts

          vim.api.nvim_create_autocmd('BufWritePre', {
            group = augroup,
            buffer = bufnr,
            callback = function()
              if vim.fn.executable 'ruff' == 0 then
                vim.notify('ruff executable not found in PATH; skipped formatting', vim.log.levels.WARN)
                return
              end

              local bufname = vim.api.nvim_buf_get_name(bufnr)
              local vcs_client = vcs.git:new()
              local init_err = vcs_client:init(bufname)
              if init_err ~= nil then
                util.notify(init_err .. ', skipping modified-only formatting', vim.log.levels.WARN)
                return
              end

              local file_info, file_info_err = vcs_client:file_info(bufname)
              if not file_info then
                util.notify('failed to inspect git file info: ' .. file_info_err, vim.log.levels.WARN)
                return
              end

              if not file_info.is_tracked then
                local buf_lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
                local input = table.concat(buf_lines, '\n')
                local output = vim.fn.system({
                  'ruff',
                  'format',
                  '--line-length',
                  '100',
                  '--stdin-filename',
                  bufname == '' and 'stdin.py' or bufname,
                  '-',
                }, input)
                if vim.v.shell_error ~= 0 then
                  vim.notify('ruff format failed: ' .. output, vim.log.levels.ERROR)
                  return
                end
                local formatted_lines = vim.split(output, '\n', { plain = true, trimempty = false })
                vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, formatted_lines)
                return
              end

              if file_info.has_conflicts then
                util.notify('file has merge conflicts; skipping modified-only formatting', vim.log.levels.WARN)
                return
              end

              local comparee_lines, comparee_err = vcs_client:get_comparee_lines(bufname)
              if comparee_err ~= nil then
                util.notify('failed to resolve git base: ' .. comparee_err, vim.log.levels.ERROR)
                return
              end

              local buf_lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
              local buf_content = table.concat(buf_lines, '\n')
              local comparee_content = table.concat(comparee_lines, '\n')

              local modifications = vim.diff(comparee_content, buf_content, diff_opts)
              if not modifications or vim.tbl_isempty(modifications) then
                return
              end

              local allowed_ranges = {}
              for _, hunk in ipairs(modifications) do
                local new_start, new_count = hunk[3], hunk[4]
                if new_count > 0 then
                  table.insert(allowed_ranges, {
                    start_line = new_start,
                    end_line = new_start + new_count - 1,
                  })
                end
              end

              if vim.tbl_isempty(allowed_ranges) then
                return
              end

              local format_cmd = {
                'ruff',
                'format',
                '--line-length',
                '100',
                '--stdin-filename',
                bufname == '' and 'stdin.py' or bufname,
                '-',
              }
              local formatted_output = vim.fn.system(format_cmd, buf_content)
              if vim.v.shell_error ~= 0 then
                vim.notify('ruff format failed: ' .. formatted_output, vim.log.levels.ERROR)
                return
              end

              local formatted_lines = vim.split(formatted_output, '\n', { plain = true, trimempty = false })
              local formatted_content = table.concat(formatted_lines, '\n')

              local formatter_hunks = vim.diff(buf_content, formatted_content, diff_opts)
              if not formatter_hunks or vim.tbl_isempty(formatter_hunks) then
                return
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

              table.sort(formatter_hunks, function(a, b)
                return a[1] > b[1]
              end)

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
                end
              end
            end,
          })
        else
          vim.api.nvim_create_autocmd('BufWritePre', {
            group = augroup,
            buffer = bufnr,
            callback = function()
              vim.lsp.buf.format {
                async = false,
                bufnr = bufnr,
                filter = function(format_client)
                  return format_client.id == client.id
                end,
              }
            end,
          })
        end
      end,
    }
  end,
}
