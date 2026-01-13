-- Set leader key
vim.g.mapleader = ' '
vim.g.maplocalleader = ' '

-- Disable the spacebar key's default beheaviour in Normal and Visual modes
vim.keymap.set({ 'n', 'v' }, '<Space>', '<Nop>', { silent = true })

local opts = { noremap = true, silent = true }

-- Helper function to add description to opts
local function with_desc(desc)
  return vim.tbl_extend('keep', opts, { desc = desc })
end

-- Treat the largest window as the "main" editing target.
local function get_main_window()
  local main_win
  local main_area = 0
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    local cfg = vim.api.nvim_win_get_config(win)
    if cfg.relative == '' then
      local area = vim.api.nvim_win_get_width(win) * vim.api.nvim_win_get_height(win)
      if area > main_area then
        main_area = area
        main_win = win
      end
    end
  end
  return main_win
end

local function open_file_in_main_window()
  local file = vim.fn.expand '<cfile>'
  if file == '' then
    vim.cmd 'normal! gf'
    return
  end

  local main_win = get_main_window()
  local current_win = vim.api.nvim_get_current_win()
  if not main_win or not vim.api.nvim_win_is_valid(main_win) or main_win == current_win then
    vim.cmd 'normal! gf'
    return
  end

  vim.api.nvim_set_current_win(main_win)
  vim.cmd('edit ' .. vim.fn.fnameescape(file))
end

-- save file
vim.keymap.set('n', '<C-s>', '<cmd> w <CR>', opts)

vim.keymap.set('n', 'gf', open_file_in_main_window, with_desc 'Follow file link in main window')

-- save file without auto-formatting
vim.keymap.set('n', '<leader>sn', '<cmd>noautocmd w <CR>', with_desc 'Save without formatting')

-- quit file
vim.keymap.set('n', '<C-q>', '<cmd> q <CR>', opts)

-- delete single character without copying into register
vim.keymap.set('n', 'x', '"_x', opts)

-- Resize with arrows
vim.keymap.set('n', '<Up>', ':resize -2<CR>', opts)
vim.keymap.set('n', '<Down>', ':resize +2<CR>', opts)
vim.keymap.set('n', '<Left>', ':vertical resize -2<CR>', opts)
vim.keymap.set('n', '<Right>', ':vertical resize +2<CR>', opts)

-- Buffers
vim.keymap.set('n', '<Tab>', ':bnext<CR>', opts)
vim.keymap.set('n', '<S-Tab>', ':bprevious<CR>', opts)
vim.keymap.set('n', '<leader>x', ':bdelete!<CR>', with_desc 'Close buffer') -- close buffer
vim.keymap.set('n', '<leader>b', '<cmd> enew <CR>', with_desc 'New [B]uffer') -- new buffer

-- Window management
vim.keymap.set('n', '<leader>v', '<C-w>v', with_desc 'Split window [V]ertically') -- split window vertically
vim.keymap.set('n', '<leader>h', '<C-w>s', with_desc 'Split window [H]orizontally') -- split window horizontally
vim.keymap.set('n', '<leader>se', '<C-w>=', with_desc '[E]qualize [S]plit windows') -- make split windows equal width & height
vim.keymap.set('n', '<leader>xs', ':close<CR>', with_desc 'Close [S]plit window') -- close current split window

-- Navigate between splits
vim.keymap.set('n', '<C-k>', ':wincmd k<CR>', opts)
vim.keymap.set('n', '<C-j>', ':wincmd j<CR>', opts)
vim.keymap.set('n', '<C-h>', ':wincmd h<CR>', opts)
vim.keymap.set('n', '<C-l>', ':wincmd l<CR>', opts)

-- Tabs
vim.keymap.set('n', '<leader>to', ':tabnew<CR>', with_desc 'Open new [T]tab') -- open new tab
vim.keymap.set('n', '<leader>tx', ':tabclose<CR>', with_desc 'Close current [T]ab') -- close current tab
vim.keymap.set('n', '<leader>tn', ':tabn<CR>', with_desc 'Go to [N]ext [T]ab') --  go to next tab
vim.keymap.set('n', '<leader>tp', ':tabp<CR>', with_desc 'Go to [R]revious [T]ab') --  go to previous tab
vim.keymap.set('n', '<A-p>', '<Cmd>BufferPin<CR>', opts) -- pin/unpin buffer
vim.keymap.set('n', '<C-p>', '<Cmd>BufferPick<CR>', opts) -- pick a buffer
vim.keymap.set('n', '<C-A-p>', '<Cmd>BufferPickDelete<CR>', opts) -- pick a buffer
vim.keymap.set('n', '<A-<>', '<Cmd>BufferMovePrevious<CR>', opts) -- move buffer left
vim.keymap.set('n', '<A->>', '<Cmd>BufferMoveNext<CR>', opts) -- move buffer right

-- Stay in indent mode
vim.keymap.set('v', '<', '<gv', opts)
vim.keymap.set('v', '>', '>gv', opts)

-- Diagnostic keymaps
vim.keymap.set('n', '[d', function()
  vim.diagnostic.jump { count = -1, float = true }
end, { desc = 'Go to previous diagnostic message' })

vim.keymap.set('n', ']d', function()
  vim.diagnostic.jump { count = 1, float = true }
end, { desc = 'Go to next diagnostic message' })

-- TODO keymaps
vim.keymap.set('n', ']t', function()
  require('todo-comments').jump_next()
end, { desc = 'Next todo comment' })

vim.keymap.set('n', '[t', function()
  require('todo-comments').jump_prev()
end, { desc = 'Previous todo comment' })

-- vim.keymap.set('n', '<leader>d', vim.diagnostic.open_float, { desc = 'Open floating diagnostic message' })
-- vim.keymap.set('n', '<leader>q', vim.diagnostic.setloclist, { desc = 'Open diagnostics list' })

-- Toggle Terminal
vim.keymap.set('n', '<leader>tt', '<cmd> ToggleTerm size=20 direction=horizontal <CR>', with_desc '[T]oggle [T]erminal')

function _G.set_terminal_keymaps()
  local opts = { buffer = 0 }
  vim.keymap.set('t', '<esc>', [[<C-\><C-n>]], opts)
  vim.keymap.set('t', 'jk', [[<C-\><C-n>]], opts)
  vim.keymap.set('t', '<C-h>', [[<Cmd>wincmd h<CR>]], opts)
  vim.keymap.set('t', '<C-j>', [[<Cmd>wincmd j<CR>]], opts)
  vim.keymap.set('t', '<C-k>', [[<Cmd>wincmd k<CR>]], opts)
  vim.keymap.set('t', '<C-l>', [[<Cmd>wincmd l<CR>]], opts)
  vim.keymap.set('t', '<C-w>', [[<C-\><C-n><C-w>]], opts)
end

-- if you only want these mappings for toggle term use term://*toggleterm#* instead
vim.cmd 'autocmd! TermOpen term://*toggleterm#* lua set_terminal_keymaps()'

vim.keymap.set('n', '<C-S-q>', ':Gdiffsplit<CR>', opts) -- staged version vs working tree view of file
vim.keymap.set('n', '<leader>gb', ':G blame<CR>', with_desc '[G]it [B]lame') -- view git blame line by line (hint: hit key p to view the details in separate pane)

-- nvim-tree global
vim.keymap.set('n', '<leader>e', ':NvimTreeToggle<cr>', with_desc '[T]oggle file tree')

-- search and replace word under cursor (press n to go to next occurrence followed by . to replace all)
vim.keymap.set('n', '<leader>j', [[:%s/\<<C-r><C-w>\>/<C-r><C-w>/gI<Left><Left><Left>]], with_desc 'Search and replace word under cursor')

-- mapping visual block mode to Atl + V
vim.keymap.set('n', '<A-v>', '<C-v>', opts)

-- load last session (refer to https://github.com/folke/persistence.nvim)
vim.keymap.set('n', '<leader>ql', function()
  require('persistence').load { last = true }
end, with_desc 'Load last session')

-- load session for current working directory (refer to https://github.com/folke/persistence.nvim)
vim.keymap.set('n', '<leader>qc', function()
  require('persistence').load()
end, with_desc 'Load session for cwd')

-- select a session to load (refer to https://github.com/folke/persistence.nvim)
vim.keymap.set('n', '<leader>qS', function()
  require('persistence').select()
end, with_desc 'Select [S]ession')

-- jump to the top of the context window
vim.keymap.set('n', '[c', function()
  require('treesitter-context').go_to_context(vim.v.count1)
end, { silent = true })

vim.keymap.set('n', '<leader>wd', ':AppendDiary<CR>', { desc = 'Append daily diary entry' })

-- neotest keymaps
vim.keymap.set('n', '<leader>nr', function()
  require('neotest').run.run()
end, with_desc '[R]un nearest test')

vim.keymap.set('n', '<leader>nf', function()
  require('neotest').run.run(vim.fn.expand '%')
end, with_desc 'Run current [f]ile')

vim.keymap.set('n', '<leader>na', function()
  require('neotest').run.run { suite = true }
end, with_desc 'Run [a]ll tests')

vim.keymap.set('n', '<leader>nd', function()
  require('neotest').run.run { strategy = 'dap' }
end, with_desc '[D]ebug nearest test')

vim.keymap.set('n', '<leader>ns', function()
  require('neotest').run.stop()
end, with_desc '[S]top test')

vim.keymap.set('n', '<leader>nn', function()
  require('neotest').run.attach()
end, with_desc 'Attach to [n]earest test')

vim.keymap.set('n', '<leader>no', function()
  require('neotest').output.open()
end, with_desc 'Show test [o]utput')

vim.keymap.set('n', '<leader>np', function()
  require('neotest').output_panel.toggle()
end, with_desc 'Toggle output [p]anel')

vim.keymap.set('n', '<leader>nv', function()
  require('neotest').summary.toggle()
end, with_desc 'Toggle test summary')

vim.keymap.set('n', '<leader>nc', function()
  require('neotest').run.run { suite = true, env = { CI = true } }
end, with_desc 'Run all tests with CI')

vim.keymap.set('n', '<leader>yp', function()
  vim.fn.setreg('+', vim.fn.expand '%:p')
  print('Copied: ' .. vim.fn.expand '%:p')
end, { desc = '[Y]ank absolute [P]ath' })
