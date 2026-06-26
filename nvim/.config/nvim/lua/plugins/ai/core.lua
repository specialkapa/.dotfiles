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
    config = function()
      local function set_copilot_from_marker()
        local marker = vim.fn.getcwd() .. '/.copilot'
        local enable = true
        if vim.fn.filereadable(marker) == 1 then
          local lines = vim.fn.readfile(marker)
          local value = vim.trim(lines[1] or '')
          enable = value ~= 'enable=false'
        end
        if enable then
          vim.cmd 'Copilot enable'
        else
          vim.cmd 'Copilot disable'
        end
      end

      local group = vim.api.nvim_create_augroup('CopilotLearningMode', { clear = true })
      vim.api.nvim_create_autocmd({ 'VimEnter', 'DirChanged' }, {
        group = group,
        callback = function()
          set_copilot_from_marker()
        end,
      })
    end,
  },
  {
    'coder/claudecode.nvim',
    dependencies = { 'folke/snacks.nvim' },
    opts = {
      terminal = {
        snacks_win_opts = {
          -- Remap the terminal window's Normal/NormalNC to a custom group so the
          -- Claude split has a lighter background than the editor.
          wo = {
            winhighlight = 'Normal:ClaudeNormal,NormalNC:ClaudeNormal',
          },
        },
      },
    },
    config = function(_, opts)
      require('claudecode').setup(opts)

      -- Tie the split's background to Catppuccin's `surface0` — the theme's
      -- "elevated surface" shade (lighter than the editor's `base` in mocha).
      -- Resolved from the live palette so it tracks the auto latte/mocha switch.
      local function set_hl()
        local ok, palettes = pcall(require, 'catppuccin.palettes')
        if not ok then
          return
        end
        vim.api.nvim_set_hl(0, 'ClaudeNormal', { bg = palettes.get_palette().surface0 })
      end
      set_hl()
      -- Custom groups are cleared on colorscheme load, so re-apply after one.
      vim.api.nvim_create_autocmd('ColorScheme', { callback = set_hl })

      -- Auto-insert on focus + <Esc> to leave terminal-insert mode, scoped to the
      -- Claude split. claudecode runs on a snacks terminal, so it doesn't pick up
      -- the toggleterm-only mappings in core/keymaps.lua. We identify it by the
      -- terminal buffer name (the `claude` CLI shows up in the `term://` name);
      -- opencode/codex terminals don't match, so they're left untouched.
      local claudeTermGroup = vim.api.nvim_create_augroup('UserClaudeTerminal', { clear = true })

      local function is_claude_terminal(buf)
        return vim.api.nvim_buf_is_valid(buf)
          and vim.bo[buf].buftype == 'terminal'
          and vim.api.nvim_buf_get_name(buf):lower():match 'claude' ~= nil
      end

      -- <Esc> drops to terminal-normal mode (so you can visual-select Claude's
      -- output), mirroring the toggleterm behaviour. Set buffer-locally on open.
      vim.api.nvim_create_autocmd('TermOpen', {
        group = claudeTermGroup,
        callback = function(args)
          if is_claude_terminal(args.buf) then
            vim.keymap.set('t', '<esc>', [[<C-\><C-n>]], { buffer = args.buf, silent = true })
          end
        end,
      })

      -- Drop into insert (terminal) mode whenever the Claude split gains focus.
      -- Only fires on *entry*, so pressing <Esc> afterwards leaves you in
      -- terminal-normal mode until you switch away and come back.
      vim.api.nvim_create_autocmd({ 'BufWinEnter', 'WinEnter' }, {
        group = claudeTermGroup,
        callback = function()
          vim.schedule(function()
            local buf = vim.api.nvim_get_current_buf()
            if is_claude_terminal(buf) and vim.api.nvim_get_mode().mode ~= 't' then
              vim.cmd 'startinsert'
            end
          end)
        end,
      })
    end,
    -- `cmd` lets lazy.nvim create command stubs that load the plugin on first use,
    -- so `:ClaudeCode` and friends work on a fresh start. Without it, a keys-only
    -- spec defers loading until a <leader>a* mapping is pressed and the commands
    -- would not exist yet.
    cmd = {
      'ClaudeCode',
      'ClaudeCodeFocus',
      'ClaudeCodeSelectModel',
      'ClaudeCodeAdd',
      'ClaudeCodeSend',
      'ClaudeCodeTreeAdd',
      'ClaudeCodeStatus',
      'ClaudeCodeStart',
      'ClaudeCodeStop',
      'ClaudeCodeOpen',
      'ClaudeCodeClose',
      'ClaudeCodeDiffAccept',
      'ClaudeCodeDiffDeny',
      'ClaudeCodeCloseAllDiffs',
    },
    keys = {
      { '<leader>a', nil, desc = 'AI/Claude Code' },
      { '<leader>ac', '<cmd>ClaudeCode<cr>', desc = 'Toggle Claude' },
      { '<leader>af', '<cmd>ClaudeCodeFocus<cr>', desc = 'Focus Claude' },
      { '<leader>ar', '<cmd>ClaudeCode --resume<cr>', desc = 'Resume Claude' },
      { '<leader>aC', '<cmd>ClaudeCode --continue<cr>', desc = 'Continue Claude' },
      { '<leader>am', '<cmd>ClaudeCodeSelectModel<cr>', desc = 'Select Claude model' },
      { '<leader>ab', '<cmd>ClaudeCodeAdd %<cr>', desc = 'Add current buffer' },
      {
        '<leader>ap',
        function()
          require('plugins.ai.claude').open()
        end,
        desc = 'Prompt Claude (cursor context)',
      },
      { '<leader>as', '<cmd>ClaudeCodeSend<cr>', mode = 'v', desc = 'Send to Claude' },
      {
        '<leader>as',
        '<cmd>ClaudeCodeTreeAdd<cr>',
        desc = 'Add file',
        ft = { 'NvimTree', 'neo-tree', 'oil', 'minifiles', 'netrw', 'snacks_picker_list' },
      },
      -- Diff management
      { '<leader>aa', '<cmd>ClaudeCodeDiffAccept<cr>', desc = 'Accept diff' },
      { '<leader>ad', '<cmd>ClaudeCodeDiffDeny<cr>', desc = 'Deny diff' },
    },
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

      -- `autoread` (required for `vim.g.opencode_opts.auto_reload`) is now set
      -- globally in core/options.lua alongside the checktime safety net.

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
