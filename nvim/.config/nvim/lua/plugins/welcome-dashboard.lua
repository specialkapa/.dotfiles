---@return table
local function layout()
  ---@param sc string
  ---@param icon string
  ---@param desc string
  ---@param icon_color string?
  ---@param keybind string?
  ---@param keybind_opts table?
  ---@param opts table?
  ---@return table
  local function button(sc, icon, desc, icon_color, keybind, keybind_opts, opts)
    local def_opts = {
      cursor = 3,
      align_shortcut = 'right',
      hl_shortcut = 'AlphaButtonShortcut',
      hl = 'AlphaButton',
      width = 35,
      position = 'center',
    }
    opts = opts and vim.tbl_extend('force', def_opts, opts) or def_opts
    opts.shortcut = sc
    local val = string.format('%s  %s', icon, desc)
    if icon_color then
      local icon_bytes = #icon
      if type(opts.hl) == 'string' then
        local button_hl = opts.hl
        opts.hl = {
          { icon_color, 0, icon_bytes },
          { button_hl, icon_bytes, #val },
        }
      elseif type(opts.hl) == 'table' then
        table.insert(opts.hl, 1, { icon_color, 0, icon_bytes })
      else
        opts.hl = { { icon_color, 0, icon_bytes } }
      end
    end
    local sc_ = sc:gsub('%s', ''):gsub('SPC', '<Leader>')
    local on_press = function()
      local key = vim.api.nvim_replace_termcodes(keybind or sc_ .. '<Ignore>', true, false, true)
      vim.api.nvim_feedkeys(key, 't', false)
    end
    if keybind then
      keybind_opts = vim.F.if_nil(keybind_opts, { noremap = true, silent = true, nowait = true })
      opts.keymap = { 'n', sc_, keybind, keybind_opts }
    end
    return { type = 'button', val = val, on_press = on_press, opts = opts }
  end

  local function system_icon()
    return ''
  end

  math.randomseed(os.time())
  local header_color = 'AlphaCol' .. math.random(11)

  local header_lines = {
    [[                                                                       ]],
    [[                                                                     ]],
    [[       ████ ██████           █████      ██                     ]],
    [[      ███████████             █████                             ]],
    [[      █████████ ███████████████████ ███   ███████████   ]],
    [[     █████████  ███    █████████████ █████ ██████████████   ]],
    [[    █████████ ██████████ █████████ █████ █████ ████ █████   ]],
    [[  ███████████ ███    ███ █████████ █████ █████ ████ █████  ]],
    [[ ██████  █████████████████████ ████ █████ █████ ████ ██████ ]],
    [[                                                                       ]],
  }

  -- https://github.com/goolord/alpha-nvim/issues/105
  local lazycache = setmetatable({}, {
    __newindex = function(table, index, fn)
      assert(type(fn) == 'function')
      getmetatable(table)[index] = fn
    end,
    __call = function(table, index)
      return function()
        return table[index]
      end
    end,
    __index = function(table, index)
      local fn = getmetatable(table)[index]
      if fn then
        local value = fn()
        rawset(table, index, value)
        return value
      end
    end,
  })

  ---@return table
  lazycache.info = function()
    local v = vim.version()
    local datetime = os.date ' %d-%m-%Y   %H:%M:%S'
    local top_line = string.format('%s nvim v%d.%d.%d  %s', system_icon(), v.major, v.minor, v.patch, datetime)
    return {
      {
        type = 'text',
        val = top_line,
        opts = { hl = header_color, position = 'center' },
      },
    }
  end

  ---@return table
  lazycache.menu = function()
    return {
      button('󱁐 wd', '', 'add vimwiki diary entry', 'AlphaIconGreen'),
      button('󱁐 s.', '', 'find recent files', 'AlphaIconSky'),
      button('󱁐 sf', '', 'find file', 'AlphaIconSky'),
      button('󱁐 sg', '', 'find reference', 'AlphaIconMauve'),
      button('󱁐 ql', '', 'load last session', 'AlphaIconLavender'),
      button('󱁐 e ', '', 'toggle file tree', 'AlphaIconYellow'),
      button('n ', '', 'new file', 'AlphaIconPeach', '<Cmd>ene<CR>'),
      button('p ', '', 'plugins', 'AlphaIconPink', '<Cmd>Lazy<CR>'),
      button('q ', '', 'quit', 'AlphaIconRed', '<Cmd>qa<CR>'),
    }
  end

  ---@return table
  lazycache.mru = function()
    local result = {}
    for _, filename in ipairs(vim.v.oldfiles) do
      if vim.loop.fs_stat(filename) ~= nil then
        local icon, hl = require('nvim-web-devicons').get_icon(filename, vim.fn.fnamemodify(filename, ':e'))
        icon = icon or ''
        hl = hl or 'Normal'
        local filename_short = string.sub(vim.fn.fnamemodify(filename, ':t'), 1, 30)
        table.insert(result, button(tostring(#result + 1), icon, filename_short, hl, string.format('<Cmd>e %s<CR>', filename), nil, { hl = 'Normal' }))
        if #result == 9 then
          break
        end
      end
    end
    return result
  end

  ---@return table
  lazycache.fortune = function()
    return require 'alpha.fortune'()
  end

  return {
    { type = 'padding', val = 1 },
    {
      type = 'text',
      val = header_lines,
      opts = { hl = header_color, position = 'center' },
    },
    { type = 'padding', val = 1 },
    {
      type = 'group',
      val = lazycache 'info',
      opts = { spacing = 1 },
    },
    { type = 'padding', val = 2 },
    {
      type = 'group',
      val = lazycache 'menu',
      opts = { spacing = 0 },
    },
    { type = 'padding', val = 1 },
    {
      type = 'group',
      val = lazycache 'mru',
      opts = { spacing = 0 },
    },
    { type = 'padding', val = 1 },
    {
      type = 'text',
      val = lazycache 'fortune',
      opts = { hl = 'AlphaQuote', position = 'center' },
    },
  }
end

local default_statuscolumn = vim.o.statuscolumn
local alpha_statuscolumn = ' %s'

return {
  'goolord/alpha-nvim',
  event = 'VimEnter',
  config = function()
    local function setup_icon_highlights()
      local ok, palettes = pcall(require, 'catppuccin.palettes')
      if not ok then
        return
      end
      local palette = palettes.get_palette 'mocha'
      local icon_colors = {
        AlphaIconBlue = palette.blue,
        AlphaIconGreen = palette.green,
        AlphaIconLavender = palette.lavender,
        AlphaIconMauve = palette.mauve,
        AlphaIconPink = palette.pink,
        AlphaIconPeach = palette.peach,
        AlphaIconRed = palette.red,
        AlphaIconSky = palette.sky,
        AlphaIconTeal = palette.teal,
        AlphaIconYellow = palette.yellow,
      }
      for group, color in pairs(icon_colors) do
        if color then
          vim.api.nvim_set_hl(0, group, { fg = color, bold = true })
        end
      end
    end

    setup_icon_highlights()
    require('alpha').setup {
      layout = layout(),
      opts = {
        setup = function()
          vim.api.nvim_create_autocmd('User', {
            pattern = 'AlphaReady',
            desc = 'Disable status and tabline for alpha',
            callback = function()
              vim.go.laststatus = 0
              vim.opt.showtabline = 0
              vim.opt_local.statuscolumn = alpha_statuscolumn
            end,
          })
          vim.api.nvim_create_autocmd('BufUnload', {
            buffer = 0,
            desc = 'Enable status and tabline after alpha',
            callback = function()
              vim.go.laststatus = 3
              vim.opt.showtabline = 2
              vim.opt_local.statuscolumn = default_statuscolumn
            end,
          })
        end,
        margin = 5,
      },
    }
  end,
}
