return {
  'nvim-telescope/telescope.nvim',
  event = 'VimEnter',
  dependencies = {
    'nvim-lua/plenary.nvim',
    {
      'nvim-telescope/telescope-fzf-native.nvim',
      build = 'make',
      cond = function()
        return vim.fn.executable 'make' == 1
      end,
    },
    { 'nvim-telescope/telescope-dap.nvim' },
    { 'nvim-telescope/telescope-file-browser.nvim' },
    { 'nvim-telescope/telescope-ui-select.nvim' },
    { 'nvim-tree/nvim-web-devicons', enabled = vim.g.have_nerd_font },
  },
  config = function()
    local telescope = require 'telescope'
    local builtin = require 'telescope.builtin'
    local pretty = require 'plugins.telescope.pretty_pickers'

    local function ts_select_dir_for_grep(prompt_bufnr)
      local action_state = require 'telescope.actions.state'
      local actions = require 'telescope.actions'
      local fb = telescope.extensions.file_browser
      local live_grep = builtin.live_grep
      local current_line = action_state.get_current_line()

      fb.file_browser {
        files = false,
        depth = false,
        attach_mappings = function(_prompt_bufnr)
          actions.select_default:replace(function()
            local entry_path = action_state.get_selected_entry().Path
            local dir = entry_path:is_dir() and entry_path or entry_path:parent()
            local relative = dir:make_relative(vim.fn.getcwd())
            local absolute = dir:absolute()

            live_grep {
              results_title = relative .. '/',
              cwd = absolute,
              default_text = current_line,
            }
          end)

          return true
        end,
      }
    end

    telescope.setup {
      defaults = {
        sorting_strategy = 'ascending',
        layout_config = {
          horizontal = {
            prompt_position = 'top',
          },
        },
      },
      pickers = {
        find_files = {
          file_ignore_patterns = { 'node_modules', '^.git/', '^.venv/' },
          hidden = true,
        },
        live_grep = {
          file_ignore_patterns = { 'node_modules', '^.git/', '^.venv/' },
          additional_args = function()
            return { '--hidden' }
          end,
          mappings = {
            i = {
              ['<C-f>'] = ts_select_dir_for_grep,
            },
            n = {
              ['<C-f>'] = ts_select_dir_for_grep,
            },
          },
        },
      },
      extensions = {
        ['ui-select'] = {
          require('telescope.themes').get_dropdown(),
        },
        file_browser = {
          grouped = true,
        },
        cmdline = {
          picker = {
            layout_config = {
              width = 100,
              height = 10,
            },
          },
          mappings = {
            complete = '<Tab>',
            run_selection = '<C-CR>',
            run_input = '<CR>',
          },
          overseer = {
            enabled = true,
          },
          icons = {
            history = '',
            command = ' ',
            number = '󰴍 ',
            system = '',
            unknown = '',
          },
        },
      },
    }

    local function find_directory_and_focus()
      local actions = require 'telescope.actions'
      local action_state = require 'telescope.actions.state'
      local api = require 'nvim-tree.api'

      local function attach_mappings(prompt_bufnr, _)
        actions.select_default:replace(function()
          actions.close(prompt_bufnr)

          local selection = action_state.get_selected_entry()
          if not selection then
            return
          end

          local path = selection.path or selection.filename or selection.value
          if not path then
            vim.notify('Could not resolve selection path', vim.log.levels.WARN)
            return
          end

          local is_absolute = path:match '^/' or path:match '^[A-Za-z]:[/\\]'
          if selection.cwd and not is_absolute then
            path = vim.fn.fnamemodify(selection.cwd .. '/' .. path, ':p')
          end

          local uv = vim.uv or vim.loop
          local stat = uv.fs_stat(path)
          if not stat then
            vim.notify('Unable to read file information for: ' .. path, vim.log.levels.WARN)
            return
          end

          api.tree.find_file { buf = path, open = true, focus = true }
        end)
        return true
      end

      local opts = {
        attach_mappings = attach_mappings,
        hidden = true,
      }

      if vim.fn.executable 'fd' == 1 then
        opts.find_command = { 'fd', '--type', 'f', '--type', 'd', '--hidden', '--exclude', '.git' }
      end

      pretty.pretty_files_picker {
        picker = 'find_files',
        options = opts,
      }
    end

    pcall(telescope.load_extension, 'fzf')
    pcall(telescope.load_extension, 'ui-select')
    pcall(telescope.load_extension, 'cmdline')
    pcall(telescope.load_extension, 'dap')
    pcall(telescope.load_extension, 'file_browser')

    local function map_pretty_files(lhs, picker, desc, opts)
      vim.keymap.set('n', lhs, function()
        pretty.pretty_files_picker {
          picker = picker,
          options = opts,
        }
      end, { desc = desc })
    end

    local function map_pretty_grep(lhs, picker, desc, opts)
      vim.keymap.set('n', lhs, function()
        pretty.pretty_grep_picker {
          picker = picker,
          options = opts,
        }
      end, { desc = desc })
    end

    vim.keymap.set('n', '<leader>sh', builtin.help_tags, { desc = '[S]earch [H]elp' })
    vim.keymap.set('n', '<leader>sk', builtin.keymaps, { desc = '[S]earch [K]eymaps' })
    map_pretty_files('<leader>sf', 'find_files', '[S]earch [F]iles')
    vim.keymap.set('n', '<leader>fdd', find_directory_and_focus, { desc = '[F]ocus [DD]ir in tree' })
    vim.keymap.set('n', '<leader>ss', builtin.builtin, { desc = '[S]earch [S]elect Telescope' })
    map_pretty_grep('<leader>sw', 'grep_string', '[S]earch current [W]ord')
    map_pretty_grep('<leader>sg', 'live_grep', '[S]earch by [G]rep')
    vim.keymap.set('n', '<leader>sd', builtin.diagnostics, { desc = '[S]earch [D]iagnostics' })
    vim.keymap.set('n', '<leader>sR', builtin.lsp_references, { desc = '[S]earch LSP [R]eferences' })
    vim.keymap.set('n', '<leader>sr', builtin.resume, { desc = '[S]earch [R]esume' })
    map_pretty_files('<leader>s.', 'oldfiles', '[S]earch Recent Files ("." for repeat)')
    vim.keymap.set('n', '<leader><leader>', builtin.buffers, { desc = '[ ] Find existing buffers' })
    vim.keymap.set('n', '<leader>st', '<cmd>TodoTelescope<CR>', { desc = '[S]earch [T]ODOs' })
    vim.keymap.set('n', '<leader>fd', ' :Telescope find_files cwd=', { desc = 'Search in directory' })
    vim.keymap.set('n', '<leader>fb', ' :Telescope file_browser<CR>', { desc = '[F]ile [B]rowser' })

    vim.keymap.set('n', '<leader>/', function()
      builtin.current_buffer_fuzzy_find {
        prompt_title = 'Current Buffer Fuzzy Find',
        sorting_strategy = 'ascending',
        layout_strategy = 'horizontal',
        previewer = true,
        layout_config = {
          prompt_position = 'top',
          width = 0.5,
          height = 0.4,
          preview_width = 0.6,
        },
      }
    end, { desc = '[/] Fuzzily search in current buffer' })

    map_pretty_grep('<leader>s/', 'live_grep', '[S]earch [/] in Open Files', {
      grep_open_files = true,
      prompt_title = 'Live Grep in Open Files',
    })

    vim.keymap.set('n', '<leader>sn', function()
      pretty.pretty_files_picker {
        picker = 'find_files',
        options = { cwd = vim.fn.stdpath 'config' },
      }
    end, { desc = '[S]earch [N]eovim files' })
  end,
}
