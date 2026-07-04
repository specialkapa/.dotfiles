-- Run `docker compose up` for the compose file in the active buffer, optionally
-- choosing a subset of services via a Telescope multi-select picker.
--
-- Service discovery is delegated to `docker compose config --services` (the
-- authoritative list) rather than parsing YAML ourselves. The `up` runs detached
-- (`-d`) in a floating toggleterm; on a clean start the terminal closes and
-- lazydocker opens to monitor the stack, while a failed start keeps the terminal
-- (and its error) on screen.
local M = {}

-- The base compose invocation. Swap to { 'docker-compose' } for the legacy binary.
local compose_cmd = { 'docker', 'compose' }

-- Behaviour knobs.
--   detach          run `up -d` (returns once containers are started)
--   open_lazydocker pop lazydocker after a clean start (only meaningful with detach)
local config = {
  detach = true,
  open_lazydocker = true,
}

local function notify(msg, level)
  vim.notify(msg, level or vim.log.levels.INFO, { title = 'Docker Compose' })
end

-- True for docker-compose.y(a)ml / compose.y(a)ml (optionally with a suffix like
-- docker-compose.prod.yml), case-insensitively.
local function is_compose_file(path)
  local name = vim.fs.basename(path or ''):lower()
  return name:match '^docker%-compose.*%.ya?ml$' ~= nil or name:match '^compose.*%.ya?ml$' ~= nil
end

-- Resolve (and validate) the compose file backing the current buffer.
-- Writes the buffer first if it has unsaved changes so docker sees current content.
local function current_compose_file()
  local path = vim.api.nvim_buf_get_name(0)
  if path == '' then
    return nil, 'current buffer is not backed by a file'
  end
  if not is_compose_file(path) then
    return nil, 'not a compose file: ' .. vim.fs.basename(path)
  end
  if vim.bo.modified then
    vim.cmd 'silent write'
  end
  return path
end

-- Run `docker compose -f <file> up [-d] [services...]` in a floating terminal.
-- When detached, a clean exit (code 0) closes the terminal and opens lazydocker;
-- a non-zero exit leaves the terminal up so the error stays visible.
local function run_up(file, services)
  local parts = vim.deepcopy(compose_cmd)
  table.insert(parts, '-f')
  table.insert(parts, vim.fn.shellescape(file))
  table.insert(parts, 'up')
  if config.detach then
    table.insert(parts, '-d')
  end
  for _, svc in ipairs(services or {}) do
    table.insert(parts, vim.fn.shellescape(svc))
  end
  local cmdline = table.concat(parts, ' ')

  local Terminal = require('toggleterm.terminal').Terminal
  local term
  term = Terminal:new {
    cmd = cmdline,
    dir = vim.fs.dirname(file),
    direction = 'float',
    float_opts = { border = require('utils.ui').BORDER, title_pos = 'center' },
    display_name = 'docker compose up',
    close_on_exit = false, -- we decide what to do based on the exit code
    on_exit = function(_, _, exit_code)
      if not config.detach then
        return
      end
      if exit_code == 0 then
        -- Stack started cleanly: drop the log pane and hand off to lazydocker.
        pcall(function()
          term:close()
        end)
        if config.open_lazydocker then
          vim.schedule(function()
            local ok, lazydocker = pcall(require, 'lazydocker')
            if ok then
              lazydocker.open()
            end
          end)
        end
      else
        -- Surface the failure: keep the terminal open and flag it.
        vim.schedule(function()
          notify('compose up failed (exit ' .. exit_code .. ') — see terminal', vim.log.levels.ERROR)
        end)
      end
    end,
  }
  term:toggle()

  local what = (services and #services > 0) and table.concat(services, ', ') or 'all services'
  notify('compose up: ' .. what)
end

-- Fetch the service names defined in `file` (async).
local function list_services(file, cb)
  local cmd = vim.deepcopy(compose_cmd)
  vim.list_extend(cmd, { '-f', file, 'config', '--services' })
  vim.system(cmd, { text = true }, function(res)
    vim.schedule(function()
      if res.code ~= 0 then
        local err = vim.trim(res.stderr or '')
        return cb(nil, err ~= '' and err or 'docker compose config failed')
      end
      cb(vim.split(vim.trim(res.stdout or ''), '\n', { plain = true, trimempty = true }))
    end)
  end)
end

-- Preview the resolved definition of a single service. `docker compose config
-- <service>` filters the rendered document down to just that service, which is
-- exactly what we want to show in the right-hand pane. Results are memoised per
-- service so scrolling the list doesn't re-shell on every move.
local function service_previewer(file)
  local previewers = require 'telescope.previewers'
  local cache = {}

  return previewers.new_buffer_previewer {
    title = 'service definition',
    define_preview = function(self, entry)
      local bufnr = self.state.bufnr
      local svc = entry.value

      local function render(lines)
        if not vim.api.nvim_buf_is_valid(bufnr) then
          return
        end
        vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
        vim.api.nvim_set_option_value('filetype', 'yaml', { buf = bufnr })
      end

      if cache[svc] then
        return render(cache[svc])
      end

      local cmd = vim.deepcopy(compose_cmd)
      vim.list_extend(cmd, { '-f', file, 'config', svc })
      vim.system(cmd, { text = true }, function(res)
        vim.schedule(function()
          local out = (res.code == 0) and vim.trim(res.stdout or '') or vim.trim(res.stderr or '')
          local lines = vim.split(out ~= '' and out or '(no output)', '\n', { plain = true })
          cache[svc] = lines
          render(lines)
        end)
      end)
    end,
  }
end

-- Telescope multi-select over the service list. <Tab> to (de)select, <CR> to run
-- the selection; with nothing multi-selected, runs the single entry under the cursor.
-- The right pane previews the resolved definition of the service under the cursor.
local function pick_services(file, services)
  local pickers = require 'telescope.pickers'
  local finders = require 'telescope.finders'
  local conf = require('telescope.config').values
  local actions = require 'telescope.actions'
  local action_state = require 'telescope.actions.state'

  pickers
    .new({
      layout_strategy = 'horizontal',
      layout_config = {
        width = 0.7,
        height = 0.6,
        preview_width = 0.55,
        prompt_position = 'top',
      },
    }, {
      prompt_title = '  compose up',
      results_title = '<Tab> select · <CR> run',
      finder = finders.new_table { results = services },
      sorter = conf.generic_sorter {},
      previewer = service_previewer(file),
      attach_mappings = function(prompt_bufnr)
        actions.select_default:replace(function()
          local picker = action_state.get_current_picker(prompt_bufnr)
          local chosen = {}
          for _, entry in ipairs(picker:get_multi_selection()) do
            table.insert(chosen, entry.value)
          end
          if #chosen == 0 then
            local entry = action_state.get_selected_entry()
            if entry then
              table.insert(chosen, entry.value)
            end
          end
          actions.close(prompt_bufnr)
          if #chosen > 0 then
            run_up(file, chosen)
          end
        end)
        return true
      end,
    })
    :find()
end

-- Entry point. `opts.select == true` opens the service picker first; otherwise
-- brings up every service in the file.
function M.up(opts)
  opts = opts or {}
  local file, err = current_compose_file()
  if not file then
    return notify(err, vim.log.levels.WARN)
  end

  if not opts.select then
    return run_up(file, nil)
  end

  list_services(file, function(services, lerr)
    if not services then
      return notify('could not list services: ' .. (lerr or '?'), vim.log.levels.ERROR)
    end
    if #services == 0 then
      return notify('no services found in ' .. vim.fs.basename(file), vim.log.levels.WARN)
    end
    pick_services(file, services)
  end)
end

return M
