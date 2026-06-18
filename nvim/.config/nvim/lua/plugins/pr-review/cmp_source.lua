-- nvim-cmp source that completes @mentions of repo collaborators, but only inside the
-- PR comment scratch buffer (tagged b:pr_review_comment). The session feeds the login
-- list via set_logins() when a review opens; until then it simply yields nothing.
local M = {}

M.logins = {}

function M.set_logins(list)
  M.logins = list or {}
end

local source = {}

function source.new()
  return setmetatable({}, { __index = source })
end

function source:is_available()
  return vim.b.pr_review_comment == true
end

function source:get_trigger_characters()
  return { '@' }
end

function source:get_keyword_pattern()
  -- match the @ and any word chars after it, so the inserted text replaces the whole token
  return [[@\w*]]
end

function source:complete(_, callback)
  local items = {}
  for _, login in ipairs(M.logins) do
    items[#items + 1] = {
      label = '@' .. login,
      insertText = '@' .. login,
      filterText = '@' .. login,
      kind = require('cmp').lsp.CompletionItemKind.User,
    }
  end
  callback { items = items, isIncomplete = false }
end

M.source = source

return M
