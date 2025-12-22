return {
  'nvim-neotest/neotest',
  dependencies = {
    'nvim-neotest/nvim-nio',
    'nvim-lua/plenary.nvim',
    'antoinemadec/FixCursorHold.nvim',
    'nvim-treesitter/nvim-treesitter',

    -- adapters
    'nvim-neotest/neotest-python',
    'nvim-neotest/neotest-plenary',
    'nvim-neotest/neotest-vim-test',
  },
  config = function()
    local neotest = require 'neotest'

    neotest.setup {
      floating = {
        border = 'rounded',
      },
      icons = {
        child_indent = '│',
        child_prefix = '├',
        collapsed = '─',
        expanded = '┐',
        failed = '',
        final_child_indent = ' ',
        final_child_prefix = '└',
        non_collapsible = '─',
        notify = '',
        passed = '󰄴',
        running = '',
        -- running_animated = { '', '', '', '', '', '' },
        running_animated = { '', '', '', '', '', '', '', '', '', '', '', '', '', '' },
        skipped = '',
        test = '',
        unknown = '󰄰',
        watching = '',
      },

      adapters = {
        require 'neotest-python' {
          dap = { justMyCode = false },
        },
        args = { '--log-level', 'DEBUG', '-vvv' },
        runner = 'pytest',
        python = '.venv/bin/python',

        require 'neotest-plenary',
        require 'neotest-vim-test' {
          ignore_file_types = { 'python', 'vim', 'lua' },
        },
      },
    }

    -- Hide the global statuscolumn/line numbers inside the summary sidebar
    local summary_group = vim.api.nvim_create_augroup('UserNeotestSummary', { clear = true })
    local function disable_summary_numbers(bufnr)
      for _, win in ipairs(vim.api.nvim_list_wins()) do
        if vim.api.nvim_win_get_buf(win) == bufnr then
          vim.api.nvim_set_option_value('number', false, { win = win })
          vim.api.nvim_set_option_value('relativenumber', false, { win = win })
          vim.api.nvim_set_option_value('statuscolumn', ' ', { win = win })
        end
      end
    end

    local function focus_summary_window()
      for _, win in ipairs(vim.api.nvim_list_wins()) do
        local buf = vim.api.nvim_win_get_buf(win)
        if vim.bo[buf].filetype == 'neotest-summary' then
          vim.api.nvim_set_current_win(win)
          break
        end
      end
    end

    vim.api.nvim_create_autocmd('FileType', {
      group = summary_group,
      pattern = 'neotest-summary',
      callback = function(args)
        disable_summary_numbers(args.buf)
      end,
    })

    vim.api.nvim_create_autocmd('BufWinEnter', {
      group = summary_group,
      callback = function(args)
        if vim.bo[args.buf].filetype == 'neotest-summary' then
          disable_summary_numbers(args.buf)
        end
      end,
    })

    vim.api.nvim_create_autocmd('User', {
      group = summary_group,
      pattern = 'NeotestSummaryOpen',
      callback = focus_summary_window,
    })
  end,
}
