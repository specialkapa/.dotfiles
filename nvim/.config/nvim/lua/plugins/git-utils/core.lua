return {
  {
    -- powerful git integration for vim
    'tpope/vim-fugitive',
    vim.keymap.set('n', '<leader>gu', '<cmd>gbrowse<cr>', { desc = '[g]it open file [u]rl' }),
  },
  {
    -- GitHub integration for vim-fugitive
    'tpope/vim-rhubarb',
  },
  {
    'f-person/git-blame.nvim',
    lazy = true,
    opts = {
      enabled = true,
      message_template = ' <summary>, <date>, <author>, <<sha>>',
      date_format = '%Y-%m-%d %H:%M:%S',
      display_virtual_text = 0,
      use_blame_commit_file_urls = true,
      message_when_not_committed = ' still cooking!',
    },
    vim.keymap.set('n', '<leader>gcu', '<cmd>GitBlameOpenCommitURL<cr>', { desc = '[G]it Blame Open File [U]RL' }),
  },
  {
    'lewis6991/gitsigns.nvim',
    event = { 'BufReadPre', 'BufNewFile' },
    opts = {
      signs = {
        add = { text = '+' },
        change = { text = '~' },
        delete = { text = '_' },
        topdelete = { text = '‾' },
        changedelete = { text = '~' },
      },
      signs_staged = {
        add = { text = '+' },
        change = { text = '~' },
        delete = { text = '_' },
        topdelete = { text = '‾' },
        changedelete = { text = '~' },
      },
    },
    config = function(_, opts)
      require('gitsigns').setup(opts)
      -- Add keymap for floating git blame window
      vim.keymap.set('n', '<leader>gb', function()
        require('plugins.git-utils.blame').show_git_blame_float()
      end, { desc = '[G]it [B]lame floating window' })
    end,
  },
  {
    'kdheepak/lazygit.nvim',
    lazy = true,
    cmd = {
      'LazyGit',
      'LazyGitConfig',
      'LazyGitCurrentFile',
      'LazyGitFilter',
      'LazyGitFilterCurrentFile',
    },
    -- optional for floating window border decoration
    dependencies = {
      'nvim-lua/plenary.nvim',
    },
    -- setting the keybinding for LazyGit with 'keys' is recommended in
    -- order to load the plugin when the command is run for the first time
    keys = {
      { '<leader>lg', '<cmd>LazyGit<cr>', desc = 'LazyGit' },
    },
  },
  {
    'esmuellert/vscode-diff.nvim',
    dependencies = { 'MunifTanjim/nui.nvim' },
    cmd = 'CodeDiff',
  },
}
