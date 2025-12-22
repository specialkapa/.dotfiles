local word_highlights = {}

---@type Neominimap.Map.Handler
local word_handler = {
  name = 'Word Highlights',
  mode = 'line',
  namespace = vim.api.nvim_create_namespace 'neominimap_word',

  init = function()
    local base_color = '#404040'
    local current_color = '#906060'

    local hl = vim.api.nvim_get_hl(0, { name = 'CursorLine', link = false })
    if hl.bg then
      base_color = string.format('#%06x', hl.bg)

      local brighten = function(channel)
        return math.min(255, math.floor(channel + channel * 0.3))
      end

      local r = math.floor(hl.bg / 0x10000) % 0x100
      local g = math.floor(hl.bg / 0x100) % 0x100
      local b = hl.bg % 0x100

      r, g, b = brighten(r), brighten(g), brighten(b)
      current_color = string.format('#%02x%02x%02x', r, g, b)
    end

    vim.api.nvim_set_hl(0, 'NeominimapWordLine', { bg = base_color, default = true })
    vim.api.nvim_set_hl(0, 'NeominimapWordSign', { fg = base_color, default = true })
    vim.api.nvim_set_hl(0, 'NeominimapWordIcon', { fg = base_color, default = true })

    vim.api.nvim_set_hl(0, 'NeominimapCurrentWordLine', { bg = current_color, default = true })
    vim.api.nvim_set_hl(0, 'NeominimapCurrentWordSign', { fg = current_color, default = true })
    vim.api.nvim_set_hl(0, 'NeominimapCurrentWordIcon', { fg = current_color, default = true })
  end,

  autocmds = {
    {
      event = { 'CursorHold', 'CursorHoldI' },
      opts = {
        desc = 'Update word highlights when cursor moves',
        callback = function(apply)
          local winid = vim.api.nvim_get_current_win()
          if not winid or not vim.api.nvim_win_is_valid(winid) then
            return
          end

          local bufnr = vim.api.nvim_win_get_buf(winid)
          vim.schedule(function()
            if bufnr and vim.api.nvim_buf_is_valid(bufnr) then
              local word = vim.fn.expand '<cword>'
              if word ~= '' then
                local key = string.format('%d:%s', bufnr, word)
                local tick = vim.api.nvim_buf_get_changedtick(bufnr)
                local cached = word_highlights[key]

                if not cached or cached.tick ~= tick then
                  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, true)
                  local positions = {}
                  for lnum, line in ipairs(lines) do
                    if line:find(word, 1, true) then
                      positions[#positions + 1] = lnum
                    end
                  end
                  word_highlights[key] = {
                    positions = positions,
                    tick = tick,
                  }
                end
              end

              apply(bufnr)
            end
          end)
        end,
      },
    },
  },

  get_annotations = function(bufnr)
    if not vim.api.nvim_buf_is_valid(bufnr) then
      return {}
    end

    local word = ''
    vim.api.nvim_buf_call(bufnr, function()
      word = vim.fn.expand '<cword>' or ''
    end)

    if word == '' then
      return {}
    end

    local key = string.format('%d:%s', bufnr, word)
    local cached = word_highlights[key]
    if not cached then
      return {}
    end

    local current_line = 0
    vim.api.nvim_buf_call(bufnr, function()
      current_line = vim.fn.line '.'
    end)

    local annotations = {}
    for _, lnum in ipairs(cached.positions) do
      annotations[#annotations + 1] = {
        lnum = lnum,
        end_lnum = lnum,
        priority = 25,
        id = 1,
        highlight = (lnum == current_line) and 'NeominimapCurrentWordLine' or 'NeominimapWordLine',
      }
    end

    return annotations
  end,
}

return {
  'Isrothy/neominimap.nvim',
  version = 'v3.x.x',
  lazy = false, -- NOTE: NO NEED to Lazy load
  init = function()
    -- The following options are recommended when layout == "float"
    vim.opt.wrap = false
    vim.opt.sidescrolloff = 36 -- Set a large value

    --- Put your configuration here
    ---@type Neominimap.UserConfig
    vim.g.neominimap = {
      auto_enable = true,
      handlers = { word_handler },
      winopt = function(opt)
        opt.number = false
        opt.relativenumber = false
        opt.statuscolumn = ''
      end,
    }
  end,
}
