return {
  {
    'rhart92/codex.nvim', -- depends on codex CLI. Make sure it is installed
    config = function()
      require('codex').setup {
        split = 'vertical',
        size = 0.3,
        float = {
          width = 1,
          height = 0.6,
          border = 'rounded',
          row = nil,
          col = nil,
          title = 'codex',
        },
        codex_cmd = { 'codex' },
        focus_after_send = true,
        log_level = 'debug',
        autostart = false,
      }

      local group = vim.api.nvim_create_augroup('CodexHideStatusColumn', { clear = true })
      vim.api.nvim_create_autocmd('BufWinEnter', {
        group = group,
        callback = function(args)
          if vim.bo[args.buf].filetype ~= 'codex' then
            return
          end
          local win = vim.api.nvim_get_current_win()
          if not vim.api.nvim_win_is_valid(win) then
            return
          end
          vim.api.nvim_set_option_value('statuscolumn', '', { win = win })
          vim.api.nvim_set_option_value('number', false, { win = win })
          vim.api.nvim_set_option_value('relativenumber', false, { win = win })
        end,
      })

      vim.keymap.set('v', '<leader>cs', function()
        require('codex').actions.send_selection()
      end, { desc = 'Codex: Send selection' })

      vim.keymap.set('n', '<leader>cc', function()
        require('codex').toggle()
      end, { desc = 'Codex: Toggle' })
    end,
  },
  {
    'github/copilot.vim', -- depends on node.js. Make sure it is installed
  },
  {
    'greggh/claude-code.nvim',
    dependencies = {
      'nvim-lua/plenary.nvim', -- Required for git operations
    },
    config = function()
      require('claude-code').setup {
        -- Terminal window settings
        window = {
          split_ratio = 0.3, -- Percentage of screen for the terminal window (height for horizontal, width for vertical splits)
          position = 'vertical', -- Position of the window: "botright", "topleft", "vertical", "float", etc.
          enter_insert = true, -- Whether to enter insert mode when opening Claude Code
          hide_numbers = true, -- Hide line numbers in the terminal window
          hide_signcolumn = true, -- Hide the sign column in the terminal window

          -- Floating window configuration (only applies when position = "float")
          float = {
            width = '80%', -- Width: number of columns or percentage string
            height = '80%', -- Height: number of rows or percentage string
            row = 'center', -- Row position: number, "center", or percentage string
            col = 'center', -- Column position: number, "center", or percentage string
            relative = 'editor', -- Relative to: "editor" or "cursor"
            border = 'rounded', -- Border style: "none", "single", "double", "rounded", "solid", "shadow"
          },
        },
        -- File refresh settings
        refresh = {
          enable = true, -- Enable file change detection
          updatetime = 100, -- updatetime when Claude Code is active (milliseconds)
          timer_interval = 1000, -- How often to check for file changes (milliseconds)
          show_notifications = true, -- Show notification when files are reloaded
        },
        -- Git project settings
        git = {
          use_git_root = true, -- Set CWD to git root when opening Claude Code (if in git project)
        },
        -- Shell-specific settings
        shell = {
          separator = '&&', -- Command separator used in shell commands
          pushd_cmd = 'pushd', -- Command to push directory onto stack (e.g., 'pushd' for bash/zsh, 'enter' for nushell)
          popd_cmd = 'popd', -- Command to pop directory from stack (e.g., 'popd' for bash/zsh, 'exit' for nushell)
        },
        -- Command settings
        command = 'claude', -- Command used to launch Claude Code
        -- Command variants
        command_variants = {
          -- Conversation management
          continue = '--continue', -- Resume the most recent conversation
          resume = '--resume', -- Display an interactive conversation picker

          -- Output options
          verbose = '--verbose', -- Enable verbose logging with full turn-by-turn output
        },
        -- Keymaps
        keymaps = {
          toggle = {
            normal = '<C-,>', -- Normal mode keymap for toggling Claude Code, false to disable
            terminal = '<C-,>', -- Terminal mode keymap for toggling Claude Code, false to disable
            variants = {
              continue = '<leader>cC', -- Normal mode keymap for Claude Code with continue flag
              verbose = '<leader>cV', -- Normal mode keymap for Claude Code with verbose flag
            },
          },
          window_navigation = true, -- Enable window navigation keymaps (<C-h/j/k/l>)
          scrolling = true, -- Enable scrolling keymaps (<C-f/b>) for page up/down
        },
      }
    end,
  },
  {
    'NickvanDyke/opencode.nvim',
    dependencies = {
      -- Recommended for `ask()` and `select()`.
      -- Required for default `toggle()` implementation.
      { 'folke/snacks.nvim', opts = { input = {}, picker = {}, terminal = {} } },
    },
    config = function()
      ---@type opencode.Opts
      vim.g.opencode_opts = {
        -- Your configuration, if any — see `lua/opencode/config.lua`, or "goto definition".
      }

      -- Required for `vim.g.opencode_opts.auto_reload`.
      vim.o.autoread = true

      -- Recommended/example keymaps.
      vim.keymap.set({ 'n', 'x' }, '<leader>oa', function()
        require('opencode').ask('@this: ', { submit = true })
      end, { desc = '[O]penCode: [A]sk about this' })
      vim.keymap.set({ 'n', 'x' }, '<leader>os', function()
        require('opencode').select()
      end, { desc = '[O]penCode: [S]elect prompt' })
      vim.keymap.set({ 'n', 'x' }, '<leader>o+', function()
        require('opencode').prompt '@this'
      end, { desc = '[O]penCode: [A]dd this' })
      vim.keymap.set('n', '<leader>ot', function()
        require('opencode').toggle()
      end, { desc = '[O]penCode: [T]oggle embedded' })
      vim.keymap.set('n', '<leader>oc', function()
        require('opencode').command()
      end, { desc = '[O]penCode: Select [C]ommand' })
      vim.keymap.set('n', '<leader>on', function()
        require('opencode').command 'session_new'
      end, { desc = '[O]penCode: [N]ew session' })
      vim.keymap.set('n', '<leader>oi', function()
        require('opencode').command 'session_interrupt'
      end, { desc = '[O]penCode: [I]nterrupt session' })
      vim.keymap.set('n', '<leader>oA', function()
        require('opencode').command 'agent_cycle'
      end, { desc = '[O]penCode: Cycle selected [A]gent' })
      vim.keymap.set('n', '<S-C-u>', function()
        require('opencode').command 'messages_half_page_up'
      end, { desc = 'Messages half page up' })
      vim.keymap.set('n', '<S-C-d>', function()
        require('opencode').command 'messages_half_page_down'
      end, { desc = 'Messages half page down' })
    end,
  },
}
