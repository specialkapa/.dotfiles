-- Route a single "resume" key to whichever fuzzy picker was used most recently.
--
-- The file/grep surface lives in fff.nvim while Telescope still owns everything
-- else (LSP refs, diagnostics, symbols…), and each plugin keeps its own private
-- resume state. Rather than overload `<leader>sr` and let load order decide the
-- winner, we bump a monotonic counter every time either picker opens and, on
-- resume, dispatch to the more recent one.
--
-- A plain counter (not a clock) is deliberate: vim.uv.now() returns the event
-- loop's cached time, which can be identical for two opens in the same tick, and
-- the tie would silently bias one picker. An incrementing seq is always strict.
--
-- Wiring (kept out of this module so it can't create load-order cycles):
--   * Telescope: an autocmd on `User TelescopeFindPre` calls mark('telescope').
--     That event fires on every Telescope open, so opens not bound to a keymap
--     are covered too.
--   * fff: no open event exists, but fff is only ever launched through the
--     keymaps in `plugins/fff.lua`, so those callbacks call mark('fff').
--
-- Note: recency here means *most recently opened*, not *most recently holding
-- resumable content*. Both `resume()` calls degrade gracefully when their side
-- has nothing saved (fff opens a fresh picker; Telescope notifies).
local M = { t = { fff = 0, telescope = 0 }, seq = 0 }

--- Record that a picker of the given source was just opened.
---@param src 'fff'|'telescope'
function M.mark(src)
  M.seq = M.seq + 1
  M.t[src] = M.seq
end

--- Resume whichever picker (fff or Telescope) was opened most recently.
function M.resume()
  if M.t.telescope > M.t.fff then
    require('telescope.builtin').resume()
  else
    require('fff').resume()
  end
end

return M
