-- ty (Astral's LSP) emits standard LSP semantic tokens, which Neovim applies
-- automatically as `@lsp.type.*` / `@lsp.typemod.*.*` highlight groups. Catppuccin
-- already links these to sensible defaults, so this is purely an override to echo the
-- (now-removed) semshi colour scheme. Tune/remove freely -- run `:Inspect` on a token
-- to see which group is actually active before adjusting a colour here.
local function apply_ty_lsp_highlights()
  local palettes_ok, palettes = pcall(require, 'catppuccin.palettes')
  if not palettes_ok then
    return
  end

  local flavour = vim.g.catppuccin_flavour or 'mocha'
  local palette = palettes.get_palette(flavour)
  if not palette then
    return
  end

  -- Mirror of the semshi palette, mapped onto standard LSP token groups.
  -- Note: LSP has no concept of unused-parameter / unresolved-name / free-variable,
  -- so those semshi cues have no equivalent here -- that gap is the trade-off of the swap.
  vim.api.nvim_set_hl(0, '@lsp.type.variable.python', { fg = palette.lavender }) -- was semshiLocal
  vim.api.nvim_set_hl(0, '@lsp.type.parameter.python', { fg = palette.maroon }) -- was semshiParameter
  vim.api.nvim_set_hl(0, '@lsp.type.property.python', { fg = palette.mauve }) -- was semshiAttribute
  vim.api.nvim_set_hl(0, '@lsp.type.selfParameter.python', { fg = palette.flamingo }) -- was semshiSelf
  -- Builtins (`defaultLibrary` modifier) -- was semshiBuiltin
  vim.api.nvim_set_hl(0, '@lsp.typemod.variable.defaultLibrary.python', { fg = palette.teal })
  vim.api.nvim_set_hl(0, '@lsp.typemod.function.defaultLibrary.python', { fg = palette.teal })
  vim.api.nvim_set_hl(0, '@lsp.typemod.class.defaultLibrary.python', { fg = palette.teal })
end

apply_ty_lsp_highlights()

local ty_hl_group = vim.api.nvim_create_augroup('TyLspCatppuccinHighlights', { clear = true })
vim.api.nvim_create_autocmd('ColorScheme', {
  group = ty_hl_group,
  callback = apply_ty_lsp_highlights,
})

return {
  {
    -- Automatic refactoring of workspace imports on python file/dir move/rename.
    -- Automatic missing import resolution for sumbol under cursor.
    'alexpasmantier/pymple.nvim',
    -- Import refactoring only matters once you're actually editing python/markdown,
    -- so defer loading (and its heavy nvim-tree/dressing/nui/treesitter deps) until then.
    ft = { 'python', 'markdown' },
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
    'smzm/hydrovim',
    dependencies = { 'MunifTanjim/nui.nvim' },
    -- optional: lazy-load when F8 is pressed
    keys = { '<F8>' },
  },
  {
    'Vigemus/iron.nvim',
    -- REPL for python/sh -- load when you open one of those files (or hit a repl
    -- keymap), not at startup. Crucially this used to `require 'dap'` eagerly, which
    -- dragged the entire nvim-dap stack (~600ms) into startup.
    ft = { 'python', 'sh' },
    keys = { '<space>rr', '<space>rf', '<space>rh', { '<space>sc', mode = { 'n', 'x' } } },
    config = function()
      local iron = require 'iron.core'
      local view = require 'iron.view'
      local common = require 'iron.fts.common'

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

      -- The bare gutter (no line numbers) is handled globally by UserStatusColumn;
      -- here we only drop the sign column so the REPL shows a plain 1-col pad.
      local function disable_python_repl_numbers(bufnr)
        for _, win in ipairs(vim.api.nvim_list_wins()) do
          if vim.api.nvim_win_get_buf(win) == bufnr then
            vim.wo[win].signcolumn = 'no'
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
          require('dap').repl.open()
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
        require('dap').repl.execute(text)
      end
    end,
  },
  {
    -- on-demand Ruff import sorting/fixing for python buffers
    'nvim-lua/plenary.nvim', -- already a dependency; reuse as a lightweight host
    ft = { 'python' },
    config = function()
      local function fix_imports(bufnr)
        return function()
          if vim.fn.executable 'ruff' == 0 then
            vim.notify('ruff not found in active environment; skipped', vim.log.levels.WARN)
            return
          end

          local bufname = vim.api.nvim_buf_get_name(bufnr)
          if bufname == '' then
            vim.notify('buffer has no file path; save it first', vim.log.levels.WARN)
            return
          end

          -- ensure disk matches buffer before ruff rewrites the file
          if vim.bo[bufnr].modified then
            vim.cmd 'write'
          end

          local output = vim.fn.system { 'ruff', 'check', bufname, '--select=I', '--fix' }
          -- reload to pick up ruff's on-disk changes
          vim.cmd 'checktime'

          -- ruff exits non-zero when unfixable violations remain; not a hard error
          if vim.v.shell_error ~= 0 and output ~= '' then
            vim.notify(output, vim.log.levels.INFO)
          else
            vim.notify('ruff: imports fixed', vim.log.levels.INFO)
          end
        end
      end

      local function set_keymap(bufnr)
        vim.keymap.set('n', '<leader>ri', fix_imports(bufnr), { buffer = bufnr, desc = '[R]uff fix [I]mports', noremap = true, silent = true })
      end

      local group = vim.api.nvim_create_augroup('RuffFixImports', { clear = true })
      vim.api.nvim_create_autocmd('FileType', {
        group = group,
        pattern = 'python',
        callback = function(args)
          set_keymap(args.buf)
        end,
      })

      -- This plugin is lazy-loaded on `ft = python`, so by the time `config` runs the
      -- FileType event for the buffer that triggered the load has already fired — the
      -- autocmd above won't catch it. Apply the mapping to any python buffers already
      -- open so the very first python file you open gets the keymap too.
      for _, buf in ipairs(vim.api.nvim_list_bufs()) do
        if vim.api.nvim_buf_is_loaded(buf) and vim.bo[buf].filetype == 'python' then
          set_keymap(buf)
        end
      end
    end,
  },
}
