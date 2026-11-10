return { -- Autocompletion
  'hrsh7th/nvim-cmp',
  event = { 'InsertEnter', 'CmdlineEnter' },
  dependencies = {
    -- Snippet Engine & its associated nvim-cmp source
    {
      'L3MON4D3/LuaSnip',
      build = (function()
        -- Build Step is needed for regex support in snippets.
        -- This step is not supported in many windows environments.
        -- Remove the below condition to re-enable on windows.
        if vim.fn.has 'win32' == 1 or vim.fn.executable 'make' == 0 then
          return
        end
        return 'make install_jsregexp'
      end)(),
      dependencies = {
        -- `friendly-snippets` contains a variety of premade snippets.
        --    See the README about individual language/framework/plugin snippets:
        --    https://github.com/rafamadriz/friendly-snippets
        {
          'rafamadriz/friendly-snippets',
          config = function()
            require('luasnip.loaders.from_vscode').lazy_load()
          end,
        },
      },
    },
    'saadparwaiz1/cmp_luasnip',

    -- Adds other completion capabilities.
    -- nvim-cmp does not ship with all sources by default. They are split
    -- into multiple repos for maintenance purposes.
    'hrsh7th/cmp-nvim-lsp',
    'hrsh7th/cmp-buffer',
    'hrsh7th/cmp-path',
    'hrsh7th/cmp-cmdline',
    'dmitmel/cmp-cmdline-history',
  },
  config = function()
    -- See `:help cmp`
    local cmp = require 'cmp'
    local luasnip = require 'luasnip'
    luasnip.config.setup {}

    -- Load custom snippets
    require 'snippets.sql'

    local kind_icons = {
      Text = '󰉿',
      Method = 'm',
      Function = '󰊕',
      Constructor = '',
      Field = '',
      Variable = '󰆧',
      Class = '󰌗',
      Interface = '',
      Module = '',
      Property = '',
      Unit = '',
      Value = '󰎠',
      Enum = '',
      Keyword = '󰌋',
      Snippet = '',
      Color = '󰏘',
      File = '󰈙',
      Reference = '',
      Folder = '󰉋',
      EnumMember = '',
      Constant = '󰇽',
      Struct = '',
      Event = '',
      Operator = '󰆕',
      TypeParameter = '󰊄',
      Copilot = '',
    }

    local palettes_ok, palettes = pcall(require, 'catppuccin.palettes')
    local mocha = palettes_ok and palettes.get_palette 'mocha' or nil
    local border_highlight = 'CmpBorder'

    if mocha then
      border_highlight = 'CmpBorderMocha'
      vim.api.nvim_set_hl(0, border_highlight, {
        fg = mocha.blue,
        bg = mocha.base,
      })
    end

    local border = require('utils.ui').border_hl(border_highlight)

    if mocha then
      vim.api.nvim_set_hl(0, 'CmpItemKindCopilot', { fg = mocha.teal })
    end

    -- Copilot happily suggests on a blank line (it reads the lines above and
    -- below), so an unguarded <Tab> would select a menu entry where you meant to
    -- indent. Gate menu navigation on there being a non-blank char behind the
    -- cursor.
    local function has_words_before()
      local line, col = unpack(vim.api.nvim_win_get_cursor(0))
      if col == 0 then
        return false
      end
      local text = vim.api.nvim_buf_get_lines(0, line - 1, line, true)[1]
      return text:sub(col, col):match '%s' == nil
    end

    -- `prioritize` floats Copilot's entries to the top of the group. pcall'd so
    -- cmp still comes up clean if copilot-cmp is ever removed.
    local comparators = {
      cmp.config.compare.offset,
      cmp.config.compare.exact,
      cmp.config.compare.score,
      cmp.config.compare.recently_used,
      cmp.config.compare.locality,
      cmp.config.compare.kind,
      cmp.config.compare.sort_text,
      cmp.config.compare.length,
      cmp.config.compare.order,
    }
    local copilot_cmp_ok, copilot_comparators = pcall(require, 'copilot_cmp.comparators')
    if copilot_cmp_ok then
      table.insert(comparators, 1, copilot_comparators.prioritize)
    end

    cmp.setup {
      sorting = {
        priority_weight = 2,
        comparators = comparators,
      },
      window = {
        documentation = {
          border = border,
        },
        completion = {
          border = border,
        },
      },
      snippet = {
        expand = function(args)
          luasnip.lsp_expand(args.body)
        end,
      },
      completion = { completeopt = 'menu,menuone,noinsert' },

      -- For an understanding of why these mappings were
      -- chosen, you will need to read `:help ins-completion`
      --
      -- No, but seriously. Please read `:help ins-completion`, it is really good!
      mapping = cmp.mapping.preset.insert {
        -- Select the [n]ext item
        ['<C-n>'] = cmp.mapping.select_next_item(),
        -- Select the [p]revious item
        ['<C-p>'] = cmp.mapping.select_prev_item(),

        -- Scroll the documentation window [b]ack / [f]orward
        ['<C-b>'] = cmp.mapping.scroll_docs(-4),
        ['<C-f>'] = cmp.mapping.scroll_docs(4),

        -- Accept ([y]es) the completion.
        --  This will auto-import if your LSP supports it.
        --  This will expand snippets if the LSP sent a snippet.
        ['<C-y>'] = cmp.mapping.confirm { select = true },

        -- If you prefer more traditional completion keymaps,
        -- you can uncomment the following lines
        --['<CR>'] = cmp.mapping.confirm { select = true },
        --['<Tab>'] = cmp.mapping.select_next_item(),
        --['<S-Tab>'] = cmp.mapping.select_prev_item(),

        -- Manually trigger a completion from nvim-cmp.
        --  Generally you don't need this, because nvim-cmp will display
        --  completions whenever it has completion options available.
        ['<C-Space>'] = cmp.mapping.complete {},

        -- Think of <c-l> as moving to the right of your snippet expansion.
        --  So if you have a snippet that's like:
        --  function $name($args)
        --    $body
        --  end
        --
        -- <c-l> will move you to the right of each of the expansion locations.
        -- <c-h> is similar, except moving you backwards.
        ['<C-l>'] = cmp.mapping(function()
          if luasnip.expand_or_locally_jumpable() then
            luasnip.expand_or_jump()
          end
        end, { 'i', 's' }),
        ['<C-h>'] = cmp.mapping(function()
          if luasnip.locally_jumpable(-1) then
            luasnip.jump(-1)
          end
        end, { 'i', 's' }),

        -- For more advanced Luasnip keymaps (e.g. selecting choice nodes, expansion) see:
        --    https://github.com/L3MON4D3/LuaSnip?tab=readme-ov-file#keymaps
        -- Select next/previous item with Tab / Shift + Tab
        ['<Tab>'] = cmp.mapping(function(fallback)
          if cmp.visible() and has_words_before() then
            cmp.select_next_item()
          elseif luasnip.expand_or_locally_jumpable() then
            luasnip.expand_or_jump()
          else
            fallback()
          end
        end, { 'i', 's' }),
        ['<S-Tab>'] = cmp.mapping(function(fallback)
          if cmp.visible() then
            cmp.select_prev_item()
          elseif luasnip.locally_jumpable(-1) then
            luasnip.jump(-1)
          else
            fallback()
          end
        end, { 'i', 's' }),
      },
      sources = {
        {
          name = 'lazydev',
          -- set group index to 0 to skip loading LuaLS completions as lazydev recommends it
          group_index = 0,
        },
        -- Deliberately left at the default group_index (1), the same group as
        -- nvim_lsp, rather than the `group_index = 2` copilot-cmp's README
        -- shows. cmp only falls through to a later group when every earlier one
        -- comes back empty, and the README's example puts *all* its sources in
        -- group 2 -- copying just this line would park Copilot in a group behind
        -- the LSP and it would surface only where the LSP had nothing to say.
        { name = 'copilot' },
        { name = 'nvim_lsp' },
        { name = 'luasnip' },
        { name = 'buffer' },
        { name = 'path' },
      },
      formatting = {
        fields = { 'kind', 'abbr', 'menu' },
        format = function(entry, vim_item)
          vim_item.kind = string.format('%s', kind_icons[vim_item.kind])
          vim_item.menu = ({
            copilot = '[Copilot]',
            nvim_lsp = '[LSP]',
            luasnip = '[Snippet]',
            buffer = '[Buffer]',
            path = '[Path]',
          })[entry.source.name]
          return vim_item
        end,
      },
      enabled = function()
        -- Enable cmp everywhere except prompt buffers, where it's usually noise.
        -- The one exception is a DAP prompt (the debug REPL): re-enable it there.
        -- Crucially, consult cmp_dap only if it's ALREADY loaded -- calling
        -- `require('cmp_dap')` unconditionally is what used to drag the whole
        -- nvim-dap stack (~220ms) into the first InsertEnter of every session.
        if vim.api.nvim_get_option_value('buftype', { buf = 0 }) ~= 'prompt' then
          return true
        end
        local cmp_dap = package.loaded['cmp_dap']
        return cmp_dap ~= nil and cmp_dap.is_dap_buffer()
      end,
    }

    -- Configure command-line completion once cmp is available.
    cmp.setup.cmdline(':', {
      mapping = cmp.mapping.preset.cmdline(),
      sources = cmp.config.sources({
        { name = 'path' },
      }, {
        { name = 'cmdline' },
        { name = 'cmdline_history' },
      }),
    })

    cmp.setup.cmdline({ '/', '?' }, {
      mapping = cmp.mapping.preset.cmdline(),
      sources = {
        { name = 'buffer' },
      },
    })

    -- Completion in DAP prompt buffers (the debug REPL / watch / hover prompts).
    -- Only the source *name* is referenced here -- a plain string, so this costs
    -- nothing and does NOT load nvim-dap. The actual 'dap' source is registered by
    -- cmp-dap, which is lazy-loaded on the dap-repl filetype (see plugins/cmp-dap).
    cmp.setup.filetype({ 'dap-repl', 'dapui_watches', 'dapui_hover' }, {
      sources = {
        { name = 'dap' },
      },
    })
  end,
}
