-- Telescope picker of open PRs for the current repo, with a preview pane showing the
-- PR's summary stats (author, branches, +/-, files, CI rollup, review decision, body).
local M = {}

local gh = require 'plugins.pr-review.gh'

-- Summarize the statusCheckRollup array into ✓/✗/● counts.
local function ci_summary(rollup)
  if not rollup or #rollup == 0 then
    return 'no checks'
  end
  local ok, fail, pending = 0, 0, 0
  for _, c in ipairs(rollup) do
    local concl = c.conclusion or ''
    local st = c.state or ''
    if concl == 'SUCCESS' or st == 'SUCCESS' then
      ok = ok + 1
    elseif concl == 'FAILURE' or concl == 'TIMED_OUT' or concl == 'CANCELLED' or concl == 'ACTION_REQUIRED' or st == 'FAILURE' or st == 'ERROR' then
      fail = fail + 1
    else
      pending = pending + 1
    end
  end
  return string.format('✓ %d  ✗ %d  ● %d', ok, fail, pending)
end

local function decision_text(d)
  return ({
    APPROVED = 'approved',
    CHANGES_REQUESTED = 'changes requested',
    REVIEW_REQUIRED = 'review required',
  })[d or ''] or 'no review yet'
end

local function entry_maker(pr)
  local author = pr.author and pr.author.login or '?'
  local draft = pr.isDraft and ' [draft]' or ''
  local display = string.format('#%-5d %s  @%s  +%d/-%d%s', pr.number, pr.title, author, pr.additions or 0, pr.deletions or 0, draft)
  return {
    value = pr,
    display = display,
    ordinal = string.format('%d %s %s', pr.number, pr.title, author),
  }
end

local function define_preview(self, entry)
  local pr = entry.value
  local author = pr.author and pr.author.login or '?'
  local lines = {
    string.format('#%d  %s', pr.number, pr.title),
    '',
    string.format('author:    @%s%s', author, pr.isDraft and '  (draft)' or ''),
    string.format('branch:    %s ← %s', pr.baseRefName or '?', pr.headRefName or '?'),
    string.format('changes:   +%d / -%d across %d file(s)', pr.additions or 0, pr.deletions or 0, pr.changedFiles or 0),
    string.format('CI:        %s', ci_summary(pr.statusCheckRollup)),
    string.format('review:    %s', decision_text(pr.reviewDecision)),
    string.format('updated:   %s', pr.updatedAt or '?'),
    '',
    '── description ──────────────────────',
    '',
  }
  vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, lines)
  vim.api.nvim_buf_set_option(self.state.bufnr, 'filetype', 'markdown')

  -- fetch the body lazily and append once it arrives
  local bufnr = self.state.bufnr
  gh.run_json({ 'pr', 'view', tostring(pr.number), '--json', 'body' }, function(data)
    vim.schedule(function()
      if not vim.api.nvim_buf_is_valid(bufnr) then
        return
      end
      local body = data and data.body or ''
      if body == '' then
        body = '(no description)'
      end
      vim.api.nvim_buf_set_lines(bufnr, #lines, -1, false, vim.split(body, '\n', { plain = true }))
    end)
  end)
end

-- Open the PR picker.
function M.open()
  gh.resolve_repo(nil, function(repo, rerr)
    if not repo then
      return vim.schedule(function()
        vim.notify('Not a GitHub repo: ' .. (rerr or '?'), vim.log.levels.ERROR, { title = 'PR review' })
      end)
    end
    gh.list_prs(function(prs, err)
      vim.schedule(function()
        if not prs then
          return vim.notify('Failed to list PRs: ' .. (err or '?'), vim.log.levels.ERROR, { title = 'PR review' })
        end
        if #prs == 0 then
          return vim.notify('No open PRs in ' .. repo.nwo, vim.log.levels.INFO, { title = 'PR review' })
        end

        local pickers = require 'telescope.pickers'
        local finders = require 'telescope.finders'
        local conf = require('telescope.config').values
        local previewers = require 'telescope.previewers'
        local actions = require 'telescope.actions'
        local action_state = require 'telescope.actions.state'

        pickers
          .new({}, {
            prompt_title = 'open PRs: ' .. repo.nwo .. '  (<CR> view · <C-o> checkout)',
            finder = finders.new_table { results = prs, entry_maker = entry_maker },
            sorter = conf.generic_sorter {},
            previewer = previewers.new_buffer_previewer {
              title = 'summary',
              define_preview = define_preview,
            },
            attach_mappings = function(prompt_bufnr, map)
              -- <CR>: view-only (read from the API, nothing checked out)
              actions.select_default:replace(function()
                local selection = action_state.get_selected_entry()
                actions.close(prompt_bufnr)
                if selection then
                  require('plugins.pr-review.session').open(selection.value)
                end
              end)
              -- <C-o>: gh pr checkout + review locally (real files, LSP)
              local function checkout()
                local selection = action_state.get_selected_entry()
                actions.close(prompt_bufnr)
                if selection then
                  require('plugins.pr-review.session').checkout(selection.value)
                end
              end
              map('i', '<C-o>', checkout, { desc = 'checkout PR & review locally' })
              map('n', '<C-o>', checkout, { desc = 'checkout PR & review locally' })
              return true
            end,
          })
          :find()
      end)
    end)
  end)
end

return M
