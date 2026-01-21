return {
  'mfussenegger/nvim-dap',
  dependencies = {
    -- Creates a beautiful debugger UI
    'igorlfs/nvim-dap-view',
    'nvim-neotest/nvim-nio',
    'theHamsta/nvim-dap-virtual-text',

    -- Installs the debug adapters for you
    'williamboman/mason.nvim',
    'jay-babu/mason-nvim-dap.nvim',

    -- Add your own debuggers here
    'leoluz/nvim-dap-go',
    'mfussenegger/nvim-dap-python',
    'Weissle/persistent-breakpoints.nvim',
    -- miscellaneous dependencies
    'nvim-treesitter/nvim-treesitter',
    -- SQLite for persistent REPL history
    'kkharji/sqlite.lua',
  },
  config = function()
    local dap = require 'dap'
    local dap_view = require 'dap-view'

    require('mason-nvim-dap').setup {
      -- Makes a best effort to setup the various debuggers with
      -- reasonable debug configurations
      automatic_setup = true,
      automatic_installation = true,

      -- You can provide additional configuration to the handlers,
      -- see mason-nvim-dap README for more information
      handlers = {},

      -- You'll need to check that you have the required things installed
      -- online, please don't ask me how to install them :)
      ensure_installed = {
        -- Update this to ensure that you have the debuggers for the langs you want
        -- 'delve',
        'python',
        'debugpy',
      },
    }
    require('nvim-dap-virtual-text').setup {
      commented = true,
    }

    -- Workaround for nvim-dap-view extmark bug in breakpoints view
    -- The plugin incorrectly uses source extmark IDs as target IDs, causing "Invalid 'ns_id'" errors
    local extmarks_module = require 'dap-view.breakpoints.util.extmarks'
    local original_copy_extmarks = extmarks_module.copy_extmarks
    extmarks_module.copy_extmarks = function(src_bufnr, src_row, target_row, col_offset)
      local ok, err = pcall(original_copy_extmarks, src_bufnr, src_row, target_row, col_offset)
      if not ok and not tostring(err):match "Invalid 'ns_id'" then
        -- Re-raise non-extmark errors
        error(err)
      end
    end

    require('dap-view').setup {
      winbar = {
        show = true,
        sections = { 'repl', 'breakpoints', 'watches', 'scopes', 'exceptions', 'threads' },
        default_section = 'repl',
        base_sections = {
          breakpoints = {
            keymap = 'b',
            label = '[b]reakpoints',
            short_label = ' [b]',
          },
          scopes = {
            keymap = 's',
            label = '[s]copes',
            short_label = '󰂥 [s]',
          },
          exceptions = {
            keymap = 'e',
            label = '[e]xceptions',
            short_label = '󰢃 [e]',
          },
          watches = {
            keymap = 'w',
            label = '[w]atches',
            short_label = '󰛐 [w]',
          },
          threads = {
            keymap = 't',
            label = '[t]hreads',
            short_label = '󱉯 [t]',
          },
          repl = {
            keymap = 'r',
            label = '[r]EPL',
            short_label = '󰯃 [r]',
          },
          sessions = {
            keymap = 'k',
            label = 'Sessions',
            short_label = ' [k]',
          },
          console = {
            keymap = 'c',
            label = '[c]onsole',
            short_label = '󰆍 [c]',
          },
        },
        custom_sections = {},
        controls = {
          enabled = true,
          position = 'right',
          buttons = {
            'play',
            'step_into',
            'step_over',
            'step_out',
            'step_back',
            'run_last',
            'terminate',
            'disconnect',
          },
          custom_buttons = {},
        },
      },
      windows = {
        size = 0.25,
        position = 'below',
        terminal = {
          size = 0.5,
          position = 'right',
          hide = {},
        },
      },
      icons = {
        disabled = ' ',
        disconnect = '',
        enabled = ' ',
        filter = '󰈲',
        negate = ' ',
        pause = '󰏤',
        play = '▶',
        run_last = '',
        step_back = '',
        step_into = '',
        step_out = '',
        step_over = '',
        terminate = '',
      },
      help = {
        border = 'rounded',
      },
      render = {
        sort_variables = nil,
        threads = {
          format = function(name, lnum, path)
            return {
              { part = name, separator = ' ' },
              { part = path, hl = 'FileName', separator = ':' },
              { part = lnum, hl = 'LineNumber' },
            }
          end,
          align = false,
        },
        breakpoints = {
          format = function(line, lnum, path)
            return {
              { part = path, hl = 'FileName' },
              { part = lnum, hl = 'LineNumber' },
              { part = line, hl = true },
            }
          end,
          align = false,
        },
      },
      -- Controls how to jump when selecting a breakpoint or navigating the stack
      -- Comma separated list, like the built-in 'switchbuf'. See :help 'switchbuf'
      -- Only a subset of the options is available: newtab, useopen, usetab and uselast
      -- Can also be a function that takes the current winnr and the bufnr that will jumped to
      -- If a function, should return the winnr of the destination window
      switchbuf = 'usetab,uselast',
      -- Auto open when a session is started and auto close when all sessions finish
      -- Alternatively, can be a string:
      -- - "keep_terminal": as above, but keeps the terminal when the session finishes
      -- - "open_term": open the terminal when starting a new session, nothing else
      auto_toggle = false,
      -- Reopen dapview when switching to a different tab
      -- Can also be a function to dynamically choose when to follow, by returning a boolean
      -- If a function, receives the name of the adapter for the current session as an argument
      follow_tab = false,
    }

    -- Disable line numbers and status column in dap-view windows
    vim.api.nvim_create_autocmd('FileType', {
      pattern = { 'dap-view', 'dap-view-term', 'dap-repl' },
      callback = function()
        vim.opt_local.number = false
        vim.opt_local.relativenumber = false
        vim.opt_local.signcolumn = 'no'
        vim.opt_local.statuscolumn = ' '
      end,
    })

    require('persistent-breakpoints').setup {
      save_dir = vim.fn.expand '~/.dotfiles/nvim/.config/nvim/lua/plugins/persistent-breakpoints/nvim_checkpoints',
      -- when to load the breakpoints? "BufReadPost" is recommended.
      load_breakpoints_event = 'BufReadPost',
      -- record the performance of different function. run
      -- :lua require('persistent-breakpoints.api').print_perf_data() to see the result.
      perf_record = false,
      -- perform callback when loading a persisted breakpoint
      --- @param opts DAPBreakpointOptions options used to create the breakpoint ({condition, logMessage, hitCondition})
      --- @param buf_id integer the buffer the breakpoint was set on
      --- @param line integer the line the breakpoint was set on
      on_load_breakpoint = nil,
      -- set this to true if the breakpoints are not loaded when you are using a session-like plugin.
      always_reload = true,
    }

    local persistent_breakpoints_api = require 'persistent-breakpoints.api'

    local persistent_breakpoints_group = vim.api.nvim_create_augroup('PersistentBreakpointsRefresh', { clear = true })
    vim.api.nvim_create_autocmd('BufWritePost', {
      group = persistent_breakpoints_group,
      callback = function(args)
        if vim.bo[args.buf].buftype ~= '' then
          return
        end
        if vim.api.nvim_buf_get_name(args.buf) == '' then
          return
        end
        vim.schedule(function()
          persistent_breakpoints_api.load_breakpoints()
        end)
      end,
    })

    vim.fn.sign_define('DapBreakpoint', {
      text = '',
      texthl = 'DiagnosticSignError',
      linehl = '',
      numhl = '',
    })

    vim.fn.sign_define('DapBreakpointCondition', {
      text = '',
      texthl = 'DapBreakpointCondition',
      linehl = '',
      numhl = '',
    })

    vim.fn.sign_define('DapBreakpointRejected', {
      text = '',
      texthl = 'DiagnosticSignError',
      linehl = '',
      numhl = '',
    })

    vim.fn.sign_define('DapStopped', {
      text = '',
      texthl = 'DiagnosticSignWarn',
      linehl = 'Visual',
      numhl = 'DiagnosticSignWarn',
    })

    local last_python_program
    local forced_python_program

    local function current_file_path()
      local name = vim.api.nvim_buf_get_name(0)
      if name and name ~= '' then
        return name
      end
      return vim.fn.expand '%:p'
    end

    local function consume_forced_python_program()
      local program = forced_python_program
      forced_python_program = nil
      return program
    end

    dap.configurations = {
      python = {
        {
          -- The first three options are required by nvim-dap
          type = 'python', -- the type here established the link to the adapter definition: `dap.adapters.python`
          request = 'launch',
          name = 'Launch file',
          repl_lang = 'python',
          console = 'integratedTerminal',

          -- Options below are for debugpy, see https://github.com/microsoft/debugpy/wiki/Debug-configuration-settings for supported options

          program = function()
            return consume_forced_python_program() or current_file_path()
          end,
          pythonPath = function()
            -- debugpy supports launching an application with a different interpreter then the one used to launch debugpy itself.
            -- The code below first respects `VIRTUAL_ENV`, then looks for `venv` or `.venv` folders in the current directory.
            local python_bin = vim.env.VIRTUAL_ENV
            if python_bin and python_bin ~= '' then
              if vim.fn.isdirectory(python_bin) == 1 and vim.fn.executable(python_bin) == 1 then
                return python_bin
              end
            end
            local cwd = vim.fn.getcwd()
            if vim.fn.executable(cwd .. '/venv/bin/python') == 1 then
              return cwd .. '/venv/bin/python'
            elseif vim.fn.executable(cwd .. '/.venv/bin/python') == 1 then
              return cwd .. '/.venv/bin/python'
            else
              return '/usr/bin/python'
            end
          end,
        },
      },
    }

    local function ensure_dap_repl_visible()
      for _, win in ipairs(vim.api.nvim_list_wins()) do
        local buf = vim.api.nvim_win_get_buf(win)
        local ft = vim.bo[buf].filetype
        if ft == 'dap-repl' then
          return
        end
      end
      -- Use vim.schedule to defer opening, avoiding extmark issues
      vim.schedule(function()
        pcall(dap_view.open)
      end)
    end

    local function open_breakpoint_picker()
      local ok, telescope = pcall(require, 'telescope')
      if not ok then
        vim.notify('Telescope is not available', vim.log.levels.ERROR)
        return
      end

      local opened, err = pcall(function()
        telescope.extensions.dap.list_breakpoints {
          layout_strategy = 'cursor',
          layout_config = { width = 0.5, height = 0.4 },
          path_display = { 'truncate' },
        }
      end)

      if not opened then
        vim.notify(('telescope-dap failed: %s'):format(err), vim.log.levels.WARN)
      end
    end

    package.preload.dap_repl_history = function()
      local M = {}

      -- SQLite database setup for persistent history
      local db_path = vim.fn.expand '~/.dotfiles/nvim/.config/nvim/lua/plugins/dap-repl/dap-repl-history.sqlite.db'
      local sqlite_ok, sqlite = pcall(require, 'sqlite')
      local db = nil

      local function init_db()
        if db then
          return db
        end
        if not sqlite_ok then
          return nil
        end

        local db_dir = vim.fn.fnamemodify(db_path, ':h')
        if vim.fn.isdirectory(db_dir) == 0 then
          vim.fn.mkdir(db_dir, 'p')
        end

        db = sqlite {
          uri = db_path,
          repl_history = {
            id = true,
            command = { 'text', required = true, unique = true },
            created_at = { 'integer', required = true },
            last_used_at = { 'integer', required = true },
          },
        }
        return db
      end

      local function cleanup_old_records()
        local database = init_db()
        if not database then
          return
        end

        local three_days_ago = os.time() - (3 * 24 * 60 * 60)
        pcall(function()
          database.repl_history:remove { where = { last_used_at = { '<', three_days_ago } } }
        end)
      end

      local function save_command(command)
        local database = init_db()
        if not database or not command or command == '' then
          return
        end

        local now = os.time()

        local ok, existing = pcall(function()
          return database.repl_history:where { command = command }
        end)

        if ok and existing and existing.id then
          pcall(function()
            database.repl_history:update { where = { id = existing.id }, set = { last_used_at = now } }
          end)
        else
          pcall(function()
            database.repl_history:insert { command = command, created_at = now, last_used_at = now }
          end)
        end
      end

      local function load_all_commands()
        local database = init_db()
        if not database then
          return {}
        end

        cleanup_old_records()

        local ok, rows = pcall(function()
          return database.repl_history:get { order_by = { desc = 'last_used_at' } }
        end)

        if not ok or not rows then
          return {}
        end

        local commands = {}
        for _, row in ipairs(rows) do
          table.insert(commands, row.command)
        end
        return commands
      end

      local function get_dap_repl_bufnr()
        for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
          if vim.api.nvim_buf_is_loaded(bufnr) then
            local ft = vim.bo[bufnr].filetype
            if vim.b[bufnr].dap_repl then
              return bufnr
            end
            if ft == 'dap-repl' or ft == 'dap_repl' then
              return bufnr
            end
            local name = vim.api.nvim_buf_get_name(bufnr)
            if name:match 'DAP REPL' or name:match 'dap%-repl' then
              return bufnr
            end
          end
        end
        return nil
      end

      local function collect_repl_inputs(bufnr)
        local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
        local seen = {}
        local items = {}

        local function trim_empty_edges(parts)
          local first = 1
          local last = #parts
          while first <= last and parts[first] == '' do
            first = first + 1
          end
          while last >= first and parts[last] == '' do
            last = last - 1
          end
          if first > last then
            return {}
          end
          local trimmed = {}
          for idx = first, last do
            table.insert(trimmed, parts[idx])
          end
          return trimmed
        end

        local i = 1
        while i <= #lines do
          local line = lines[i]
          local cmd = line:match '^dap>%s*(.*)$'
          if cmd ~= nil then
            local parts = {}
            table.insert(parts, cmd)
            local j = i + 1
            while j <= #lines do
              if lines[j]:match '^dap>' then
                break
              end
              table.insert(parts, lines[j])
              j = j + 1
            end
            parts = trim_empty_edges(parts)
            local combined = table.concat(parts, '\n')
            if combined ~= '' and not seen[combined] then
              seen[combined] = true
              table.insert(items, combined)
            end
            i = j
          else
            i = i + 1
          end
        end

        return items
      end

      -- Save all commands from current REPL buffer to database
      function M.save_session_history()
        local bufnr = get_dap_repl_bufnr()
        if not bufnr then
          return
        end

        local items = collect_repl_inputs(bufnr)
        for _, cmd in ipairs(items) do
          save_command(cmd)
        end
      end

      function M.pick(opts)
        opts = opts or {}

        -- First, save any commands from current session to database
        M.save_session_history()

        -- Load all persisted commands from database
        local db_items = load_all_commands()

        -- Also collect from current buffer (in case there are new commands not yet saved)
        local bufnr = get_dap_repl_bufnr()
        local session_items = {}
        if bufnr then
          session_items = collect_repl_inputs(bufnr)
        end

        -- Merge: session items first (most recent), then DB items not already in session
        local seen = {}
        local items = {}
        for _, cmd in ipairs(session_items) do
          if not seen[cmd] then
            seen[cmd] = true
            table.insert(items, cmd)
          end
        end
        for _, cmd in ipairs(db_items) do
          if not seen[cmd] then
            seen[cmd] = true
            table.insert(items, cmd)
          end
        end

        if #items == 0 then
          vim.notify('No REPL history found.', vim.log.levels.INFO)
          return
        end

        local ok_telescope = pcall(require, 'telescope')
        if not ok_telescope then
          vim.notify('telescope.nvim is not available.', vim.log.levels.ERROR)
          return
        end

        local pickers = require 'telescope.pickers'
        local finders = require 'telescope.finders'
        local previewers = require 'telescope.previewers'
        local conf = require('telescope.config').values
        local actions = require 'telescope.actions'
        local action_state = require 'telescope.actions.state'
        local dap_module = require 'dap'

        pickers
          .new({}, {
            prompt_title = 'dap repl history',
            results_title = 'results',
            preview_title = 'preview',
            finder = finders.new_table {
              results = items,
              entry_maker = function(entry)
                local first_line = entry:match '([^\n\r]*)' or entry
                return {
                  value = entry,
                  display = first_line,
                  ordinal = entry,
                }
              end,
            },
            sorter = conf.generic_sorter {},
            layout_strategy = 'cursor',
            layout_config = { width = 0.6, height = 20 },
            previewer = previewers.new_buffer_previewer {
              define_preview = function(self, entry, _)
                if not entry or not entry.value then
                  return
                end
                local lines = vim.split(entry.value, '\n', { plain = true })
                vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, lines)
              end,
            },
            attach_mappings = function(prompt_bufnr, _)
              actions.select_default:replace(function()
                actions.close(prompt_bufnr)
                local selection = action_state.get_selected_entry()
                if not selection or not selection.value then
                  return
                end
                -- Save the executed command to database
                save_command(selection.value)
                dap_module.repl.execute(selection.value)
              end)
              return true
            end,
          })
          :find()
      end

      return M
    end

    -- Auto-save REPL history when debug session ends
    dap.listeners.before.event_terminated['dap_repl_history'] = function()
      pcall(function()
        require('dap_repl_history').save_session_history()
      end)
    end

    dap.listeners.before.disconnect['dap_repl_history'] = function()
      pcall(function()
        require('dap_repl_history').save_session_history()
      end)
    end

    -- Basic debugging keymaps, feel free to change to your liking!
    vim.keymap.set('n', '<leader>rb', persistent_breakpoints_api.clear_all_breakpoints, { desc = 'Debug: [R]emove all [B]reakpoints' })
    vim.keymap.set('n', '<F5>', function()
      if vim.bo.filetype == 'python' then
        local path = current_file_path()
        if path and path ~= '' then
          last_python_program = path
        else
          last_python_program = nil
        end
      else
        last_python_program = nil
      end
      dap.continue()
    end, { desc = 'Debug: Start/Continue' })

    vim.keymap.set('n', '<F6>', function()
      local session = dap.session()
      if session and session.config and session.config.type == 'python' and last_python_program then
        forced_python_program = last_python_program
      else
        forced_python_program = nil
      end
      dap.run_last()
    end, { desc = 'Debug: Restart' })
    vim.keymap.set('n', '<F1>', dap.step_into, { desc = 'Debug: Step Into' })
    vim.keymap.set('n', '<F2>', dap.step_out, { desc = 'Debug: Step Out' })
    vim.keymap.set('n', '<F3>', dap.terminate, { desc = 'Debug: Terminate' })
    vim.keymap.set('n', '<F10>', dap.step_over, { desc = 'Debug: Step Over' })
    vim.keymap.set('n', '<leader>b', persistent_breakpoints_api.toggle_breakpoint, { desc = 'Debug: Toggle [B]reakpoint' })
    vim.keymap.set('n', '<leader>B', persistent_breakpoints_api.set_conditional_breakpoint, { desc = 'Debug: Toggle Conditional [B]reakpoint' })
    vim.keymap.set('n', '<leader>bl', persistent_breakpoints_api.set_log_point, { desc = 'Debug: Toggle [L]og Point' })
    vim.keymap.set('n', '<leader>bb', open_breakpoint_picker, { desc = 'Debug: [B]rowse [B]reakpoints' })
    vim.keymap.set('n', '<leader>dh', function()
      require('dap_repl_history').pick()
    end, { desc = 'DAP REPL history (Telescope)' })

    vim.keymap.set('n', '<space>?', function()
      require('dap.ui.widgets').hover(nil, { border = 'rounded' })
    end, { desc = 'Debug: show value in floating box' })

    vim.keymap.set('n', '<leader>dw', dap_view.add_expr, { desc = 'Debug: Add to [W]atch list' })
    vim.keymap.set('x', '<leader>dw', dap_view.add_expr, { desc = 'Debug: Add selection to [W]atch list' })

    vim.keymap.set('x', '<leader>ss', function()
      local lines = vim.fn.getregion(vim.fn.getpos '.', vim.fn.getpos 'v')
      local code = table.concat(lines, '\n')
      -- Execute the code - dap.repl.execute will open the REPL if needed
      vim.schedule(function()
        pcall(dap_view.open)
        vim.defer_fn(function()
          dap.repl.execute(code)
        end, 50)
      end)
    end, { desc = 'Debug: [S]end [S]election to REPL' })

    vim.keymap.set('n', '<leader>gt', function()
      dap.goto_()
    end, { desc = 'Debug: [G]o [T]o cursor' })

    -- Toggle to see last session result. Without this, you can't see session output in case of unhandled exception.
    vim.keymap.set('n', '<F7>', dap_view.toggle, { desc = 'Debug: See last session result.' })

    local function setup_repl_highlights(session)
      if not session then
        return
      end
      -- Find the REPL buffer
      for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
        if vim.api.nvim_buf_is_loaded(bufnr) and vim.bo[bufnr].filetype == 'dap-repl' then
          local lang = session.config and session.config.repl_lang
          if not lang then
            local ok, ts_lang = pcall(vim.treesitter.language.get_lang, session.filetype or '')
            if ok and ts_lang then
              lang = ts_lang
            end
          end
          -- Fallback to python for python adapter
          if not lang and session.config and session.config.type == 'python' then
            lang = 'python'
          end
          if lang then
            require('nvim-dap-repl-highlights').setup_injections(bufnr, lang)
            -- Force parse with injections to trigger highlighting
            local hl = vim.treesitter.highlighter.active[bufnr]
            if hl and hl.tree then
              hl.tree:parse(true)
            end
          end
        end
      end
    end

    dap.listeners.after.event_initialized['dap_view_config'] = function(session)
      dap_view.open()
      -- Setup REPL highlights after a delay to ensure buffer is ready
      vim.defer_fn(function()
        setup_repl_highlights(session)
      end, 200)
    end

    -- Also setup highlights when switching to REPL section (in case it wasn't ready earlier)
    vim.api.nvim_create_autocmd('FileType', {
      pattern = 'dap-repl',
      callback = function()
        vim.defer_fn(function()
          local session = dap.session()
          if session then
            setup_repl_highlights(session)
          end
        end, 100)
      end,
    })

    -- Manual trigger for REPL syntax highlighting (for debugging)
    vim.keymap.set('n', '<leader>dr', function()
      local buf = vim.api.nvim_get_current_buf()
      local ft = vim.bo[buf].filetype

      if ft ~= 'dap-repl' then
        vim.notify('Not in a dap-repl buffer!', vim.log.levels.WARN)
        return
      end

      -- Use the plugin's setup_highlights function
      require('nvim-dap-repl-highlights').setup_highlights('python', buf)

      -- Force parse with injections and redraw
      local hl = vim.treesitter.highlighter.active[buf]
      if hl and hl.tree then
        hl.tree:parse(true)
        vim.cmd 'redraw!'
        vim.notify('REPL highlights applied', vim.log.levels.INFO)
      else
        vim.notify('Highlighter not active', vim.log.levels.WARN)
      end
    end, { desc = 'Debug: [R]efresh REPL highlights' })

    -- Install golang specific config
    -- require('dap-go').setup()
    require('dap-python').setup 'uv'
    require('dap-python').test_runner = 'pytest'

    -- Custom REPL command to pretty-print objects without duplication
    local repl = require 'dap.repl'
    repl.commands = vim.tbl_extend('force', repl.commands, {
      custom_commands = {
        ['.p'] = function(expr)
          if not expr or expr:match '^%s*$' then
            repl.append 'Usage: .p <expression>'
            return
          end
          local wrapped = '__import__("pprint").pprint(' .. expr .. ')'
          repl.execute(wrapped, { context = 'repl', silent = true })
        end,
      },
    })

    -- Override on_output to deduplicate debugpy's duplicate output
    -- debugpy sends both an evaluate response AND an output event for the same content
    local recent_output = {}
    dap.defaults.fallback.on_output = function(session, body)
      if body.category == 'telemetry' then
        return
      end

      local output = body.output
      if not output then
        return
      end

      -- Check if we've seen this exact output very recently (within 100ms)
      local now = vim.uv.now()
      if recent_output[output] and (now - recent_output[output]) < 100 then
        return -- Skip duplicate
      end
      recent_output[output] = now

      -- Clean old entries periodically to avoid memory buildup
      for k, v in pairs(recent_output) do
        if now - v > 1000 then
          recent_output[k] = nil
        end
      end

      repl.append(output, '$', { newline = false })
    end
  end,
}
