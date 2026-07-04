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
    vim.g.db_ui_save_location = vim.fn.expand '~/.dotfiles/nvim/.config/nvim/lua/plugins/.data'

    -- Auto-open a sqlite file as a DBUI connection.
    --
    -- When a real SQLite file (*.db / *.sqlite / *.sqlite3) is opened, register it
    -- as a vim-dadbod-ui connection named after the file (if not already present),
    -- fire up the DBUI drawer on the left, and expand the new connection so its
    -- tables are shown immediately.
    local dbui_save_dir = vim.g.db_ui_save_location
    local connections_file = dbui_save_dir .. '/connections.json'

    local function read_connections()
      if vim.fn.filereadable(connections_file) == 0 then
        return {}
      end
      local content = vim.trim(table.concat(vim.fn.readfile(connections_file), '\n'))
      if content == '' then
        return {}
      end
      local ok, data = pcall(vim.fn.json_decode, content)
      if not ok or type(data) ~= 'table' then
        return {}
      end
      return data
    end

    local function write_connections(conns)
      vim.fn.mkdir(dbui_save_dir, 'p')
      -- Match vim-dadbod-ui's own format: a single JSON line.
      vim.fn.writefile({ vim.fn.json_encode(conns) }, connections_file)
    end

    -- Only act on genuine SQLite databases so we don't hijack unrelated *.db files.
    local function is_sqlite_file(path)
      local f = io.open(path, 'rb')
      if not f then
        return false
      end
      local header = f:read(16)
      f:close()
      return header ~= nil and header:sub(1, 15) == 'SQLite format 3'
    end

    -- Ensure a connection for `path` exists. Returns the connection name and
    -- whether it was newly added.
    local function ensure_connection(path)
      local url = 'sqlite:' .. path
      local conns = read_connections()
      local names = {}
      for _, c in ipairs(conns) do
        names[c.name] = true
        if c.url == url then
          return c.name, false
        end
      end
      local base = vim.fn.fnamemodify(path, ':t')
      local name, i = base, 2
      while names[name] do
        name = base .. '_' .. i
        i = i + 1
      end
      table.insert(conns, { name = name, url = url })
      write_connections(conns)
      return name, true
    end

    -- Open the DBUI drawer and expand the connection for `key` (name .. '_file').
    local function open_connection_in_dbui(key, added)
      vim.schedule(function()
        -- Loads the plugin (lazy) if needed and opens the drawer on the left.
        pcall(vim.cmd, 'DBUI')

        -- If we just wrote a new entry and an instance already existed, re-read
        -- the connections file so the drawer picks the connection up.
        if added then
          pcall(vim.cmd, [[call db_ui#drawer#get().render({'dbs': 1})]])
        end

        local ok, drawer = pcall(vim.fn['db_ui#drawer#get'])
        if not ok or type(drawer) ~= 'table' or type(drawer.content) ~= 'table' then
          return
        end

        for line_nr, item in ipairs(drawer.content) do
          if item.type == 'db' and item.dbui_db_key_name == key then
            if vim.bo.filetype ~= 'dbui' then
              pcall(vim.cmd, [[call db_ui#drawer#get().focus()]])
            end
            pcall(vim.api.nvim_win_set_cursor, 0, { line_nr, 0 })
            -- Expand (connect + list tables) only if it isn't already open.
            if item.expanded ~= 1 then
              pcall(vim.cmd, [[execute "normal \<Plug>(DBUI_SelectLine)"]])
            end
            break
          end
        end
      end)
    end

    -- Replace the (binary) sqlite file buffer with an empty scratch buffer so its
    -- contents are never shown, then wipe it. Done synchronously (before redraw)
    -- to avoid flashing the raw bytes.
    local function discard_sqlite_buffer(bufnr)
      local win = vim.fn.bufwinid(bufnr)
      if win ~= -1 then
        pcall(vim.api.nvim_set_current_win, win)
        pcall(vim.cmd, 'enew')
      end
      if vim.api.nvim_buf_is_valid(bufnr) then
        pcall(vim.api.nvim_buf_delete, bufnr, { force = true })
      end
    end

    local function open_sqlite_in_dbui(bufnr, path)
      if vim.bo[bufnr].buftype ~= '' or not is_sqlite_file(path) then
        return
      end

      -- Register the connection (no-op if it already exists).
      local name, added = ensure_connection(path)

      -- Blank the buffer in place so its raw bytes are never rendered, but keep
      -- it valid for the rest of the BufReadPost chain (other handlers, e.g. the
      -- linter, read args.buf after us). Switching it to 'nofile' also stops it
      -- from ever being written back over the database.
      vim.bo[bufnr].modifiable = true
      pcall(vim.api.nvim_buf_set_lines, bufnr, 0, -1, false, {})
      vim.bo[bufnr].modifiable = false
      vim.bo[bufnr].modified = false
      vim.bo[bufnr].buftype = 'nofile'
      vim.bo[bufnr].swapfile = false

      -- Defer the actual removal + DBUI open until the event chain has finished,
      -- so we never invalidate the buffer while another handler is still using it.
      vim.schedule(function()
        discard_sqlite_buffer(bufnr)
        open_connection_in_dbui(name .. '_file', added)
      end)
    end

    vim.api.nvim_create_autocmd('BufReadPost', {
      group = vim.api.nvim_create_augroup('sqlite_auto_dbui', { clear = true }),
      pattern = { '*.db', '*.sqlite', '*.sqlite3' },
      callback = function(args)
        pcall(open_sqlite_in_dbui, args.buf, vim.fn.fnamemodify(args.file, ':p'))
      end,
    })
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
              vim.wo[win].signcolumn = 'no'
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

    -- Delete table functionality for DBUI
    local function get_dbui_item_under_cursor()
      -- Get the drawer instance and current item from DBUI
      local ok, drawer = pcall(vim.fn['db_ui#drawer#get'])
      if not ok or not drawer or vim.tbl_isempty(drawer) then
        return nil
      end

      local content = drawer.content
      if not content then
        return nil
      end

      local line_nr = vim.fn.line '.'
      local item = content[line_nr]
      return item
    end

    local function delete_table_under_cursor()
      local item = get_dbui_item_under_cursor()

      if not item then
        vim.notify('Unable to get DBUI item under cursor', vim.log.levels.WARN)
        return
      end

      -- Check if this is a table item (tables have action='toggle' and are under the Tables section)
      -- The label contains the table name
      local table_name = item.label
      if not table_name or table_name == '' then
        vim.notify('No table name found under cursor', vim.log.levels.WARN)
        return
      end

      -- Get the database key name from the item
      local db_key_name = item.dbui_db_key_name
      if not db_key_name then
        vim.notify('No database connection found for this item', vim.log.levels.ERROR)
        return
      end

      -- Get the connection info (including URL) using DBUI's API
      local conn_info = vim.fn['db_ui#get_conn_info'](db_key_name)
      if not conn_info or not conn_info.url then
        vim.notify('Unable to get database connection URL', vim.log.levels.ERROR)
        return
      end

      local db_url = conn_info.url

      -- Ask for confirmation using vim.fn.confirm
      local choice = vim.fn.confirm(
        string.format('DROP TABLE %s?', table_name),
        '&Yes\n&No',
        2 -- Default to "No"
      )

      if choice ~= 1 then
        vim.notify('Table deletion cancelled', vim.log.levels.INFO)
        return
      end

      local drop_sql = string.format('DROP TABLE %s;', table_name)
      local escaped_url = vim.fn.fnameescape(db_url)
      local cmd = string.format('DB %s %s', escaped_url, drop_sql)

      local ok_exec, err = pcall(vim.cmd, cmd)

      if ok_exec then
        vim.notify(string.format('Table "%s" deleted successfully', table_name), vim.log.levels.INFO)
        -- Refresh DBUI to reflect the change by calling redraw
        vim.schedule(function()
          pcall(vim.cmd, 'call db_ui#drawer#get().redraw()')
        end)
      else
        vim.notify(string.format('Failed to delete table: %s', tostring(err)), vim.log.levels.ERROR)
      end
    end

    -- Set up keymap for DBUI filetype
    vim.api.nvim_create_autocmd('FileType', {
      pattern = 'dbui',
      callback = function(args)
        vim.keymap.set('n', 'D', delete_table_under_cursor, {
          buffer = args.buf,
          desc = 'Delete table under cursor (DROP TABLE)',
        })
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
          vim.wo[winnr].signcolumn = 'no'
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
