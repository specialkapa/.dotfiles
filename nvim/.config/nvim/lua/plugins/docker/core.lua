-- Docker Compose helper: `compose up` the file in the active buffer, with an
-- optional Telescope multi-select to bring up only some services. Runs attached
-- in a floating toggleterm (see compose.lua).
--
-- The implementation only leans on Telescope (picker) + toggleterm (terminal),
-- both already loaded, so this spec just hangs the entry keymaps off Telescope
-- and loads the logic on demand.
return {
  'nvim-telescope/telescope.nvim',
  optional = true,
  keys = {
    {
      '<leader>lu',
      function()
        require('plugins.docker.compose').up()
      end,
      desc = 'Docker Compose: [u]p (all services)',
    },
    {
      '<leader>lU',
      function()
        require('plugins.docker.compose').up { select = true }
      end,
      desc = 'Docker Compose: [U]p (choose services)',
    },
  },
}
