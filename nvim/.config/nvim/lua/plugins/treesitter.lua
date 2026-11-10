return { -- Highlight, edit, and navigate code
  'nvim-treesitter/nvim-treesitter',
  event = { 'BufReadPost', 'BufNewFile' },
  build = ':TSUpdate',
  dependencies = {
    {
      'nvim-treesitter/nvim-treesitter-context',
      config = function()
        require('treesitter-context').setup {
          enable = true,
          multiwindow = false,
          max_lines = 2,
          min_window_height = 0,
          line_numbers = true,
          multiline_threshold = 1,
          trim_scope = 'outer',
          mode = 'cursor',
          separator = nil,
          zindex = 20,
          on_attach = nil,
        }
      end,
    },
    -- nvim-dap-repl-highlights is set up in the main config function below
    'LiadOz/nvim-dap-repl-highlights',
    -- `main` is required: the `master` branch pairs with nvim-treesitter's `master`
    -- and its `configs.setup { textobjects = ... }` API silently no-ops here.
    {
      'nvim-treesitter/nvim-treesitter-textobjects',
      branch = 'main',
    },
  },
  config = function()
    -- IMPORTANT: nvim-dap-repl-highlights.setup() MUST be called BEFORE treesitter setup
    require('nvim-dap-repl-highlights').setup()

    -- nvim-treesitter main branch setup
    require('nvim-treesitter').setup {
      install_dir = vim.fn.stdpath 'data' .. '/site',
    }

    require('nvim-treesitter-textobjects').setup {
      select = {
        -- Jump forward to the textobject if the cursor is before it, so `vif` works
        -- from a blank line above a function rather than failing.
        lookahead = true,
        selection_modes = {
          ['@function.outer'] = 'V',
          ['@class.outer'] = 'V',
        },
        include_surrounding_whitespace = false,
      },
    }

    -- Textobject selection only for now; `move` and `swap` can layer on later.
    -- `a`/`i` prefixes are free in operator-pending/visual mode, so none of these
    -- collide with the `[c`/`]d`/`]t` bracket jumps in core/keymaps.lua.
    local ts_select = require 'nvim-treesitter-textobjects.select'
    local textobjects = {
      { key = 'f', name = 'function', outer = '@function.outer', inner = '@function.inner' },
      { key = 'c', name = 'class', outer = '@class.outer', inner = '@class.inner' },
      { key = 'a', name = 'argument', outer = '@parameter.outer', inner = '@parameter.inner' },
      { key = 'i', name = 'conditional', outer = '@conditional.outer', inner = '@conditional.inner' },
      { key = 'l', name = 'loop', outer = '@loop.outer', inner = '@loop.inner' },
      { key = 'm', name = 'call', outer = '@call.outer', inner = '@call.inner' },
      -- Most languages only ship a @comment.outer query, so there is no `i/`.
      { key = '/', name = 'comment', outer = '@comment.outer' },
    }
    for _, obj in ipairs(textobjects) do
      vim.keymap.set({ 'x', 'o' }, 'a' .. obj.key, function()
        ts_select.select_textobject(obj.outer, 'textobjects')
      end, { desc = 'Select outer ' .. obj.name })
      if obj.inner then
        vim.keymap.set({ 'x', 'o' }, 'i' .. obj.key, function()
          ts_select.select_textobject(obj.inner, 'textobjects')
        end, { desc = 'Select inner ' .. obj.name })
      end
    end

    -- Install parsers (main branch API)
    local parsers_to_install = {
      'lua',
      'python',
      'javascript',
      'typescript',
      'vimdoc',
      'vim',
      'regex',
      'terraform',
      'sql',
      'dockerfile',
      'helm',
      'toml',
      'json',
      'java',
      'just',
      'groovy',
      'go',
      'gitignore',
      'graphql',
      'yaml',
      'make',
      'cmake',
      'markdown',
      'markdown_inline',
      'bash',
      'tsx',
      'css',
      'html',
      'dap_repl',
    }

    -- Auto-install missing parsers on startup
    vim.api.nvim_create_autocmd('User', {
      pattern = 'VeryLazy',
      callback = function()
        -- Check installed parsers by looking for .so files in parser directories
        local installed_set = {}
        for _, dir in ipairs(vim.api.nvim_get_runtime_file('parser/*.so', true)) do
          local parser_name = vim.fn.fnamemodify(dir, ':t:r')
          installed_set[parser_name] = true
        end
        local to_install = {}
        for _, p in ipairs(parsers_to_install) do
          if not installed_set[p] then
            table.insert(to_install, p)
          end
        end
        if #to_install > 0 then
          require('nvim-treesitter').install(to_install)
        end
      end,
      once = true,
    })
  end,
  -- There are additional nvim-treesitter modules that you can use to interact
  -- with nvim-treesitter. You should go explore a few and see what interests you:
  --
  --    - Incremental selection: Included, see `:help nvim-treesitter-incremental-selection-mod`
  --    - Show your current context: https://github.com/nvim-treesitter/nvim-treesitter-context
  --    - Treesitter + textobjects: https://github.com/nvim-treesitter/nvim-treesitter-textobjects
}
