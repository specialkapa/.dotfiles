-- Async wrappers around the `gh` CLI for the PR-review plugin.
--
-- Everything here runs off the UI thread via vim.system; callbacks fire in a fast
-- event context, so any callback that touches the editor API must wrap that work in
-- vim.schedule (the higher-level modules do this). The helpers themselves stay pure.
local M = {}

local trim = require('utils.str').trim

-- repo (owner/name) resolved from the cwd's git remote, cached per cwd.
local repo_cache = {}
-- collaborator logins for @mentions, cached per "owner/name".
local collaborator_cache = {}

-- Run gh with the given argument list. cb(ok, stdout, stderr) runs in a fast event
-- context. `opts.stdin` (string) is piped to gh's stdin when present.
local function run(args, cb, opts)
  opts = opts or {}
  local cmd = vim.list_extend({ 'gh' }, args)
  local sysopts = { text = true }
  if opts.stdin then
    sysopts.stdin = opts.stdin
  end
  vim.system(cmd, sysopts, function(res)
    cb(res.code == 0, res.stdout or '', res.stderr or '')
  end)
end
M.run = run

-- Run gh and decode JSON stdout. cb(data_or_nil, errmsg).
local function run_json(args, cb)
  run(args, function(ok, stdout, stderr)
    if not ok then
      return cb(nil, trim(stderr) ~= '' and trim(stderr) or 'gh command failed')
    end
    local decoded
    local pok = pcall(function()
      decoded = vim.json.decode(stdout)
    end)
    if not pok then
      return cb(nil, 'failed to parse gh JSON output')
    end
    cb(decoded, nil)
  end)
end
M.run_json = run_json

-- Resolve the GitHub repo for a directory (defaults to cwd). cb(repo_or_nil, err)
-- where repo = { owner = .., name = .., nwo = 'owner/name' }.
function M.resolve_repo(dir, cb)
  dir = dir or vim.fn.getcwd()
  local cached = repo_cache[dir]
  if cached then
    return cb(cached, nil)
  end
  run({ 'repo', 'view', '--json', 'nameWithOwner', '-q', '.nameWithOwner' }, function(ok, stdout, stderr)
    if not ok then
      return cb(nil, trim(stderr) ~= '' and trim(stderr) or 'not a GitHub repository')
    end
    local nwo = trim(stdout)
    local owner, name = nwo:match '^([^/]+)/(.+)$'
    if not owner then
      return cb(nil, 'could not parse repo from: ' .. nwo)
    end
    local repo = { owner = owner, name = name, nwo = nwo }
    repo_cache[dir] = repo
    cb(repo, nil)
  end)
end

local PR_LIST_FIELDS = table.concat({
  'number',
  'title',
  'author',
  'additions',
  'deletions',
  'changedFiles',
  'reviewDecision',
  'isDraft',
  'headRefName',
  'baseRefName',
  'statusCheckRollup',
  'updatedAt',
}, ',')

-- List open PRs for the current repo. cb(list_or_nil, err).
function M.list_prs(cb)
  run_json({ 'pr', 'list', '--state', 'open', '--limit', '100', '--json', PR_LIST_FIELDS }, cb)
end

-- Resolve the head/base commit SHAs for a PR. cb({ head = .., base = .. } | nil, err).
function M.pr_shas(number, cb)
  run_json({ 'pr', 'view', tostring(number), '--json', 'headRefOid,baseRefOid' }, function(data, err)
    if not data then
      return cb(nil, err)
    end
    cb({ head = data.headRefOid, base = data.baseRefOid }, nil)
  end)
end

-- Changed files for a PR (paginated). cb(files_or_nil, err); each file has
-- { filename, status, additions, deletions, patch, previous_filename }.
function M.pr_files(repo, number, cb)
  local endpoint = string.format('repos/%s/%s/pulls/%d/files', repo.owner, repo.name, number)
  run_json({ 'api', '--paginate', endpoint }, cb)
end

-- Existing review comments for a PR (paginated). cb(comments_or_nil, err).
function M.pr_comments(repo, number, cb)
  local endpoint = string.format('repos/%s/%s/pulls/%d/comments', repo.owner, repo.name, number)
  run_json({ 'api', '--paginate', endpoint }, cb)
end

-- Fetch raw file content at a given ref. cb(ok, content_string). On a 404 (added or
-- deleted file at that ref) ok is false and content is ''.
function M.file_content(repo, path, ref, cb)
  local endpoint = string.format('repos/%s/%s/contents/%s?ref=%s', repo.owner, repo.name, path, ref)
  run({ 'api', '-H', 'Accept: application/vnd.github.raw', endpoint }, function(ok, stdout)
    cb(ok, ok and stdout or '')
  end)
end

-- Post a single review comment immediately (no pending review). cb(ok, err).
function M.post_comment(repo, number, payload, cb)
  -- payload = { body, commit_id, path, line, side }
  local endpoint = string.format('repos/%s/%s/pulls/%d/comments', repo.owner, repo.name, number)
  run({ 'api', '--method', 'POST', endpoint, '--input', '-' }, function(ok, _, stderr)
    cb(ok, ok and nil or (trim(stderr) ~= '' and trim(stderr) or 'failed to post comment'))
  end, { stdin = vim.json.encode(payload) })
end

-- Submit a review with a verdict and (optionally) a batch of line comments. cb(ok, err).
-- payload = { commit_id, body, event = APPROVE|REQUEST_CHANGES|COMMENT, comments = {..} }.
function M.submit_review(repo, number, payload, cb)
  local endpoint = string.format('repos/%s/%s/pulls/%d/reviews', repo.owner, repo.name, number)
  run({ 'api', '--method', 'POST', endpoint, '--input', '-' }, function(ok, _, stderr)
    cb(ok, ok and nil or (trim(stderr) ~= '' and trim(stderr) or 'failed to submit review'))
  end, { stdin = vim.json.encode(payload) })
end

-- Edit an existing review comment. cb(ok, err).
function M.update_comment(repo, comment_id, body, cb)
  local endpoint = string.format('repos/%s/%s/pulls/comments/%d', repo.owner, repo.name, comment_id)
  run({ 'api', '--method', 'PATCH', endpoint, '--input', '-' }, function(ok, _, stderr)
    cb(ok, ok and nil or (trim(stderr) ~= '' and trim(stderr) or 'failed to edit comment'))
  end, { stdin = vim.json.encode { body = body } })
end

-- Delete a review comment. cb(ok, err).
function M.delete_comment(repo, comment_id, cb)
  local endpoint = string.format('repos/%s/%s/pulls/comments/%d', repo.owner, repo.name, comment_id)
  run({ 'api', '--method', 'DELETE', endpoint }, function(ok, _, stderr)
    cb(ok, ok and nil or (trim(stderr) ~= '' and trim(stderr) or 'failed to delete comment'))
  end)
end

-- Reply to a review comment (creates a threaded reply). cb(ok, err).
function M.reply_comment(repo, number, comment_id, body, cb)
  local endpoint = string.format('repos/%s/%s/pulls/%d/comments/%d/replies', repo.owner, repo.name, number, comment_id)
  run({ 'api', '--method', 'POST', endpoint, '--input', '-' }, function(ok, _, stderr)
    cb(ok, ok and nil or (trim(stderr) ~= '' and trim(stderr) or 'failed to reply'))
  end, { stdin = vim.json.encode { body = body } })
end

-- Review threads via GraphQL: gives the thread id (needed to resolve), resolution state,
-- and per-comment/per-thread viewer permissions, keyed by comment databaseId. cb(nodes_or_nil, err).
function M.review_threads(repo, number, cb)
  local query = table.concat({
    'query($owner:String!,$name:String!,$number:Int!){',
    '  repository(owner:$owner,name:$name){',
    '    pullRequest(number:$number){',
    '      reviewThreads(first:100){ nodes{',
    '        id isResolved isOutdated viewerCanResolve viewerCanUnresolve',
    '        comments(first:100){ nodes{ databaseId viewerCanUpdate viewerCanDelete } }',
    '      } }',
    '    }',
    '  }',
    '}',
  }, '\n')
  run_json({
    'api',
    'graphql',
    '-f',
    'query=' .. query,
    '-f',
    'owner=' .. repo.owner,
    '-f',
    'name=' .. repo.name,
    '-F',
    'number=' .. number,
  }, function(data, err)
    if not data then
      return cb(nil, err)
    end
    local ok, nodes = pcall(function()
      return data.data.repository.pullRequest.reviewThreads.nodes
    end)
    cb(ok and nodes or {}, nil)
  end)
end

-- Resolve or unresolve a review thread (GraphQL mutation). cb(ok, err).
function M.set_thread_resolved(thread_id, resolved, cb)
  local mutation = resolved and 'resolveReviewThread' or 'unresolveReviewThread'
  local query = string.format('mutation($id:ID!){ %s(input:{threadId:$id}){ thread{ id isResolved } } }', mutation)
  run({ 'api', 'graphql', '-f', 'query=' .. query, '-f', 'id=' .. thread_id }, function(ok, _, stderr)
    cb(ok, ok and nil or (trim(stderr) ~= '' and trim(stderr) or 'failed to update thread'))
  end)
end

-- ---- local git (for checkout mode) ---------------------------------------------

-- Run git asynchronously. cb(ok, stdout, stderr) in a fast event context.
function M.git(args, cb)
  vim.system(vim.list_extend({ 'git' }, args), { text = true }, function(res)
    cb(res.code == 0, res.stdout or '', res.stderr or '')
  end)
end

-- Absolute path of the repo root (cb(root_or_nil)).
function M.repo_root(cb)
  M.git({ 'rev-parse', '--show-toplevel' }, function(ok, out)
    cb(ok and trim(out) ~= '' and trim(out) or nil)
  end)
end

-- Current branch name (cb(branch_or_nil); nil when detached).
function M.current_branch(cb)
  M.git({ 'rev-parse', '--abbrev-ref', 'HEAD' }, function(ok, out)
    local b = trim(out)
    cb(ok and b ~= '' and b ~= 'HEAD' and b or nil)
  end)
end

-- Is the working tree dirty (uncommitted changes)? cb(bool).
function M.is_dirty(cb)
  M.git({ 'status', '--porcelain' }, function(ok, out)
    cb(ok and trim(out) ~= '')
  end)
end

-- Check out a PR branch locally via gh. cb(ok, err).
function M.pr_checkout(number, cb)
  run({ 'pr', 'checkout', tostring(number) }, function(ok, _, stderr)
    cb(ok, ok and nil or (trim(stderr) ~= '' and trim(stderr) or 'gh pr checkout failed'))
  end)
end

-- Switch back to a branch/ref. cb(ok, err).
function M.git_checkout(ref, cb)
  M.git({ 'checkout', ref }, function(ok, _, stderr)
    cb(ok, ok and nil or (trim(stderr) ~= '' and trim(stderr) or 'git checkout failed'))
  end)
end

-- Collaborator logins for @mention completion, cached per repo. cb(list) — never errors;
-- yields {} if the lookup fails (e.g. insufficient scope), and falls back to assignees.
function M.collaborators(repo, cb)
  local cached = collaborator_cache[repo.nwo]
  if cached then
    return cb(cached)
  end
  local function finish(list)
    collaborator_cache[repo.nwo] = list
    cb(list)
  end
  local endpoint = string.format('repos/%s/%s/collaborators', repo.owner, repo.name)
  run({ 'api', '--paginate', endpoint, '-q', '.[].login' }, function(ok, stdout)
    if ok and trim(stdout) ~= '' then
      return finish(vim.split(trim(stdout), '\n', { trimempty = true }))
    end
    -- fall back to assignees when collaborator listing is forbidden
    local assignees = string.format('repos/%s/%s/assignees', repo.owner, repo.name)
    run({ 'api', '--paginate', assignees, '-q', '.[].login' }, function(ok2, out2)
      if ok2 and trim(out2) ~= '' then
        return finish(vim.split(trim(out2), '\n', { trimempty = true }))
      end
      finish {}
    end)
  end)
end

return M
