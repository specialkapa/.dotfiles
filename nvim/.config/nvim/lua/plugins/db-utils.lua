return {
  'kristijanhusak/vim-dadbod-ui',
  dependencies = {
    { 'tpope/vim-dadbod', lazy = true },
    { 'kristijanhusak/vim-dadbod-completion', ft = { 'sql', 'mysql', 'plsql' }, lazy = true }, -- Optional
  },
  cmd = {
    'DBUI',
    'DBUIToggle',
    'DBUIAddConnection',
    'DBUIFindBuffer',
  },
  init = function()
    vim.g.db_ui_use_nerd_fonts = 1
    vim.g.db_ui_save_location = '~/.dotfiles/nvim/.config/nvim/lua/plugins/dbui'
  end,
  config = function()
    local function latest_dbout_file()
      local user = vim.env.USER or ''
      local target_dir = string.format('/tmp/nvim.%s/', user)

      local stat = vim.loop.fs_stat(target_dir)
      if not stat or stat.type ~= 'directory' then
        return nil, string.format('Unable to read %s', target_dir)
      end

      local newest_path, newest_mtime = nil, -1

      local function scan_dir(dir)
        local ok, iter = pcall(vim.fs.dir, dir)
        if not ok then
          return
        end

        for name, type_ in iter do
          local path = dir .. name
          if type_ == 'directory' then
            scan_dir(path .. '/')
          elseif type_ == 'file' and name:sub(-6) == '.dbout' then
            local stat = vim.loop.fs_stat(path)
            local mtime = stat and (stat.mtime and (stat.mtime.sec or stat.mtime) or -1) or -1
            if mtime > newest_mtime then
              newest_mtime = mtime
              newest_path = path
            end
          end
        end
      end

      scan_dir(target_dir)

      if not newest_path then
        return nil, 'No .dbout files found'
      end

      return newest_path
    end

    local function detect_column_spans(separator_line)
      local spans = {}
      local start_idx

      for idx = 1, #separator_line do
        local char = separator_line:sub(idx, idx)
        if char == '-' and not start_idx then
          start_idx = idx
        elseif char ~= '-' and start_idx then
          table.insert(spans, { start = start_idx, finish = idx - 1 })
          start_idx = nil
        end
      end

      if start_idx then
        table.insert(spans, { start = start_idx, finish = #separator_line })
      end

      return spans
    end

    local function slice_line_by_spans(line, spans)
      local values = {}
      for _, span in ipairs(spans) do
        local chunk = line:sub(span.start, span.finish)
        table.insert(values, vim.trim(chunk))
      end
      return values
    end

    local function row_is_empty(row)
      for _, value in ipairs(row) do
        if value ~= '' then
          return false
        end
      end
      return true
    end

    local function parse_dbout_for_csv(path)
      local ok, lines = pcall(vim.fn.readfile, path)
      if not ok then
        return nil, string.format('Unable to read %s', path)
      end

      local header_line, separator_line
      local data_lines = {}

      for _, line in ipairs(lines) do
        if vim.trim(line) ~= '' then
          if not header_line then
            header_line = line
          elseif not separator_line then
            separator_line = line
          else
            local trimmed = vim.trim(line)
            local is_footer = trimmed:match '^%(%d+ rows?%)$'
              or trimmed:match '^Time:'
              or trimmed:match '^%d+ rows? in set'
              or trimmed:match '^%d+ rows? affected'
            if not is_footer then
              table.insert(data_lines, line)
            end
          end
        end
      end

      if not header_line or not separator_line then
        return nil, 'Malformed .dbout file: missing header or separator'
      end

      local spans = detect_column_spans(separator_line)
      if vim.tbl_isempty(spans) then
        return nil, 'Unable to detect columns in .dbout file'
      end

      local rows = { slice_line_by_spans(header_line, spans) }
      for _, line in ipairs(data_lines) do
        local row = slice_line_by_spans(line, spans)
        if not row_is_empty(row) then
          table.insert(rows, row)
        end
      end

      return rows
    end

    local function encode_csv_value(value)
      local str = tostring(value or '')
      local needs_quotes = str:find '[",\n\r]' or str:find '^%s' or str:find '%s$'
      str = str:gsub('"', '""')
      if needs_quotes then
        str = string.format('"%s"', str)
      end
      return str
    end

    local function rows_to_csv_lines(rows)
      local csv_lines = {}
      for _, row in ipairs(rows) do
        local encoded = {}
        for _, value in ipairs(row) do
          table.insert(encoded, encode_csv_value(value))
        end
        table.insert(csv_lines, table.concat(encoded, ','))
      end
      return csv_lines
    end

    local function ensure_dir(path)
      local dir = vim.fn.fnamemodify(path, ':h')
      if dir ~= '' and dir ~= '.' then
        local ok, res = pcall(vim.fn.mkdir, dir, 'p')
        if not ok then
          return false, res
        end
        if res == 0 then
          return false, string.format('Unable to create directory %s', dir)
        end
      end
      return true
    end

    local function write_csv_file(path, csv_lines)
      local ok_dir, dir_err = ensure_dir(path)
      if not ok_dir then
        return nil, dir_err
      end

      local ok, err = pcall(vim.fn.writefile, csv_lines, path)
      if not ok then
        return nil, err
      end

      return path
    end

    vim.api.nvim_create_user_command('DBUILastOutput', function()
      local path, err = latest_dbout_file()
      if not path then
        vim.notify(err, vim.log.levels.WARN)
        return
      end
      vim.notify(path, vim.log.levels.INFO)
    end, { desc = 'Show the most recent vim-dadbod-ui .dbout file' })

    vim.api.nvim_create_user_command('DBUIDumpLastOutputCSV', function()
      local path, err = latest_dbout_file()
      if not path then
        vim.notify(err, vim.log.levels.WARN)
        return
      end

      local rows, parse_err = parse_dbout_for_csv(path)
      if not rows then
        vim.notify(parse_err, vim.log.levels.ERROR)
        return
      end

      local csv_lines = rows_to_csv_lines(rows)
      local cwd = vim.fn.getcwd()
      local suggested = ''
      if cwd and cwd ~= '' then
        local sep = package.config:sub(1, 1)
        suggested = cwd:sub(-1) == sep and cwd or (cwd .. sep)
      end

      vim.schedule(function()
        vim.ui.input({
          prompt = ' save location ',
          default = suggested,
          completion = 'file',
        }, function(input)
          if not input or vim.trim(input) == '' then
            vim.notify('DBUI CSV export canceled', vim.log.levels.WARN)
            return
          end

          local expanded = vim.fn.expand(input)
          local target = vim.fn.fnamemodify(expanded, ':p')
          local saved_path, write_err = write_csv_file(target, csv_lines)
          if not saved_path then
            vim.notify(write_err or 'Unable to write CSV file', vim.log.levels.ERROR)
            return
          end

          vim.notify(string.format('Saved DBUI output to %s', saved_path), vim.log.levels.INFO)
        end)
      end)
    end, { desc = 'Dump the latest vim-dadbod-ui output buffer to CSV' })

    -- Disable line numbers and sign column in DBUI windows
    vim.api.nvim_create_autocmd('FileType', {
      pattern = { 'dbui', 'dbout', 'sql' },
      callback = function(args)
        local bufnr = args.buf
        local bufname = vim.api.nvim_buf_get_name(bufnr)

        -- Check if this is a DBUI-related buffer
        if
          vim.bo[bufnr].filetype == 'dbui'
          or vim.bo[bufnr].filetype == 'dbout'
          or (vim.bo[bufnr].filetype == 'sql' and vim.bo[bufnr].buftype == 'nofile')
          or bufname:match 'dbui://'
          or bufname:match '%.dbout$'
        then
          -- Find all windows displaying this buffer
          for _, win in ipairs(vim.api.nvim_list_wins()) do
            if vim.api.nvim_win_get_buf(win) == bufnr then
              vim.wo[win].number = false
              vim.wo[win].relativenumber = false
              vim.wo[win].signcolumn = 'no'
              vim.wo[win].statuscolumn = ' '
              -- Disable neominimap for this window
              vim.b[bufnr].neominimap_disable = true
              -- Also try to disable via command if available
              pcall(function()
                vim.api.nvim_buf_call(bufnr, function()
                  vim.cmd 'Neominimap BufDisable'
                end)
              end)
            end
          end
        end
      end,
    })

    -- Also handle when windows are created or entered
    vim.api.nvim_create_autocmd({ 'BufWinEnter', 'WinEnter' }, {
      callback = function()
        local bufnr = vim.api.nvim_get_current_buf()
        local winnr = vim.api.nvim_get_current_win()
        local bufname = vim.api.nvim_buf_get_name(bufnr)

        if
          vim.bo[bufnr].filetype == 'dbui'
          or vim.bo[bufnr].filetype == 'dbout'
          or (vim.bo[bufnr].filetype == 'sql' and vim.bo[bufnr].buftype == 'nofile')
          or bufname:match 'dbui://'
          or bufname:match '%.dbout$'
        then
          vim.wo[winnr].number = false
          vim.wo[winnr].relativenumber = false
          vim.wo[winnr].signcolumn = 'no'
          vim.wo[winnr].statuscolumn = ' '
          -- Disable neominimap for this buffer
          vim.b[bufnr].neominimap_disable = true
          -- Also try to disable via command if available
          vim.schedule(function()
            if vim.api.nvim_buf_is_valid(bufnr) and vim.api.nvim_win_is_valid(winnr) then
              pcall(vim.cmd, 'Neominimap BufDisable')
            end
          end)
        end
      end,
    })
  end,
}
