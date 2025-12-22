return {
  'mfussenegger/nvim-dap',
  dependencies = {
    -- Creates a beautiful debugger UI
    'rcarriga/nvim-dap-ui',
    'nvim-neotest/nvim-nio',
    'theHamsta/nvim-dap-virtual-text',
    'LiadOz/nvim-dap-repl-highlights',

    -- Installs the debug adapters for you
    'williamboman/mason.nvim',
    'jay-babu/mason-nvim-dap.nvim',

    -- Add your own debuggers here
    'leoluz/nvim-dap-go',
    'mfussenegger/nvim-dap-python',
    'Weissle/persistent-breakpoints.nvim',
  },
  config = function()
    local dap = require 'dap'

    -- Preload our patched dapui REPL element so nvim-dap-ui picks it up
    -- before it tries to require the module during setup.
    pcall(require, 'dapui.elements.repl')

    local dapui = require 'dapui'

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
    require('nvim-dap-repl-highlights').setup()
    require('persistent-breakpoints').setup {
      save_dir = vim.fn.stdpath 'data' .. '/nvim_checkpoints',
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
      text = '', -- or "→"
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
        if ft == 'dapui_repl' or ft == 'dap-repl' then
          return
        end
      end

      local ok, dapui_module = pcall(require, 'dapui')
      if ok then
        dapui_module.open { reset = false }
      else
        dap.repl.open()
      end
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
    vim.keymap.set('n', '<F10>', dap.step_over, { desc = 'Debug: Step Over' })
    vim.keymap.set('n', '<leader>b', persistent_breakpoints_api.toggle_breakpoint, { desc = 'Debug: Toggle [B]reakpoint' })
    vim.keymap.set('n', '<leader>B', persistent_breakpoints_api.set_conditional_breakpoint, { desc = 'Debug: Toggle Conditional [B]reakpoint' })
    vim.keymap.set('n', '<leader>bl', persistent_breakpoints_api.set_log_point, { desc = 'Debug: Toggle [L]og Point' })
    vim.keymap.set('n', '<leader>bb', open_breakpoint_picker, { desc = 'Debug: [B]rowse [B]reakpoints' })

    vim.keymap.set('n', '<space>?', function()
      require('dapui').eval(nil, { enter = true })
    end, { desc = 'Debug: show value in floating box' })

    vim.keymap.set('x', '<leader>ss', function()
      local lines = vim.fn.getregion(vim.fn.getpos '.', vim.fn.getpos 'v')
      ensure_dap_repl_visible()
      dap.repl.execute(table.concat(lines, '\n'))
    end, { desc = 'Debug: [S]end [S]election to REPL' })

    vim.keymap.set('n', '<leader>gt', function()
      dap.goto_()
    end, { desc = 'Debug: [G]o [T]o cursor' })

    -- Dap UI setup
    -- For more information, see |:help nvim-dap-ui|
    dapui.setup {
      -- Set icons to characters that are more likely to work in every terminal.
      --    Feel free to remove or use ones that you like more! :)
      --    Don't feel like these are good choices.
      icons = { expanded = '▾', collapsed = '▸', current_frame = '*' },
      controls = {
        icons = {
          pause = '󰏤',
          play = '▶',
          step_into = '',
          step_over = '',
          step_out = '',
          step_back = '',
          run_last = '',
          terminate = '',
          disconnect = '⏏',
        },
      },
      layouts = {
        {
          elements = {
            { id = 'scopes', size = 0.25 },
            'breakpoints',
            'stacks',
            'watches',
          },
          size = 40,
          position = 'left',
        },
        {
          elements = {
            { id = 'repl', size = 1.0 },
          },
          size = 25,
          position = 'bottom',
        },
      },
    }

    -- Remove line numbers from DAP UI windows. Some panes re-enable them, so guard on multiple events.
    local function strip_dapui_numbers(win)
      pcall(vim.api.nvim_win_set_option, win, 'statuscolumn', '')
      pcall(vim.api.nvim_win_set_option, win, 'number', false)
      pcall(vim.api.nvim_win_set_option, win, 'relativenumber', false)
    end
    local dapui_filetypes = {
      dapui_scopes = true,
      dapui_breakpoints = true,
      dapui_stacks = true,
      dapui_watches = true,
      dapui_console = true,
      dapui_repl = true,
      ['dap-repl'] = true,
      dapui_hover = true,
    }

    vim.api.nvim_create_autocmd({ 'FileType', 'BufWinEnter', 'WinEnter', 'TermEnter' }, {
      callback = function(args)
        local ft = vim.bo[args.buf].filetype
        if not dapui_filetypes[ft] then
          return
        end
        strip_dapui_numbers(args.win or vim.api.nvim_get_current_win())
      end,
    })

    -- Toggle to see last session result. Without this, you can't see session output in case of unhandled exception.
    vim.keymap.set('n', '<F7>', dapui.toggle, { desc = 'Debug: See last session result.' })

    local function close_dapui()
      dapui.close()
    end

    local last_stop_reason

    dap.listeners.after.event_initialized['dapui_config'] = function()
      last_stop_reason = nil
      dapui.open()
    end

    dap.listeners.after.event_stopped['dapui_config'] = function(_, body)
      last_stop_reason = body and body.reason or nil
    end

    local function close_if_not_exception()
      if last_stop_reason ~= 'exception' then
        close_dapui()
      end
    end

    dap.listeners.before.event_terminated['dapui_config'] = close_if_not_exception
    dap.listeners.before.event_exited['dapui_config'] = close_if_not_exception

    -- Install golang specific config
    -- require('dap-go').setup()
    require('dap-python').setup 'uv'
    require('dap-python').test_runner = 'pytest'
  end,
}
