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
        json = true,
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

          vim.b[bufnr].tabview_opened = true
          local cmd = ('tw %s --theme catppuccin'):format(vim.fn.shellescape(path))

          local ok, toggleterm = pcall(require, 'toggleterm.terminal')
          if ok then
            local term = toggleterm.Terminal:new {
              cmd = cmd,
              direction = 'float',
              close_on_exit = true,
              hidden = true,
            }
            term:open()
          else
            local buf = vim.api.nvim_create_buf(false, true)
            local width = math.floor(vim.o.columns * 0.9)
            local height = math.floor(vim.o.lines * 0.8)
            local row = math.floor((vim.o.lines - height) / 2)
            local col = math.floor((vim.o.columns - width) / 2)
            local win = vim.api.nvim_open_win(buf, true, {
              relative = 'editor',
              width = width,
              height = height,
              row = row,
              col = col,
              style = 'minimal',
              border = 'rounded',
            })
            vim.fn.termopen(cmd, {
              on_exit = function()
                if vim.api.nvim_win_is_valid(win) then
                  vim.api.nvim_win_close(win, true)
                end
                if vim.api.nvim_buf_is_valid(buf) then
                  vim.api.nvim_buf_delete(buf, { force = true })
                end
              end,
            })
            vim.cmd 'startinsert'
          end

          if not vim.bo[bufnr].modified then
            vim.api.nvim_buf_delete(bufnr, { force = true })
          else
            vim.notify('Tabview opened; buffer has unsaved changes so it was kept.', vim.log.levels.WARN)
          end
        end,
      })
    end,
  },
}
