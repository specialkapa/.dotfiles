local M = {}

local function trim(value)
  if not value then
    return ''
  end
  return (value:gsub('\r', '')):gsub('^%s+', ''):gsub('%s+$', '')
end

local function is_wsl()
  local uname = trim(vim.fn.system { 'uname', '-a' })
  return uname:match 'WSL2' ~= nil
end

function M.open_url_in_browser(url)
  if not url or url == '' then
    return false
  end

  local open_cmd
  if is_wsl() then
    open_cmd = { 'cmd.exe', '/C', 'start', '', url }
  elseif vim.fn.has 'mac' == 1 or vim.fn.has 'macunix' == 1 then
    open_cmd = { 'open', url }
  elseif vim.fn.has 'win32' == 1 or vim.fn.has 'win64' == 1 then
    open_cmd = { 'cmd.exe', '/C', 'start', '', url }
  else
    open_cmd = { 'xdg-open', url }
  end

  local job = vim.fn.jobstart(open_cmd, { detach = true })
  if job <= 0 then
    vim.notify('Failed to launch browser', vim.log.levels.ERROR)
    return false
  end

  return true
end

local function extract_url(text)
  if not text or text == '' then
    return nil
  end

  -- Remove surrounding punctuation that might be captured (quotes, parens, brackets, etc.)
  text = text:gsub('^[%(%[%{%<"\'`]+', ''):gsub('[%(%[%{%<"\'%)`%]%}>%.,;:!%?]+$', '')

  -- Check for full URL (http:// or https://)
  if text:match '^https?://' then
    return text
  end

  -- Check for common domain patterns (bare domains)
  -- Matches: domain.tld, subdomain.domain.tld, domain.tld/path, etc.
  local domain_pattern = '^[%w%-]+%.[%w%-%.]+[%w%-]'
  if text:match(domain_pattern) then
    -- Verify it looks like a real domain (has valid TLD-like ending or path)
    if text:match '%.[%a][%a]+' or text:match '%.[%a][%a]+/' then
      return 'https://' .. text
    end
  end

  return nil
end

function M.open_url_under_cursor()
  local cword = vim.fn.expand '<cWORD>'
  local url = extract_url(cword)

  if not url then
    vim.notify('No valid URL found under cursor', vim.log.levels.WARN)
    return
  end

  local success = M.open_url_in_browser(url)
  if success then
    vim.notify('Opening: ' .. url, vim.log.levels.INFO)
  end
end

return M
