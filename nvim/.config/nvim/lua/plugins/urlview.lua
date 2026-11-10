-- axieax/urlview.nvim — list every URL in the current buffer and open/yank them.
-- Uses Telescope as the picker, themed as a bare dropdown: a search input with the
-- results listed right below it and no preview pane.
return {
  'axieax/urlview.nvim',
  dependencies = { 'nvim-telescope/telescope.nvim' },
  cmd = 'UrlView',
  keys = {
    {
      '<leader>sU',
      function()
        require('urlview').search(
          'buffer',
          require('telescope.themes').get_dropdown {
            previewer = false,
            layout_config = { width = 0.6, height = 0.5 },
          }
        )
      end,
      desc = '[S]earch [U]RLs in buffer',
    },
  },
  -- lazy.nvim runs require('urlview').setup(opts) for us.
  opts = {
    default_picker = 'telescope',
  },
}
