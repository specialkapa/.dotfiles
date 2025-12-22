return {
  'catppuccin/nvim',
  name = 'catppuccin',
  priority = 1000,
  config = function()
    local catppuccin = require 'catppuccin'

    local base_config = {
      flavour = 'auto',
      background = {
        light = 'latte',
        dark = 'mocha',
      },
      transparent_background = false,
      float = {
        transparent = true,
        solid = false,
      },
      show_end_of_buffer = false,
      term_colors = false,
      dim_inactive = {
        enabled = false,
        shade = 'dark',
        percentage = 0.15,
      },
      no_italic = false,
      no_bold = false,
      no_underline = false,
      styles = {
        comments = { 'italic' },
        conditionals = { 'italic' },
        loops = {},
        functions = {},
        keywords = {},
        strings = {},
        variables = {},
        numbers = {},
        booleans = {},
        properties = {},
        types = {},
        operators = {},
        -- miscs = {}, -- Uncomment to turn off hard-coded styles
      },
      lsp_styles = {
        virtual_text = {
          errors = { 'italic' },
          hints = { 'italic' },
          warnings = { 'italic' },
          information = { 'italic' },
          ok = { 'italic' },
        },
        underlines = {
          errors = { 'underline' },
          hints = { 'underline' },
          warnings = { 'underline' },
          information = { 'underline' },
          ok = { 'underline' },
        },
        inlay_hints = {
          background = true,
        },
      },
      color_overrides = {},
      custom_highlights = nil,
      default_integrations = true,
      auto_integrations = false,
      integrations = {
        barbar = true,
        cmp = true,
        gitsigns = true,
        nvimtree = true,
        notify = true,
        grug_fare = false,
        noice = false,
        neotest = true,
        dap = true,
        dap_ui = true,
        trouble = true,
        which_key = false,
        mini = {
          enabled = true,
          indentscope_color = '',
        },
        -- For more plugins integrations please scroll down (https://github.com/catppuccin/nvim#integrations)
      },
    }

    local transparency_enabled = base_config.transparent_background or false

    local function git_blame_custom_highlights(colors)
      local float_bg = base_config.transparency_enabled

      return {
        GitBlameFloat = { bg = float_bg, fg = colors.text },
        GitBlameFloatTitle = { bg = float_bg, fg = colors.sky, bold = true },
        GitBlameFloatBorder = { bg = float_bg, fg = colors.sky },
        GitBlameFloatTitleIcon = { bg = float_bg, fg = colors.red, bold = true },
        GitBlameFloatAuthor = { bg = float_bg, fg = colors.lavender, bold = true },
        GitBlameFloatMessage = { bg = float_bg, fg = colors.text },
        GitBlameFloatHash = { bg = float_bg, fg = colors.mauve },
        GitBlameFloatStatsFilesChanged = { bg = float_bg, fg = colors.text },
        GitBlameFloatStatsInsertions = { bg = float_bg, fg = colors.green },
        GitBlameFloatStatsDeletions = { bg = float_bg, fg = colors.red },
        GitBlameFloatHelp = { bg = float_bg, fg = colors.overlay1, italic = true },
        GitBlameURL = { fg = colors.blue, underline = true },
        WinSeparator = { fg = colors.blue },
        -- Ensure neominimap honors Catppuccin's dimming for inactive windows
        NeominimapBackground = { link = 'NormalNC' },
      }
    end

    base_config.custom_highlights = git_blame_custom_highlights

    local function apply_theme()
      local config = vim.deepcopy(base_config)
      config.transparent_background = transparency_enabled
      config.custom_highlights = base_config.custom_highlights

      catppuccin.setup(config)
      vim.cmd.colorscheme 'catppuccin'
    end

    apply_theme()

    vim.keymap.set('n', '<leader>bg', function()
      transparency_enabled = not transparency_enabled
      apply_theme()
    end, { desc = 'Toggle background transparency', noremap = true, silent = true })
  end,
}
