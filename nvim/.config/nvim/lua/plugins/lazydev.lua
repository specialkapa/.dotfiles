return { -- Lua types for the Neovim API and for plugins, resolved on demand.
  -- Replaces handing lua_ls the whole runtimepath as `workspace.library` (see
  -- lsp.lua): that made it index every installed plugin's source on each Lua
  -- file, which is where the long "Loading workspace N/2800" progress came from.
  -- lazydev instead injects a module's path only once something references it.
  'folke/lazydev.nvim',
  ft = 'lua',
  opts = {
    library = {
      -- vim.uv is a C module, so lua_ls can't infer it from source the way it
      -- can for the rest of the runtime. Pulled in only if `vim.uv` is typed.
      { path = '${3rd}/luv/library', words = { 'vim%.uv' } },
    },
  },
}
