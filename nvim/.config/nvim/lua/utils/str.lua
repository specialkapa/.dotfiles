-- Small string helpers shared across plugins.
local M = {}

-- Strip carriage returns and surrounding whitespace. nil-safe (returns '').
function M.trim(value)
  if not value then
    return ''
  end
  return (value:gsub('\r', '')):gsub('^%s+', ''):gsub('%s+$', '')
end

return M
