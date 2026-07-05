return {
  'akinsho/bufferline.nvim',
  -- Bufferline isn't needed to draw the first frame; defer to just after UIEnter so
  -- it (and its devicons dep) stay off the startup path.
  event = 'VeryLazy',
  dependencies = {
    'nvim-tree/nvim-web-devicons', -- OPTIONAL: for file icons
  },
  opts = {
    options = {
      mode = 'buffers',
      themable = true,

      -- Click behaviour (barbar parity: left-click focuses, middle-click deletes).
      left_mouse_command = 'buffer %d',
      middle_mouse_command = 'bdelete! %d',
      close_command = 'bdelete! %d',
      right_mouse_command = 'bdelete! %d',

      -- The slanted look from the bufferline README screenshot.
      separator_style = 'slant',

      indicator = { style = 'icon', icon = '▎' },
      buffer_close_icon = '󰅖',
      modified_icon = '●',
      close_icon = '',
      left_trunc_marker = '',
      right_trunc_marker = '',

      max_name_length = 30,
      max_prefix_length = 15,
      truncate_names = true,
      tab_size = 18,

      -- LSP diagnostics on the tabs (barbar showed ERROR + HINT).
      diagnostics = 'nvim_lsp',
      diagnostics_update_in_insert = false,
      diagnostics_indicator = function(count, level)
        local icon = level:match 'error' and '󰅚 ' or '󰌶 '
        return ' ' .. icon .. count
      end,

      -- The "File Explorer" gap on the left from the screenshot.
      offsets = {
        {
          filetype = 'NvimTree',
          text = 'File Explorer',
          text_align = 'left',
          highlight = 'Directory',
          separator = true,
        },
      },

      color_icons = true,
      show_buffer_icons = true,
      show_buffer_close_icons = true,
      show_close_icon = false,
      show_tab_indicators = true,

      persist_buffer_sort = true, -- keep manual BufferLineMove order across sessions
      sort_by = 'insert_after_current',
      always_show_bufferline = true,
    },
  },
  config = function(_, opts)
    require('bufferline').setup(opts)
    -- Highlights are driven by catppuccin's `bufferline` integration (see
    -- colortheme.lua), which refreshes the BufferLine* groups on the
    -- latte/mocha (light/dark) flavour switch — no manual re-tinting needed.
  end,
}
