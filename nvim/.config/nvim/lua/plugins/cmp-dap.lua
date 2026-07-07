-- cmp-dap: completion source for the nvim-dap REPL / watch / hover prompts.
--
-- This used to be a plain dependency of nvim-cmp. That made lazy load it together
-- with cmp on InsertEnter, and cmp-dap's after/plugin (`require('cmp_dap')`) requires
-- 'dap' at the top of its module -- so the ENTIRE nvim-dap stack (~220ms of adapter
-- setup) was pulled synchronously into the first InsertEnter of every session,
-- defeating the careful ft/keys lazy-loading in plugins/debug.lua.
--
-- Instead, load it only when a `dap-repl` buffer actually appears. By then you're in
-- a live debug session, so nvim-dap is loaded (it opened the REPL) and nvim-cmp is
-- loaded (you've been editing) -- pulling both in here costs nothing extra. On normal
-- editing, and even on opening a python/go file, cmp-dap is never touched.
return {
  'rcarriga/cmp-dap',
  ft = 'dap-repl',
  dependencies = {
    'mfussenegger/nvim-dap',
    'hrsh7th/nvim-cmp',
  },
}
