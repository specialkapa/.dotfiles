-- PR review plugin: review GitHub PRs without leaving Neovim.
--
-- List open PRs (Telescope), read summary stats, open files in a side-by-side diff,
-- leave line comments (immediately, or queued privately under a started review),
-- @mention collaborators, and approve / request changes with a summary.
--
-- All GitHub I/O goes through the authenticated `gh` CLI (see gh.lua). The code lives
-- on the runtimepath already, so this spec only attaches the entry keymap to the
-- existing Telescope plugin (loading it on demand). The @mention cmp source is
-- registered lazily the first time a comment float opens (see comment.lua).
return {
  'nvim-telescope/telescope.nvim',
  optional = true,
  keys = {
    {
      '<leader>gP',
      function()
        require('plugins.pr-review.list').open()
      end,
      desc = '[G]it [P]R review (list open PRs)',
    },
  },
}
