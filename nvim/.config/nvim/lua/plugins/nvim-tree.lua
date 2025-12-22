local function on_attach(bufnr)
  local api = require 'nvim-tree.api'

  local function opts(desc)
    return { desc = 'nvim-tree: ' .. desc, buffer = bufnr, noremap = true, silent = true, nowait = true }
  end

  -- default mappings
  api.config.mappings.default_on_attach(bufnr)

  -- automatically open a file upon creation
  api.events.subscribe(api.events.Event.FileCreated, function(file)
    vim.cmd('edit ' .. vim.fn.fnameescape(file.fname))
  end)

  -- custom mappings
  vim.keymap.set('n', '?', api.tree.toggle_help, opts 'Help')
  vim.keymap.set('n', '<CR>', api.node.open.tab_drop, opts 'Tab drop')
end

local function setup_pymple_integration()
  local ok_tree, tree_api = pcall(require, 'nvim-tree.api')
  if not ok_tree then
    return
  end

  local Event = tree_api.events.Event

  tree_api.events.subscribe(Event.NodeRenamed, function(data)
    if not data or not data.old_name or not data.new_name then
      return
    end

    local ok_pymple_api, pymple_api = pcall(require, 'pymple.api')
    if not ok_pymple_api then
      return
    end

    local ok_pymple_config, pymple_config = pcall(require, 'pymple.config')
    if not ok_pymple_config or not pymple_config.user_config then
      return
    end

    local opts = pymple_config.user_config.update_imports
    if not opts then
      return
    end

    pymple_api.update_imports(data.old_name, data.new_name, opts)
  end)
end

return {
  'nvim-tree/nvim-tree.lua',
  version = '*',
  lazy = false,
  dependencies = {
    'nvim-tree/nvim-web-devicons',
  },
  config = function()
    require('nvim-tree').setup {
      on_attach = on_attach,
      hijack_cursor = false,
      auto_reload_on_write = true,
      disable_netrw = false,
      hijack_netrw = true,
      hijack_unnamed_buffer_when_opening = false,
      root_dirs = {},
      prefer_startup_root = false,
      sync_root_with_cwd = false,
      reload_on_bufenter = false,
      respect_buf_cwd = false,
      select_prompts = false,
      sort = {
        sorter = 'name',
        folders_first = true,
        files_first = false,
      },
      view = {
        centralize_selection = false,
        cursorline = true,
        cursorlineopt = 'both',
        debounce_delay = 15,
        side = 'left',
        preserve_window_proportions = false,
        number = false,
        relativenumber = false,
        signcolumn = 'yes',
        width = 30,
        float = {
          enable = false,
          quit_on_focus_loss = true,
          open_win_config = {
            relative = 'editor',
            border = 'rounded',
            width = 30,
            height = 30,
            row = 1,
            col = 1,
          },
        },
      },
      renderer = {
        add_trailing = false,
        group_empty = false,
        full_name = false,
        root_folder_label = ':~:s?$?/..?',
        indent_width = 3,
        special_files = { 'Cargo.toml', 'Makefile', 'README.md', 'readme.md' },
        hidden_display = 'none',
        symlink_destination = true,
        decorators = { 'Git', 'Open', 'Hidden', 'Modified', 'Bookmark', 'Diagnostics', 'Copied', 'Cut' },
        highlight_git = 'name',
        highlight_diagnostics = 'none',
        highlight_opened_files = 'none',
        highlight_modified = 'none',
        highlight_hidden = 'none',
        highlight_bookmarks = 'none',
        highlight_clipboard = 'name',
        indent_markers = {
          enable = true,
          inline_arrows = true,
          icons = {
            corner = '└',
            edge = '│',
            item = '│',
            bottom = '─',
            none = ' ',
          },
        },
        icons = {
          web_devicons = {
            file = {
              enable = true,
              color = true,
            },
            folder = {
              enable = false,
              color = true,
            },
          },
          git_placement = 'after',
          modified_placement = 'after',
          hidden_placement = 'after',
          diagnostics_placement = 'signcolumn',
          bookmarks_placement = 'signcolumn',
          padding = {
            icon = ' ',
            folder_arrow = ' ',
          },
          symlink_arrow = ' ➛ ',
          show = {
            file = true,
            folder = true,
            folder_arrow = true,
            git = true,
            modified = true,
            hidden = false,
            diagnostics = true,
            bookmarks = true,
          },
          glyphs = {
            default = '',
            symlink = '',
            bookmark = '󰆤',
            modified = '●',
            hidden = '󰜌',
            folder = {
              arrow_closed = '',
              arrow_open = '',
              default = '',
              open = '',
              empty = '',
              empty_open = '',
              symlink = '',
              symlink_open = '',
            },
            git = {
              unstaged = '✗',
              staged = '✓',
              unmerged = '',
              renamed = '➜',
              untracked = '★',
              deleted = '',
              ignored = '◌',
            },
          },
        },
      },
      hijack_directories = {
        enable = true,
        auto_open = true,
      },
      update_focused_file = {
        enable = false,
        update_root = {
          enable = false,
          ignore_list = {},
        },
        exclude = false,
      },
      system_open = {
        cmd = '',
        args = {},
      },
      git = {
        enable = true,
        show_on_dirs = true,
        show_on_open_dirs = true,
        disable_for_dirs = {},
        timeout = 400,
        cygwin_support = false,
      },
      diagnostics = {
        enable = false,
        show_on_dirs = false,
        show_on_open_dirs = true,
        debounce_delay = 500,
        severity = {
          min = vim.diagnostic.severity.HINT,
          max = vim.diagnostic.severity.ERROR,
        },
        icons = {
          hint = '',
          info = '',
          warning = '',
          error = '',
        },
      },
      modified = {
        enable = false,
        show_on_dirs = true,
        show_on_open_dirs = true,
      },
      filters = {
        enable = true,
        git_ignored = true,
        dotfiles = false,
        git_clean = false,
        no_buffer = false,
        no_bookmark = false,
        custom = {},
        exclude = {},
      },
      live_filter = {
        prefix = '[FILTER]: ',
        always_show_folders = true,
      },
      filesystem_watchers = {
        enable = true,
        debounce_delay = 50,
        ignore_dirs = {
          '/.ccls-cache',
          '/build',
          '/node_modules',
          '/target',
        },
      },
      actions = {
        use_system_clipboard = true,
        change_dir = {
          enable = true,
          global = false,
          restrict_above_cwd = false,
        },
        expand_all = {
          max_folder_discovery = 300,
          exclude = {},
        },
        file_popup = {
          open_win_config = {
            col = 1,
            row = 1,
            relative = 'cursor',
            border = 'shadow',
            style = 'minimal',
          },
        },
        open_file = {
          quit_on_open = false,
          eject = true,
          resize_window = true,
          relative_path = true,
          window_picker = {
            enable = true,
            picker = 'default',
            chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ1234567890',
            exclude = {
              filetype = { 'notify', 'packer', 'qf', 'diff', 'fugitive', 'fugitiveblame' },
              buftype = { 'nofile', 'terminal', 'help' },
            },
          },
        },
        remove_file = {
          close_window = true,
        },
      },
      trash = {
        cmd = 'gio trash',
      },
      tab = {
        sync = {
          open = false,
          close = false,
          ignore = {},
        },
      },
      notify = {
        threshold = vim.log.levels.INFO,
        absolute_path = true,
      },
      help = {
        sort_by = 'key',
      },
      ui = {
        confirm = {
          remove = true,
          trash = true,
          default_yes = false,
        },
      },
      experimental = {},
      log = {
        enable = false,
        truncate = false,
        types = {
          all = false,
          config = false,
          copy_paste = false,
          dev = false,
          diagnostics = false,
          git = false,
          profile = false,
          watcher = false,
        },
      },
    } -- END_DEFAULT_OPTS

    vim.api.nvim_create_autocmd('BufEnter', {
      callback = function()
        if vim.bo.filetype == 'NvimTree' then
          vim.wo.statuscolumn = ''
        end
      end,
    })

    -- forward rename events to pymple so python imports stay in sync
    if not vim.g._pymple_nvim_tree_renamed_hook then
      setup_pymple_integration()
      vim.g._pymple_nvim_tree_renamed_hook = true
    end
  end,
}
