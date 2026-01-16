return {
  {
    'tabview-config',
    dir = vim.fn.stdpath 'config',
    lazy = false,
    config = function()
      local tabview_extensions = {
        parquet = true,
        csv = true,
        tsv = true,
        json = false,
        jsonl = true,
        arrow = true,
        fwf = true,
        db = true,
        sqlite = true,
        xls = true,
        xlsx = true,
        xlsm = true,
        xlsb = true,
      }

      local tabview_group = vim.api.nvim_create_augroup('UserTabview', { clear = true })
      vim.api.nvim_create_autocmd('BufReadPost', {
        group = tabview_group,
        pattern = '*',
        callback = function(args)
          local bufnr = args.buf
          if vim.b[bufnr].tabview_opened then
            return
          end
          if vim.bo[bufnr].buftype ~= '' then
            return
          end
          local path = vim.api.nvim_buf_get_name(bufnr)
          if path == '' then
            return
          end

          local ext = vim.fn.fnamemodify(path, ':e'):lower()
          if not tabview_extensions[ext] then
            return
          end

          if vim.bo[bufnr].modified then
            vim.notify('Tabview skipped; buffer has unsaved changes.', vim.log.levels.WARN)
            return
          end

          vim.b[bufnr].tabview_opened = true
          local cmd = ('tw %s --theme catppuccin'):format(vim.fn.shellescape(path))

          local win = vim.fn.bufwinid(bufnr)
          if win == -1 then
            return
          end

          vim.api.nvim_set_current_win(win)
          vim.cmd 'enew'

          local term_buf = vim.api.nvim_get_current_buf()
          local term_win = vim.api.nvim_get_current_win()
          vim.bo[term_buf].bufhidden = 'wipe'
          vim.wo[term_win].number = false
          vim.wo[term_win].relativenumber = false
          vim.wo[term_win].statuscolumn = ''

          if vim.api.nvim_buf_is_valid(bufnr) then
            vim.api.nvim_buf_delete(bufnr, { force = true })
          end

          vim.fn.termopen(cmd, {
            on_exit = function()
              vim.schedule(function()
                if vim.api.nvim_win_is_valid(term_win) then
                  vim.api.nvim_win_close(term_win, true)
                elseif vim.api.nvim_buf_is_valid(term_buf) then
                  vim.api.nvim_buf_delete(term_buf, { force = true })
                end
              end)
            end,
          })
          vim.cmd 'startinsert'
        end,
      })
    end,
  },
}
