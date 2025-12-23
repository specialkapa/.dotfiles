return {
  {
    -- Automatic refactoring of workspace imports on python file/dir move/rename.
    -- Automatic missing import resolution for sumbol under cursor.
    'alexpasmantier/pymple.nvim',
    -- TODO:: document fd (brew), cargo (rust) and grip-grab (cargo) dependencies
    dependencies = {
      'nvim-lua/plenary.nvim',
      'MunifTanjim/nui.nvim',
      'nvim-treesitter/nvim-treesitter',
      -- optional (nicer ui)
      'stevearc/dressing.nvim',
      'nvim-tree/nvim-web-devicons',
    },
    build = ':PympleBuild',
    config = function()
      require('pymple').setup {
        -- options for the update imports feature
        update_imports = {
          -- the filetypes on which to run the update imports command
          -- NOTE: this should at least include "python" for the plugin to
          -- actually do anything useful
          filetypes = { 'python', 'markdown' },
        },
        -- options for the add import for symbol under cursor feature
        add_import_to_buf = {
          -- whether to autosave the buffer after adding the import (which will
          -- automatically format/sort the imports if you have on-save autocommands)
          autosave = false,
        },
        -- automatically register the following keymaps on plugin setup
        keymaps = {
          -- Resolves import for symbol under cursor.
          -- This will automatically find and add the corresponding import to
          -- the top of the file (below any existing doctsring)
          resolve_import_under_cursor = {
            desc = 'Resolve import under cursor',
            keys = '<leader>li', -- feel free to change this to whatever you like
          },
        },
        -- logging options
        logging = {
          -- whether to log to the neovim console (only use this for debugging
          -- as it might quickly ruin your neovim experience)
          console = {
            enabled = false,
          },
          -- whether or not to log to a file (default location is nvim's
          -- stdpath("data")/pymple.vlog which will typically be at
          -- `~/.local/share/nvim/pymple.vlog` on unix systems)
          file = {
            enabled = true,
            -- the maximum number of lines to keep in the log file (pymple will
            -- automatically manage this for you so you don't have to worry about
            -- the log file getting too big)
            max_lines = 1000,
            -- use stdpath to ensure the log directory always exists/expands
            path = vim.fn.stdpath 'data' .. '/pymple.vlog',
          },
          -- the log level to use
          -- (one of "trace", "debug", "info", "warn", "error", "fatal")
          level = 'info',
        },
        -- python options:
        python = {
          -- the names of root markers to look out for when discovering a project
          root_markers = { 'pyproject.toml', 'setup.py', '.git', 'manage.py' },
          -- the names of virtual environment folders to look out for when
          -- discovering a project
          virtual_env_names = { '.venv' },
        },
      }
    end,
  },
  {
    'numirias/semshi',
    ft = { 'python' },
    build = ':UpdateRemotePlugins',
    config = function()
      vim.g['semshi#active'] = 1
      vim.g['semshi#always_update_all_highlights'] = 1
      vim.g['semshi#excluded_hl_groups'] = { 'imported' }

      local function apply_semshi_highlights()
        local palettes_ok, palettes = pcall(require, 'catppuccin.palettes')
        if not palettes_ok then
          return
        end

        local flavour = vim.g.catppuccin_flavour or 'mocha'
        local palette = palettes.get_palette(flavour)
        if not palette then
          return
        end

        vim.api.nvim_set_hl(0, 'semshiLocal', { fg = palette.lavender })
        vim.api.nvim_set_hl(0, 'semshiGlobal', { fg = palette.blue })
        vim.api.nvim_set_hl(0, 'semshiParameter', { fg = palette.maroon })
        vim.api.nvim_set_hl(0, 'semshiParameterUnused', { fg = palette.overlay1, italic = true })
        vim.api.nvim_set_hl(0, 'semshiFree', { fg = palette.peach })
        vim.api.nvim_set_hl(0, 'semshiBuiltin', { fg = palette.teal })
        vim.api.nvim_set_hl(0, 'semshiAttribute', { fg = palette.mauve })
        vim.api.nvim_set_hl(0, 'semshiSelf', { fg = palette.flamingo })
        vim.api.nvim_set_hl(0, 'semshiUnresolved', { fg = palette.red, underline = true })
        vim.api.nvim_set_hl(0, 'semshiSelected', { fg = palette.sky, bold = true })
        vim.api.nvim_set_hl(0, 'semshiError', { fg = palette.red, bold = true, underline = true })
        vim.api.nvim_set_hl(0, 'semshiDocstring', { fg = palette.green, italic = true })
      end

      apply_semshi_highlights()

      local highlight_group = vim.api.nvim_create_augroup('SemshiCatppuccinHighlights', { clear = true })
      vim.api.nvim_create_autocmd('ColorScheme', {
        group = highlight_group,
        callback = apply_semshi_highlights,
      })

      local enable_group = vim.api.nvim_create_augroup('SemshiPythonAutoEnable', { clear = true })
      vim.api.nvim_create_autocmd('FileType', {
        group = enable_group,
        pattern = 'python',
        callback = function()
          pcall(vim.cmd, 'Semshi enable')
        end,
      })
    end,
  },
  {
    'smzm/hydrovim',
    dependencies = { 'MunifTanjim/nui.nvim' },
    -- optional: lazy-load when F8 is pressed
    keys = { '<F8>' },
  },
  {
    'Vigemus/iron.nvim',
    config = function()
      local iron = require 'iron.core'
      local view = require 'iron.view'
      local common = require 'iron.fts.common'
      local dap = require 'dap'

      iron.setup {
        config = {
          -- Whether a repl should be discarded or not
          scratch_repl = true,
          -- Your repl definitions come here
          repl_definition = {
            sh = {
              -- Can be a table or a function that
              -- returns a table (see below)
              command = { 'bash' },
            },
            python = {
              command = { 'ipython', '--no-autoindent' }, -- or { "ipython", "--no-autoindent" }
              format = common.bracketed_paste_python,
              block_dividers = { '# %%', '#%%' },
              env = { PYTHON_BASIC_REPL = '1' }, -- this is needed for python3.13 and up.
            },
          },
          -- set the file type of the newly created repl to ft
          -- bufnr is the buffer id of the REPL and ft is the filetype of the
          -- language being used for the REPL.
          repl_filetype = function(bufnr, ft)
            return ft
            -- or return a string name such as the following
            -- return "iron"
          end,
          -- Send selections to the DAP repl if an nvim-dap session is running.
          dap_integration = true,
          -- How the repl window will be displayed
          -- See below for more information
          repl_open_cmd = view.split.vertical.botright(0.61903398875),

          -- repl_open_cmd can also be an array-style table so that multiple
          -- repl_open_commands can be given.
          -- When repl_open_cmd is given as a table, the first command given will
          -- be the command that `IronRepl` initially toggles.
          -- Moreover, when repl_open_cmd is a table, each key will automatically
          -- be available as a keymap (see `keymaps` below) with the names
          -- toggle_repl_with_cmd_1, ..., toggle_repl_with_cmd_k
          -- For example,
          --
          -- repl_open_cmd = {
          --   view.split.vertical.rightbelow("%40"), -- cmd_1: open a repl to the right
          --   view.split.rightbelow("%25") -- cmd_2: open a repl below
          -- }
        },
        -- Iron doesn't set keymaps by default anymore.
        -- You can set them here or manually add keymaps to the functions in iron.core
        keymaps = {
          toggle_repl = '<space>rr', -- toggles the repl open and closed.
          -- If repl_open_command is a table as above, then the following keymaps are
          -- available
          -- toggle_repl_with_cmd_1 = '<space>rv',
          -- toggle_repl_with_cmd_2 = '<space>rh',
          restart_repl = '<space>rR', -- calls `IronRestart` to restart the repl
          send_motion = '<space>sc',
          visual_send = '<space>sc',
          send_file = '<space>sff',
          send_line = '<space>sl',
          send_paragraph = '<space>sp',
          send_until_cursor = '<space>su',
          send_mark = '<space>sm',
          send_code_block = '<space>sb',
          send_code_block_and_move = '<space>sn',
          mark_motion = '<space>mc',
          mark_visual = '<space>mc',
          remove_mark = '<space>md',
          cr = '<space>s<cr>',
          interrupt = '<space>s<space>',
          exit = '<space>sq',
          clear = '<space>cl',
        },
        -- If the highlight is on, you can change how it looks
        -- For the available options, check nvim_set_hl
        highlight = {
          italic = true,
        },
        ignore_blank_lines = true, -- ignore blank lines when sending visual select lines
      }

      local function disable_python_repl_numbers(bufnr)
        for _, win in ipairs(vim.api.nvim_list_wins()) do
          if vim.api.nvim_win_get_buf(win) == bufnr then
            vim.api.nvim_set_option_value('number', false, { win = win })
            vim.api.nvim_set_option_value('relativenumber', false, { win = win })
            vim.api.nvim_set_option_value('statuscolumn', ' ', { win = win })
          end
        end
      end

      local repl_number_group = vim.api.nvim_create_augroup('IronPythonReplNumbers', { clear = true })

      vim.api.nvim_create_autocmd('TermOpen', {
        group = repl_number_group,
        pattern = 'term://*ipython*',
        callback = function(event)
          vim.api.nvim_buf_set_var(event.buf, 'iron_python_repl', true)
          disable_python_repl_numbers(event.buf)
        end,
      })

      vim.api.nvim_create_autocmd({ 'BufWinEnter', 'WinEnter' }, {
        group = repl_number_group,
        callback = function(event)
          local ok, is_repl = pcall(vim.api.nvim_buf_get_var, event.buf, 'iron_python_repl')
          if ok and is_repl then
            disable_python_repl_numbers(event.buf)
          end
        end,
      })

      -- iron also has a list of commands, see :h iron-commands for all available commands
      vim.keymap.set('n', '<space>rf', '<cmd>IronFocus<cr>')
      vim.keymap.set('n', '<space>rh', '<cmd>IronHide<cr>')

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

      local iron_dap = require 'iron.dap'
      iron_dap.send_to_dap = function(lines)
        local text
        if type(lines) == 'table' then
          text = table.concat(lines, '\n'):gsub('\r', '')
        else
          text = lines
        end

        ensure_dap_repl_visible()
        dap.repl.execute(text)
      end
    end,
  },
}
