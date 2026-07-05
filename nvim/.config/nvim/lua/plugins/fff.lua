local ui = require 'utils.ui'

return {
  'dmtrKovalenko/fff.nvim',
  build = function()
    -- downloads a prebuilt binary or falls back to cargo build
    require('fff.download').download_or_build_binary()
  end,
  -- for nixos:
  -- build = "nix run .#release",
  opts = {
    -- Mirror the telescope picker feel: prompt on top, preview on the right,
    -- single-style borders from utils.ui (single source of truth for box style).
    layout = {
      prompt_position = 'top',
      preview_position = 'right',
      border = ui.border,
      flex = { size = 130, wrap = 'top' },
    },
    -- Reuse catppuccin's telescope highlight groups so the fff picker is visually
    -- identical to the telescope pickers and tracks the `flavour = 'auto'`
    -- light/dark switch automatically (no hardcoded hex). Only the slots that
    -- have a telescope counterpart are overridden; the rest keep fff's defaults.
    hl = {
      normal = 'TelescopeNormal',
      border = 'TelescopeBorder',
      title = 'TelescopePromptTitle',
      prompt = 'TelescopePromptPrefix',
      cursor = 'TelescopeSelection',
      -- Background-only match highlight (defined in `config` below): keeps each
      -- matched span's own foreground and paints a visible band behind it.
      matched = 'FFFMatch',
      grep_match = 'FFFMatch',
      directory_path = 'TelescopeResultsComment',
    },
    debug = {
      enabled = true,
      show_scores = true,
    },
  },
  config = function(_, opts)
    require('fff').setup(opts)

    -- `FFFMatch` borrows the active theme's Search *background* but drops its
    -- foreground, so a match reads like a search hit while its text keeps its
    -- own color (readable regardless of what it sits on). Re-derived on
    -- ColorScheme so it tracks the `flavour = 'auto'` light/dark switch.
    local group = vim.api.nvim_create_augroup('FFFMatchHl', { clear = true })
    local function set_match_hl()
      local search = vim.api.nvim_get_hl(0, { name = 'Search', link = false })
      vim.api.nvim_set_hl(0, 'FFFMatch', { bg = search.bg or '#585b70' })
    end
    set_match_hl()
    vim.api.nvim_create_autocmd('ColorScheme', { group = group, callback = set_match_hl })
  end,
  lazy = false, -- the plugin lazy-initialises itself
  -- Telescope-style keymaps, repointed at fff. The file/grep surface (and only
  -- that surface) lives here now; everything else still runs through telescope.
  keys = {
    {
      '<leader>sf',
      function()
        require('fff').find_files()
      end,
      desc = '[S]earch [F]iles',
    },
    {
      '<leader>sg',
      function()
        require('fff').live_grep()
      end,
      desc = '[S]earch by [G]rep',
    },
    {
      '<leader>sw',
      function()
        require('fff').live_grep_under_cursor()
      end,
      mode = { 'n', 'x' },
      desc = '[S]earch current [W]ord',
    },
    {
      '<leader>sn',
      function()
        require('fff').find_files_in_dir(vim.fn.stdpath 'config')
      end,
      desc = '[S]earch [N]eovim files',
    },
  },
}
