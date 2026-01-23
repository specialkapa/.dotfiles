-- Standalone plugins with less than 10 lines of config go here
return {
  {
    -- Detect tabstop and shiftwidth automatically
    'tpope/vim-sleuth',
  },
  {
    -- Hints keybinds
    'folke/which-key.nvim',
    event = 'VeryLazy',
    opts = {
      preset = 'helix',
      win = {
        title = '  keybinds ',
        title_pos = 'center',
      },
    },
  },
  {
    -- Autoclose parentheses, brackets, quotes, etc.
    'windwp/nvim-autopairs',
    event = 'InsertEnter',
    config = true,
    opts = {},
  },
  {
    -- High-performance color highlighter
    'norcalli/nvim-colorizer.lua',
    event = 'InsertEnter',
    config = function()
      require('colorizer').setup()
    end,
  },
  {
    'ya2s/nvim-cursorline',
    config = function()
      require('nvim-cursorline').setup {
        cursorline = {
          enable = false,
          timeout = 1000,
          number = true,
        },
        cursorword = {
          enable = true,
          min_length = 3,
          hl = { underline = true },
        },
      }
    end,
  },
  {
    'folke/persistence.nvim',
    event = 'BufReadPre', -- this will only start session saving when an actual file was opened
    opts = {
      -- add any custom options here
    },
  },
  {
    'numToStr/Comment.nvim',
    opts = {},
    config = function()
      local opts = { noremap = true, silent = true }
      vim.keymap.set('n', '<C-_>', require('Comment.api').toggle.linewise.current, opts)
      vim.keymap.set('n', '<C-c>', require('Comment.api').toggle.linewise.current, opts)
      vim.keymap.set('n', '<C-/>', require('Comment.api').toggle.linewise.current, opts)
      vim.keymap.set('v', '<C-_>', "<ESC><cmd>lua require('Comment.api').toggle.linewise(vim.fn.visualmode())<cr>", opts)
      vim.keymap.set('v', '<C-c>', "<ESC><cmd>lua require('Comment.api').toggle.linewise(vim.fn.visualmode())<cr>", opts)
      vim.keymap.set('v', '<C-/>', "<ESC><cmd>lua require('Comment.api').toggle.linewise(vim.fn.visualmode())<cr>", opts)
    end,
  },
  {
    'lukas-reineke/indent-blankline.nvim',
    event = 'BufReadPost',
    main = 'ibl',
    opts = {
      indent = {
        char = '▏',
      },
      scope = {
        show_start = false,
        show_end = false,
        show_exact_scope = false,
      },
      exclude = {
        filetypes = {
          'help',
          'startify',
          'dashboard',
          'packer',
          'neogitstatus',
          'NvimTree',
          'Trouble',
        },
      },
    },
  },
  {
    'vimwiki/vimwiki',
    init = function()
      vim.g.vimwiki_list = {
        {
          path = vim.fn.expand '~/.vimwiki/',
          syntax = 'markdown',
          ext = 'md',
          diary_rel_path = 'journal/',
          diary_index = 'journal',
          diary_header = 'Journal',
          diary_frequency = 'yearly',
          vimwiki_toc_link_format = 0,
          diary_mode = 'append',
          diary_sort = 'desc',
        },
      }

      vim.api.nvim_create_user_command('AppendDiary', function()
        local cfg = vim.g.vimwiki_list[1]
        local diary_path = vim.fn.expand(cfg.path .. cfg.diary_rel_path .. cfg.diary_index .. '.' .. cfg.ext)
        local date_header = '# ' .. os.date '%Y-%m-%d'
        local content = { '', date_header, '', '- [ ] Todo item', '' }

        local file = io.open(diary_path, 'r')
        local lines = {}
        local header_exists = false
        if file then
          for line in file:lines() do
            if line == date_header then
              header_exists = true
            end
            table.insert(lines, line)
          end
          file:close()
        end

        if header_exists then
          vim.cmd('edit ' .. diary_path)
          return
        end

        if #lines > 0 and lines[#lines] ~= '' then
          table.insert(lines, '')
        end
        for _, line in ipairs(content) do
          table.insert(lines, line)
        end

        file = io.open(diary_path, 'w')
        if file then
          local body = table.concat(lines, '\n')
          if #body > 0 then
            body = body .. '\n'
          end
          file:write(body)
          file:close()
          vim.cmd('edit ' .. diary_path)
        end
      end, {})
    end,
  },
  {
    'jake-stewart/multicursor.nvim',
    branch = '1.0',
    config = function()
      local mc = require 'multicursor-nvim'
      mc.setup()

      local set = vim.keymap.set

      -- Add or skip cursor above/below the main cursor (vim-style j/k).
      set({ 'n', 'x' }, '<leader>mk', function()
        mc.lineAddCursor(-1)
      end, { desc = 'Add cursor above' })
      set({ 'n', 'x' }, '<leader>mj', function()
        mc.lineAddCursor(1)
      end, { desc = 'Add cursor below' })
      set({ 'n', 'x' }, '<leader>mK', function()
        mc.lineSkipCursor(-1)
      end, { desc = 'Skip cursor above' })
      set({ 'n', 'x' }, '<leader>mJ', function()
        mc.lineSkipCursor(1)
      end, { desc = 'Skip cursor below' })

      -- Add or skip adding a new cursor by matching word/selection
      set({ 'n', 'x' }, '<leader>mn', function()
        mc.matchAddCursor(1)
      end, { desc = 'Add cursor at next match' })
      set({ 'n', 'x' }, '<leader>ms', function()
        mc.matchSkipCursor(1)
      end, { desc = 'Skip next match' })
      set({ 'n', 'x' }, '<leader>mN', function()
        mc.matchAddCursor(-1)
      end, { desc = 'Add cursor at prev match' })
      set({ 'n', 'x' }, '<leader>mS', function()
        mc.matchSkipCursor(-1)
      end, { desc = 'Skip prev match' })

      -- Add and remove cursors with control + left click.
      set('n', '<c-leftmouse>', mc.handleMouse)
      set('n', '<c-leftdrag>', mc.handleMouseDrag)
      set('n', '<c-leftrelease>', mc.handleMouseRelease)

      -- Toggle cursor on/off.
      set({ 'n', 'x' }, '<leader>mt', mc.toggleCursor, { desc = 'Toggle cursor' })

      -- Mappings defined in a keymap layer only apply when there are
      -- multiple cursors. This lets you have overlapping mappings.
      mc.addKeymapLayer(function(layerSet)
        -- Select a different cursor as the main one (vim-style h/l).
        layerSet({ 'n', 'x' }, '<leader>mh', mc.prevCursor)
        layerSet({ 'n', 'x' }, '<leader>ml', mc.nextCursor)

        -- Delete the main cursor.
        layerSet({ 'n', 'x' }, '<leader>mx', mc.deleteCursor)

        -- Enable and clear cursors using escape.
        layerSet('n', '<esc>', function()
          if not mc.cursorsEnabled() then
            mc.enableCursors()
          else
            mc.clearCursors()
          end
        end)
      end)

      -- Customize how cursors look.
      local hl = vim.api.nvim_set_hl
      hl(0, 'MultiCursorCursor', { reverse = true })
      hl(0, 'MultiCursorVisual', { link = 'Visual' })
      hl(0, 'MultiCursorSign', { link = 'SignColumn' })
      hl(0, 'MultiCursorMatchPreview', { link = 'Search' })
      hl(0, 'MultiCursorDisabledCursor', { reverse = true })
      hl(0, 'MultiCursorDisabledVisual', { link = 'Visual' })
      hl(0, 'MultiCursorDisabledSign', { link = 'SignColumn' })
    end,
  },
  {
    'zhisme/copy_with_context.nvim',
    config = function()
      require('copy_with_context').setup {
        -- Customize mappings
        mappings = {
          relative = '<leader>yc',
          absolute = '<leader>Yc',
          remote = '<leader>cr',
        },
        formats = {
          default = '# {filepath}:{line}', -- Used by relative and absolute mappings
          remote = '# {remote_url}',
        },
        -- whether to trim lines or not
        trim_lines = false,
      }
    end,
  },
}
