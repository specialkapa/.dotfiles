return {
  {
    -- powerful git integration for vim
    'tpope/vim-fugitive',
    vim.keymap.set('n', '<leader>gu', '<cmd>gbrowse<cr>', { desc = '[g]it open file [u]rl' }),
  },
  {
    -- GitHub integration for vim-fugitive
    'tpope/vim-rhubarb',
  },
  {
    'f-person/git-blame.nvim',
    lazy = true,
    opts = {
      enabled = true,
      message_template = ' <summary>, <date>, <author>, <<sha>>',
      date_format = '%Y-%m-%d %H:%M:%S',
      display_virtual_text = 0,
      use_blame_commit_file_urls = true,
      message_when_not_committed = ' still cooking!',
    },
    vim.keymap.set('n', '<leader>gcu', '<cmd>GitBlameOpenCommitURL<cr>', { desc = '[G]it Blame Open File [U]RL' }),
  },
  {
    'lewis6991/gitsigns.nvim',
    event = { 'BufReadPre', 'BufNewFile' },
    opts = {
      signs = {
        add = { text = '+' },
        change = { text = '~' },
        delete = { text = '_' },
        topdelete = { text = '‾' },
        changedelete = { text = '~' },
      },
      signs_staged = {
        add = { text = '+' },
        change = { text = '~' },
        delete = { text = '_' },
        topdelete = { text = '‾' },
        changedelete = { text = '~' },
      },
    },
    config = function(_, opts)
      require('gitsigns').setup(opts)
      -- Add keymap for floating git blame window
      vim.keymap.set('n', '<leader>gb', function()
        require('plugins.git-utils.blame').show_git_blame_float()
      end, { desc = '[G]it [B]lame floating window' })
    end,
  },
  {
    'kdheepak/lazygit.nvim',
    lazy = true,
    cmd = {
      'LazyGit',
      'LazyGitConfig',
      'LazyGitCurrentFile',
      'LazyGitFilter',
      'LazyGitFilterCurrentFile',
    },
    -- optional for floating window border decoration
    dependencies = {
      'nvim-lua/plenary.nvim',
    },
    -- setting the keybinding for LazyGit with 'keys' is recommended in
    -- order to load the plugin when the command is run for the first time
    keys = {
      { '<leader>lg', '<cmd>LazyGit<cr>', desc = 'LazyGit' },
    },
  },
  {
    'esmuellert/vscode-diff.nvim',
    dependencies = { 'MunifTanjim/nui.nvim' },
    cmd = 'CodeDiff',
    config = function()
      require('vscode-diff').setup {
        -- Highlight configuration
        highlights = {
          -- Line-level: accepts highlight group names or hex colors (e.g., "#2ea043")
          line_insert = 'DiffAdd', -- Line-level insertions
          line_delete = 'DiffDelete', -- Line-level deletions

          -- Character-level: accepts highlight group names or hex colors
          -- If specified, these override char_brightness calculation
          char_insert = nil, -- Character-level insertions (nil = auto-derive)
          char_delete = nil, -- Character-level deletions (nil = auto-derive)

          -- Brightness multiplier (only used when char_insert/char_delete are nil)
          -- nil = auto-detect based on background (1.4 for dark, 0.92 for light)
          char_brightness = nil, -- Auto-adjust based on your colorscheme
        },

        -- Diff view behavior
        diff = {
          disable_inlay_hints = true, -- Disable inlay hints in diff windows for cleaner view
          max_computation_time_ms = 5000, -- Maximum time for diff computation (VSCode default)
        },

        -- Explorer panel configuration
        explorer = {
          position = 'left', -- "left" or "bottom"
          width = 40, -- Width when position is "left" (columns)
          height = 15, -- Height when position is "bottom" (lines)
          indent_markers = true, -- Show indent markers in tree view (│, ├, └)
          icons = {
            folder_closed = '󰉋', -- Nerd Font folder icon (customize as needed)
            folder_open = '󰝰', -- Nerd Font folder-open icon
          },
          view_mode = 'list', -- "list" or "tree"
          file_filter = {
            ignore = { '*.db', '*.sqlite', '*.sqlite3', '*.csv', '*.xlsx', '*.parquet' },
          },
        },

        -- Keymaps in diff view
        keymaps = {
          view = {
            quit = 'q', -- Close diff tab
            toggle_explorer = '<leader>b', -- Toggle explorer visibility (explorer mode only)
            next_hunk = ']c', -- Jump to next change
            prev_hunk = '[c', -- Jump to previous change
            next_file = ']f', -- Next file in explorer mode
            prev_file = '[f', -- Previous file in explorer mode
            diff_get = 'do', -- Get change from other buffer (like vimdiff)
            diff_put = 'dp', -- Put change to other buffer (like vimdiff)
          },
          explorer = {
            select = '<CR>', -- Open diff for selected file
            hover = 'K', -- Show file diff preview
            refresh = 'R', -- Refresh git status
            toggle_view_mode = 'i', -- Toggle between 'list' and 'tree' views
          },
        },
      }
    end,
  },
}
