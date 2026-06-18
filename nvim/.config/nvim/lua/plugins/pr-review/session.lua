-- Review session state machine. Owns the single active review: which PR, its files,
-- comment threads (root + replies, with resolve state), the locally-queued (pending)
-- comments, and whether a batched review is active. Drives diff.lua (the view) and
-- comment.lua (the input floats).
local M = {}

local gh = require 'plugins.pr-review.gh'
local diff = require 'plugins.pr-review.diff'
local comment = require 'plugins.pr-review.comment'
local cmp_source = require 'plugins.pr-review.cmp_source'
local ui = require 'utils.ui'

local state = nil
local next_local_id = 0

local refresh_panel -- forward decl; assigned in the changed-files section below

local nav_ns = vim.api.nvim_create_namespace 'PrReviewNav'

local function notify(msg, level)
  vim.notify(msg, level or vim.log.levels.INFO, { title = 'PR review' })
end

-- ---- thread building ------------------------------------------------------------

-- Combine REST comments (body/line/side/author) with GraphQL thread metadata
-- (thread id, resolve state, viewer permissions) into a list of thread objects.
local function build_posted_threads(comments, gql)
  local meta = {} -- comment databaseId -> { thread fields + per-comment perms }
  for _, t in ipairs(gql or {}) do
    for _, cn in ipairs(t.comments and t.comments.nodes or {}) do
      meta[cn.databaseId] = {
        thread_id = t.id,
        resolved = t.isResolved,
        outdated = t.isOutdated,
        can_resolve = t.viewerCanResolve,
        can_unresolve = t.viewerCanUnresolve,
        can_update = cn.viewerCanUpdate,
        can_delete = cn.viewerCanDelete,
      }
    end
  end

  local by_thread, order = {}, {}
  for _, c in ipairs(comments or {}) do
    local m = meta[c.id] or {}
    local tid = m.thread_id or ('rest:' .. c.id)
    local th = by_thread[tid]
    if not th then
      th = {
        id = m.thread_id,
        resolved = m.resolved or false,
        outdated = m.outdated or false,
        can_resolve = m.can_resolve,
        can_unresolve = m.can_unresolve,
        path = c.path,
        line = c.line or c.original_line,
        side = c.side or 'RIGHT',
        comments = {},
        pending = false,
      }
      by_thread[tid] = th
      order[#order + 1] = tid
    end
    th.comments[#th.comments + 1] = {
      db_id = c.id,
      user = c.user and c.user.login or '?',
      body = c.body,
      can_update = m.can_update,
      can_delete = m.can_delete,
    }
    if not c.in_reply_to_id then
      -- root comment defines the thread anchor
      th.path, th.line, th.side = c.path, c.line or c.original_line, c.side or 'RIGHT'
      th.root_id = c.id
    end
  end

  local threads = {}
  for _, tid in ipairs(order) do
    local th = by_thread[tid]
    th.root_id = th.root_id or (th.comments[1] and th.comments[1].db_id)
    threads[#threads + 1] = th
  end
  return threads
end

-- Locally-queued comments rendered as single-comment pending threads.
local function pending_threads()
  local out = {}
  for _, q in ipairs(state.queued) do
    out[#out + 1] = {
      pending = true,
      resolved = false,
      path = q.path,
      line = q.line,
      side = q.side,
      local_id = q.local_id,
      comments = { { user = 'you', body = q.body, local_id = q.local_id } },
    }
  end
  return out
end

-- Posted + pending threads anchored in one file.
local function threads_for_file(path)
  local out = {}
  for _, th in ipairs(state.posted_threads or {}) do
    if th.path == path then
      out[#out + 1] = th
    end
  end
  for _, th in ipairs(pending_threads()) do
    if th.path == path then
      out[#out + 1] = th
    end
  end
  return out
end

-- ---- file rendering -------------------------------------------------------------

local function show_current()
  local file = state.files[state.file_idx]
  local local_mode = state.mode == 'local'
  -- in checkout mode the head side is the real on-disk file (nil for deleted files)
  local head_path = (local_mode and file.status ~= 'removed') and (state.root .. '/' .. file.filename) or nil
  local cached = state.contents[file.filename]

  local function render(base_content, head_content)
    local badge = local_mode and '%#PrReviewModeCheckout# CHECKOUT %*' or '%#PrReviewModeView# VIEW %*'
    diff.show_file {
      file = file,
      base_content = base_content,
      head_content = head_content, -- only used when the head is NOT the local file
      head_local = local_mode,
      head_path = head_path,
      threads = threads_for_file(file.filename),
      handlers = M.handlers,
      -- %< marks where truncation starts: keep the badge/PR/position, shorten the path
      winbar_head = badge .. string.format('  PR #%d  [%d/%d]  %%<%s', state.pr, state.file_idx, #state.files, file.filename),
      winbar_base = '%#PrReviewWinbarDim#  base · read-only%*',
    }
    local label = string.format('[%d/%d] %s', state.file_idx, #state.files, file.filename)
    notify(label .. (state.review_active and string.format('  ● REVIEW (%d queued)', #state.queued) or ''))
    refresh_panel()
  end

  if cached then
    return render(cached.base, cached.head)
  end

  -- binary / too-large files have no patch from the files API
  if not file.patch then
    local placeholder = '(no diff available — binary or too large to display)'
    state.contents[file.filename] = { base = nil, head = nil }
    local head_ph = (not local_mode and file.status ~= 'removed') and placeholder or nil
    return render(file.status ~= 'added' and placeholder or nil, head_ph)
  end

  -- base side is always fetched from the API (base SHA); head from the API only in view
  -- mode (in checkout mode the head is read straight off disk)
  local fetch_base = file.status ~= 'added'
  local fetch_head = (not local_mode) and file.status ~= 'removed'
  local base, head
  local pending = (fetch_base and 1 or 0) + (fetch_head and 1 or 0)

  local function done()
    pending = pending - 1
    if pending > 0 then
      return
    end
    state.contents[file.filename] = { base = base, head = head }
    vim.schedule(function()
      render(base, head)
    end)
  end

  if pending == 0 then
    state.contents[file.filename] = { base = nil, head = nil }
    return vim.schedule(function()
      render(nil, nil)
    end)
  end

  if fetch_base then
    gh.file_content(state.repo, file.previous_filename or file.filename, state.base_sha, function(ok, content)
      if ok then
        base = content
      end
      done()
    end)
  end
  if fetch_head then
    gh.file_content(state.repo, file.filename, state.head_sha, function(ok, content)
      if ok then
        head = content
      end
      done()
    end)
  end
end

local function rerender_current()
  if state then
    diff.set_threads(threads_for_file(state.files[state.file_idx].filename))
  end
end

local function goto_file(idx)
  if idx < 1 or idx > #state.files then
    return
  end
  state.file_idx = idx
  show_current()
  refresh_panel() -- keep the side panel's ▶ marker in sync (no-op if closed)
end

-- Re-fetch comment threads from GitHub and re-render. cb optional.
local function load_threads(cb)
  local comments, gql
  local pending = 2
  local function done()
    pending = pending - 1
    if pending > 0 then
      return
    end
    state.posted_threads = build_posted_threads(comments, gql)
    if cb then
      cb()
    end
  end
  gh.pr_comments(state.repo, state.pr, function(c)
    comments = c
    done()
  end)
  gh.review_threads(state.repo, state.pr, function(t)
    gql = t
    done()
  end)
end

local function refresh_threads()
  load_threads(function()
    vim.schedule(rerender_current)
  end)
end

-- ---- changed-files list (float + side panel) ------------------------------------

local function status_glyph(status)
  return ({ added = '+', removed = '-', modified = '~', renamed = '→' })[status] or '·'
end

-- Build the colored changed-files list: buffer lines + highlight specs. Shared by the
-- floating navigator (<leader>rf) and the toggleable side panel (<leader>rt), so both
-- render identically (status glyph tinted, +adds green, -dels red).
local function file_list_lines()
  -- git-status colors from the active theme (not hardcoded hex)
  ui.link_first('PrReviewNavAdd', { 'Added', 'diffAdded', 'GitSignsAdd', 'DiagnosticOk' })
  ui.link_first('PrReviewNavDel', { 'Removed', 'diffRemoved', 'GitSignsDelete', 'DiagnosticError' })
  ui.link_first('PrReviewNavMod', { 'Changed', 'diffChanged', 'GitSignsChange', 'DiagnosticWarn' })
  ui.link_first('PrReviewNavRen', { 'Special', 'Changed', 'DiagnosticInfo' })
  local glyph_hl = { added = 'PrReviewNavAdd', removed = 'PrReviewNavDel', modified = 'PrReviewNavMod', renamed = 'PrReviewNavRen' }

  local lines, hls, width = {}, {}, 20
  for i, f in ipairs(state.files) do
    local marker = i == state.file_idx and '▶ ' or '  '
    local glyph = status_glyph(f.status)
    local pre = marker .. glyph
    local mid = ' ' .. f.filename .. '  '
    local add_str = '+' .. (f.additions or 0)
    local del_str = '-' .. (f.deletions or 0)
    local line = pre .. mid .. add_str .. '/' .. del_str
    lines[#lines + 1] = line
    width = math.max(width, vim.fn.strdisplaywidth(line) + 2)
    local add_start = #pre + #mid
    hls[#hls + 1] = {
      row = i - 1,
      { #marker, #pre, glyph_hl[f.status] or 'PrReviewNavMod' },
      { add_start, add_start + #add_str, 'PrReviewNavAdd' },
      { add_start + #add_str + 1, add_start + #add_str + 1 + #del_str, 'PrReviewNavDel' },
    }
  end
  return lines, hls, width
end

local function apply_list_hls(buf, hls)
  vim.api.nvim_buf_clear_namespace(buf, nav_ns, 0, -1)
  for _, h in ipairs(hls) do
    for _, seg in ipairs(h) do
      pcall(vim.api.nvim_buf_set_extmark, buf, nav_ns, h.row, seg[1], { end_col = seg[2], hl_group = seg[3] })
    end
  end
end

-- floating navigator (one-shot picker) -------------------------------------------
local function open_navigator()
  if not state then
    return
  end
  local lines, hls, width = file_list_lines()

  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  apply_list_hls(buf, hls)
  vim.api.nvim_buf_set_option(buf, 'modifiable', false)

  local ui_w, ui_h = vim.o.columns, vim.o.lines
  local win_w = math.min(width, ui_w - 6)
  local win_h = math.min(#lines, ui_h - 6)
  local win = vim.api.nvim_open_win(buf, true, {
    relative = 'editor',
    width = win_w,
    height = win_h,
    row = math.floor((ui_h - win_h) / 2 - 1),
    col = math.floor((ui_w - win_w) / 2),
    style = 'minimal',
    border = ui.BORDER,
    title = { { ' changed files ', 'Title' } },
    title_pos = 'left',
  })
  vim.api.nvim_win_set_cursor(win, { state.file_idx, 0 })
  vim.api.nvim_win_set_option(win, 'cursorline', true)

  local function close()
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
  end
  vim.api.nvim_buf_set_keymap(buf, 'n', '<CR>', '', {
    noremap = true,
    silent = true,
    callback = function()
      local idx = vim.api.nvim_win_get_cursor(win)[1]
      close()
      goto_file(idx)
    end,
  })
  for _, lhs in ipairs { 'q', '<Esc>' } do
    vim.api.nvim_buf_set_keymap(buf, 'n', lhs, '', { noremap = true, silent = true, callback = close })
  end
end

-- toggleable side panel (persistent left split) ----------------------------------
local PANEL_W = 36
local panel = { win = nil, buf = nil }

local function panel_is_open()
  return panel.win ~= nil and vim.api.nvim_win_is_valid(panel.win)
end

-- (re)render the panel buffer, keeping the ▶ marker on the current file. Assigned to
-- the forward-declared upvalue so goto_file (defined earlier) can call it.
function refresh_panel()
  if not panel_is_open() or not state then
    return
  end
  local lines, hls = file_list_lines()
  vim.api.nvim_buf_set_option(panel.buf, 'modifiable', true)
  vim.api.nvim_buf_set_lines(panel.buf, 0, -1, false, lines)
  apply_list_hls(panel.buf, hls)
  vim.api.nvim_buf_set_option(panel.buf, 'modifiable', false)
  pcall(vim.api.nvim_win_set_cursor, panel.win, { state.file_idx, 0 })
end

local function close_panel()
  if panel_is_open() then
    vim.api.nvim_win_close(panel.win, true)
  end
  panel.win, panel.buf = nil, nil
end

local function open_panel()
  if not state or not diff.is_open() then
    return notify('Open a PR first', vim.log.levels.WARN)
  end
  -- the toggle keymap is buffer-local to the diff, so we are already in the review tab;
  -- pin a full-height split to the far left, leaving base|head to its right
  vim.cmd('topleft ' .. PANEL_W .. 'vnew')
  panel.win = vim.api.nvim_get_current_win()
  panel.buf = vim.api.nvim_get_current_buf()
  vim.api.nvim_buf_set_option(panel.buf, 'buftype', 'nofile')
  vim.api.nvim_buf_set_option(panel.buf, 'bufhidden', 'wipe')
  vim.api.nvim_buf_set_option(panel.buf, 'buflisted', false)
  pcall(vim.api.nvim_buf_set_name, panel.buf, 'pr://files')
  vim.api.nvim_win_set_option(panel.win, 'number', false)
  vim.api.nvim_win_set_option(panel.win, 'relativenumber', false)
  vim.api.nvim_win_set_option(panel.win, 'signcolumn', 'no')
  vim.api.nvim_win_set_option(panel.win, 'cursorline', true)
  vim.api.nvim_win_set_option(panel.win, 'winfixwidth', true)
  vim.api.nvim_win_set_option(panel.win, 'wrap', false)
  -- drop the global statuscolumn (line numbers) and the end-of-buffer ~ markers
  vim.api.nvim_win_set_option(panel.win, 'statuscolumn', '')
  vim.api.nvim_win_call(panel.win, function()
    vim.opt_local.fillchars:append 'eob: '
  end)

  vim.api.nvim_buf_set_keymap(panel.buf, 'n', '<CR>', '', {
    noremap = true,
    silent = true,
    callback = function()
      goto_file(vim.api.nvim_win_get_cursor(panel.win)[1])
    end,
  })
  vim.api.nvim_buf_set_keymap(panel.buf, 'n', 'q', '', { noremap = true, silent = true, callback = close_panel })

  refresh_panel()
end

local function toggle_panel()
  if panel_is_open() then
    close_panel()
  else
    open_panel()
  end
end

-- ---- comment / verdict actions --------------------------------------------------

-- Threads anchored on the cursor's (side, line), plus the resolved target.
local function threads_at_cursor()
  local target = diff.current_target()
  if not target then
    notify('Place the cursor inside the diff', vim.log.levels.WARN)
    return nil, nil
  end
  local matches = {}
  for _, th in ipairs(threads_for_file(target.path)) do
    if th.side == target.side and th.line == target.line then
      matches[#matches + 1] = th
    end
  end
  return matches, target
end

-- Pick one thread from a list (auto-selects when there is only one).
local function pick_thread(matches, prompt, cb)
  if #matches == 0 then
    return notify('No comment on this line', vim.log.levels.WARN)
  end
  if #matches == 1 then
    return cb(matches[1])
  end
  local items = {}
  for _, th in ipairs(matches) do
    items[#items + 1] = th
  end
  vim.ui.select(items, {
    prompt = prompt,
    format_item = function(th)
      local first = th.comments[1]
      return string.format('@%s: %s', first.user, (first.body or ''):gsub('\n', ' '):sub(1, 50))
    end,
  }, function(choice)
    if choice then
      cb(choice)
    end
  end)
end

-- Pick one comment in a thread matching `predicate` (auto-selects when only one).
local function pick_comment(thread, predicate, prompt, cb)
  local items = {}
  for _, c in ipairs(thread.comments) do
    if predicate(c) then
      items[#items + 1] = c
    end
  end
  if #items == 0 then
    return notify('No comment you can ' .. prompt .. ' here', vim.log.levels.WARN)
  end
  if #items == 1 then
    return cb(items[1])
  end
  vim.ui.select(items, {
    prompt = 'Which comment to ' .. prompt .. '?',
    format_item = function(c)
      return string.format('@%s: %s', c.user, (c.body or ''):gsub('\n', ' '):sub(1, 50))
    end,
  }, function(choice)
    if choice then
      cb(choice)
    end
  end)
end

local function add_comment()
  local target = diff.current_target()
  if not target then
    return notify('Place the cursor inside the diff to comment', vim.log.levels.WARN)
  end
  if not diff.is_commentable(target) then
    return notify('Line ' .. target.line .. ' is not part of the diff — GitHub only accepts comments on changed/context lines', vim.log.levels.WARN)
  end

  comment.input {
    title = string.format('comment on %s:%d (%s)', target.path, target.line, target.side),
    on_submit = function(body)
      if body == '' then
        return notify('Empty comment discarded', vim.log.levels.WARN)
      end
      if state.review_active then
        next_local_id = next_local_id + 1
        table.insert(state.queued, { path = target.path, line = target.line, side = target.side, body = body, local_id = next_local_id })
        rerender_current()
        notify(string.format('Comment queued (%d pending)', #state.queued))
      else
        gh.post_comment(state.repo, state.pr, {
          body = body,
          commit_id = state.head_sha,
          path = target.path,
          line = target.line,
          side = target.side,
        }, function(ok, err)
          vim.schedule(function()
            if ok then
              notify 'Comment posted'
              refresh_threads()
            else
              notify('Failed to post comment: ' .. (err or '?'), vim.log.levels.ERROR)
            end
          end)
        end)
      end
    end,
  }
end

local function edit_comment()
  local matches = threads_at_cursor()
  if not matches then
    return
  end
  pick_thread(matches, 'Edit a comment in which thread?', function(thread)
    pick_comment(
      thread,
      function(c)
        return thread.pending or c.can_update
      end,
      'edit',
      function(c)
        comment.input {
          title = 'edit comment',
          initial = vim.split(c.body or '', '\n', { plain = true }),
          on_submit = function(body)
            if body == '' then
              return notify('Empty edit discarded', vim.log.levels.WARN)
            end
            if thread.pending then
              for _, q in ipairs(state.queued) do
                if q.local_id == c.local_id then
                  q.body = body
                end
              end
              rerender_current()
              notify 'Queued comment updated'
            else
              gh.update_comment(state.repo, c.db_id, body, function(ok, err)
                vim.schedule(function()
                  if ok then
                    notify 'Comment edited'
                    refresh_threads()
                  else
                    notify('Failed to edit: ' .. (err or '?'), vim.log.levels.ERROR)
                  end
                end)
              end)
            end
          end,
        }
      end
    )
  end)
end

local function delete_comment()
  local matches = threads_at_cursor()
  if not matches then
    return
  end
  pick_thread(matches, 'Delete a comment in which thread?', function(thread)
    pick_comment(
      thread,
      function(c)
        return thread.pending or c.can_delete
      end,
      'delete',
      function(c)
        if vim.fn.confirm('Delete this comment?', '&Yes\n&No', 2) ~= 1 then
          return
        end
        if thread.pending then
          for i = #state.queued, 1, -1 do
            if state.queued[i].local_id == c.local_id then
              table.remove(state.queued, i)
            end
          end
          rerender_current()
          notify 'Queued comment deleted'
        else
          gh.delete_comment(state.repo, c.db_id, function(ok, err)
            vim.schedule(function()
              if ok then
                notify 'Comment deleted'
                refresh_threads()
              else
                notify('Failed to delete: ' .. (err or '?'), vim.log.levels.ERROR)
              end
            end)
          end)
        end
      end
    )
  end)
end

local function reply_comment()
  local matches = threads_at_cursor()
  if not matches then
    return
  end
  pick_thread(matches, 'Reply to which thread?', function(thread)
    if thread.pending then
      return notify('Submit the review before replying to a queued comment', vim.log.levels.WARN)
    end
    comment.input {
      title = 'reply',
      on_submit = function(body)
        if body == '' then
          return notify('Empty reply discarded', vim.log.levels.WARN)
        end
        gh.reply_comment(state.repo, state.pr, thread.root_id, body, function(ok, err)
          vim.schedule(function()
            if ok then
              notify 'Reply posted'
              refresh_threads()
            else
              notify('Failed to reply: ' .. (err or '?'), vim.log.levels.ERROR)
            end
          end)
        end)
      end,
    }
  end)
end

local function resolve_thread()
  local matches = threads_at_cursor()
  if not matches then
    return
  end
  pick_thread(matches, 'Resolve/unresolve which thread?', function(thread)
    if thread.pending or not thread.id then
      return notify('That comment is not posted yet', vim.log.levels.WARN)
    end
    local want_resolved = not thread.resolved
    if want_resolved and not thread.can_resolve then
      return notify('You cannot resolve this thread', vim.log.levels.WARN)
    end
    if not want_resolved and not thread.can_unresolve then
      return notify('You cannot unresolve this thread', vim.log.levels.WARN)
    end
    gh.set_thread_resolved(thread.id, want_resolved, function(ok, err)
      vim.schedule(function()
        if ok then
          notify(want_resolved and 'Thread resolved' or 'Thread unresolved')
          refresh_threads()
        else
          notify('Failed to update thread: ' .. (err or '?'), vim.log.levels.ERROR)
        end
      end)
    end)
  end)
end

local function start_review()
  if state.review_active then
    return notify 'Review already started; comments are being queued'
  end
  state.review_active = true
  notify 'Review started; comments are queued privately until you approve/request changes'
end

local EVENTS = {
  approve = { event = 'APPROVE', label = 'approve', requires_body = false },
  reject = { event = 'REQUEST_CHANGES', label = 'request changes', requires_body = true },
  comment_only = { event = 'COMMENT', label = 'comment', requires_body = true },
}

local function submit_verdict(kind)
  local spec = EVENTS[kind]
  local has_queued = state.review_active and #state.queued > 0
  -- a comment-only review needs no summary when it already carries queued line comments
  -- (the comments ARE the review); approve never needs one; request-changes always does
  local requires = spec.requires_body
  if kind == 'comment_only' and has_queued then
    requires = false
  end
  comment.input {
    title = string.format('%s: review summary%s', spec.label, requires and ' (required)' or ' (optional)'),
    on_submit = function(body)
      if body == '' and requires then
        return notify(spec.label .. ' requires a summary comment', vim.log.levels.WARN)
      end
      if kind == 'comment_only' and body == '' and not has_queued then
        return notify('Nothing to submit: add a line comment or a summary first', vim.log.levels.WARN)
      end
      local payload = { commit_id = state.head_sha, event = spec.event, body = body }
      if has_queued then
        payload.comments = {}
        for _, c in ipairs(state.queued) do
          payload.comments[#payload.comments + 1] = { path = c.path, line = c.line, side = c.side, body = c.body }
        end
      end
      gh.submit_review(state.repo, state.pr, payload, function(ok, err)
        vim.schedule(function()
          if ok then
            notify(spec.label .. ' submitted' .. (payload.comments and string.format(' with %d comments', #payload.comments) or ''))
            state.queued = {}
            state.review_active = false
            refresh_threads()
          else
            notify('Failed to submit review: ' .. (err or '?'), vim.log.levels.ERROR)
          end
        end)
      end)
    end,
  }
end

-- Drop the queued comments and end the review locally (nothing is sent to GitHub).
local function discard_review()
  if not state.review_active and #state.queued == 0 then
    return notify('No active review to discard', vim.log.levels.WARN)
  end
  local n = #state.queued
  if n > 0 and vim.fn.confirm(string.format('Discard %d queued comment(s) and end the review?', n), '&Yes\n&No', 2) ~= 1 then
    return
  end
  state.queued = {}
  state.review_active = false
  rerender_current()
  notify(string.format('Review discarded (%d queued comment(s) dropped)', n))
end

-- In checkout mode, offer to switch back to the branch we came from (skips if the tree
-- is now dirty so we never clobber in-progress work).
local function offer_branch_return(branch)
  if vim.fn.confirm('Return to branch ' .. branch .. '?', '&Yes\n&No', 1) ~= 1 then
    return
  end
  gh.is_dirty(function(dirty)
    vim.schedule(function()
      if dirty then
        return notify('Working tree is dirty; staying put. Commit/stash, then `git checkout ' .. branch .. '`', vim.log.levels.WARN)
      end
      gh.git_checkout(branch, function(ok, err)
        vim.schedule(function()
          if ok then
            notify('Switched back to ' .. branch)
          else
            notify('Could not switch back: ' .. (err or '?'), vim.log.levels.ERROR)
          end
        end)
      end)
    end)
  end)
end

local function close_session()
  if state and state.review_active and #state.queued > 0 then
    if vim.fn.confirm(string.format('Discard %d queued comment(s) and close the review?', #state.queued), '&Yes\n&No', 2) ~= 1 then
      return
    end
  end
  local return_branch = state and state.mode == 'local' and state.original_branch or nil
  diff.close() -- closes the review tab (and the panel window living in it)
  panel.win, panel.buf = nil, nil
  state = nil
  if return_branch then
    offer_branch_return(return_branch)
  end
end

M.handlers = {
  comment = add_comment,
  edit = edit_comment,
  delete = delete_comment,
  reply = reply_comment,
  resolve = resolve_thread,
  start_review = start_review,
  approve = function()
    submit_verdict 'approve'
  end,
  reject = function()
    submit_verdict 'reject'
  end,
  comment_only = function()
    submit_verdict 'comment_only'
  end,
  discard = discard_review,
  next_file = function()
    goto_file(state.file_idx + 1)
  end,
  prev_file = function()
    goto_file(state.file_idx - 1)
  end,
  files = open_navigator,
  panel = toggle_panel,
  close = close_session,
}

-- ---- entry point ----------------------------------------------------------------

-- If a queued review is active, confirm discarding it before switching PRs. Returns
-- true to proceed, false to abort.
local function ok_to_switch(action)
  if state and state.review_active and #state.queued > 0 then
    return vim.fn.confirm(string.format('A review of #%d has %d queued comment(s). Discard and %s?', state.pr, #state.queued, action), '&Yes\n&No', 2) == 1
  end
  return true
end

-- Fetch a PR's shas/files/comments/threads, build the session, and open the first file.
-- opts = { mode = 'view' | 'local', original_branch, root }.
local function load_and_start(repo, pr, opts)
  local shas, files, comments, gql
  local pending = 4
  local failed = nil
  local function step(err)
    if err then
      failed = failed or err
    end
    pending = pending - 1
    if pending > 0 then
      return
    end
    vim.schedule(function()
      if failed then
        return notify('Failed to load PR: ' .. failed, vim.log.levels.ERROR)
      end
      if not files or #files == 0 then
        return notify('PR #' .. pr.number .. ' has no changed files', vim.log.levels.WARN)
      end
      state = {
        repo = repo,
        pr = pr.number,
        title = pr.title,
        head_sha = shas.head,
        base_sha = shas.base,
        files = files,
        file_idx = 1,
        contents = {},
        posted_threads = build_posted_threads(comments, gql),
        queued = {},
        review_active = false,
        mode = opts.mode,
        original_branch = opts.original_branch,
        root = opts.root,
      }
      show_current()
    end)
  end

  gh.pr_shas(pr.number, function(s, err)
    shas = s
    step(err)
  end)
  gh.pr_files(repo, pr.number, function(f, err)
    files = f
    step(err)
  end)
  gh.pr_comments(repo, pr.number, function(c)
    comments = c
    step()
  end)
  gh.review_threads(repo, pr.number, function(t)
    gql = t
    step()
  end)
  -- collaborators feed the @mention cmp source; failure is non-fatal
  gh.collaborators(repo, function(logins)
    cmp_source.set_logins(logins)
  end)
end

-- View a PR (read-only, sourced from the API; nothing is checked out).
function M.open(pr)
  if not ok_to_switch('open #' .. pr.number) then
    return
  end
  if diff.is_open() then
    diff.close()
  end
  notify(string.format('Loading PR #%d…', pr.number))
  gh.resolve_repo(nil, function(repo, rerr)
    if not repo then
      return vim.schedule(function()
        notify('Could not resolve repo: ' .. (rerr or '?'), vim.log.levels.ERROR)
      end)
    end
    load_and_start(repo, pr, { mode = 'view' })
  end)
end

-- Check out a PR locally (gh pr checkout) and review it with the real on-disk files on
-- the head side. Aborts if the working tree is dirty; offers to return on close.
function M.checkout(pr)
  if not ok_to_switch('check out #' .. pr.number) then
    return
  end
  if diff.is_open() then
    diff.close()
  end

  gh.is_dirty(function(dirty)
    if dirty then
      return vim.schedule(function()
        notify('Working tree has uncommitted changes; commit or stash before checking out', vim.log.levels.WARN)
      end)
    end
    gh.current_branch(function(branch)
      gh.repo_root(function(root)
        if not root then
          return vim.schedule(function()
            notify('Not inside a git repository', vim.log.levels.ERROR)
          end)
        end
        vim.schedule(function()
          notify(string.format('Checking out PR #%d…', pr.number))
        end)
        gh.pr_checkout(pr.number, function(ok, err)
          if not ok then
            return vim.schedule(function()
              notify('Checkout failed: ' .. (err or '?'), vim.log.levels.ERROR)
            end)
          end
          gh.resolve_repo(nil, function(repo, rerr)
            if not repo then
              return vim.schedule(function()
                notify('Could not resolve repo: ' .. (rerr or '?'), vim.log.levels.ERROR)
              end)
            end
            load_and_start(repo, pr, { mode = 'local', original_branch = branch, root = root })
          end)
        end)
      end)
    end)
  end)
end

return M
