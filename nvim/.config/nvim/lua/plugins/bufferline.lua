return {
  'akinsho/bufferline.nvim',
  -- Bufferline isn't needed to draw the first frame; defer to just after UIEnter so
  -- it (and its devicons dep) stay off the startup path.
  event = 'VeryLazy',
  dependencies = {
    'nvim-tree/nvim-web-devicons', -- OPTIONAL: for file icons
  },
  opts = {
    -- Brighten the bufferline in two tiers and keep the file-type devicons in
    -- sync. bufferline clones each devicon's background from the tab's own
    -- highlight (buffer_selected / buffer_visible / background), so the only
    -- reliable way to recolour icon backgrounds is to hand bufferline the
    -- corrected backgrounds here rather than patching BufferLine* groups after
    -- setup. Passing a function means it re-runs on every catppuccin flavour
    -- (latte/mocha) switch, so both tiers track the theme automatically.
    highlights = function(defaults)
      local ok, ctp_bufferline = pcall(require, 'catppuccin.special.bufferline')
      if not ok then
        return defaults.highlights
      end

      local hls = ctp_bufferline.get_theme()()
      local C = require('catppuccin.palettes').get_palette()

      for _, hl in pairs(hls) do
        -- Tier 1: every tab's background (catppuccin's `mantle`) -> lighter `surface0`.
        -- Tier 2: the focused tab's background (catppuccin's `base`) -> brighter `surface1`.
        if hl.bg == C.mantle then
          hl.bg = C.surface0
        elseif hl.bg == C.base then
          hl.bg = C.surface1
        end
        -- Lift catppuccin's dim `surface1` tab text to the more legible `subtext1`.
        if hl.fg == C.surface1 then
          hl.fg = C.subtext1
        end
      end

      return hls
    end,
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
