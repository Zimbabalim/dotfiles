-- Beads panel: issues from the nearest .beads database, in its own tab (like the git changes tab).
-- <leader>b opens the tab, or jumps to it; pressed in the beads tab it goes back to the previous tab.
-- It shows the project of the file you were in (or nvim's folder), follows you as you switch
-- projects in other tabs, and refreshes when the database changes (plus every 30s while open).
--
-- Read-only: it only runs `bd list --json` and `bd show`, so it never writes to the project.
-- (bv, the beads TUI, exports .beads/issues.jsonl into the project each time it opens.)
--
-- Layout: the issue list on the left, details (bd show) for the issue under the cursor on the right.
--
-- Keys in the list:
--   Enter  jump into the details column     y  copy the issue id
--   c      show / hide closed issues        r  refresh now
--   q      close the beads tab
-- In the details column: q (or Ctrl-h) goes back to the list.

local M = {}

local width = 60 -- fallback for title truncation; the real width is the window's
local poll_ms = 30000
local ns = vim.api.nvim_create_namespace("beads_panel")
local state = {
  buf = nil,
  root = nil, -- project folder containing .beads
  issues = nil, -- last bd list result
  error = nil,
  loading = false,
  dirty = false, -- a refresh was requested while one was running
  show_closed = false,
  line_ids = {}, -- buffer line -> issue id
  watcher = nil,
  timer = nil,
  updated = nil,
}

local colors = {
  BeadsTitle = { fg = "#e6e6e6", bold = true },
  BeadsDim = { fg = "#8a8a8a" },
  BeadsId = { fg = "#7aa2f7" },
  BeadsP0 = { fg = "#e05252", bold = true },
  BeadsP1 = { fg = "#e8743b", bold = true },
  BeadsP2 = { fg = "#d9a520" },
  BeadsP3 = { fg = "#8a8a8a" },
  BeadsActive = { fg = "#e8743b" },
  BeadsReady = { fg = "#3fb68b" },
  BeadsWaiting = { fg = "#8a8a8a" },
  BeadsBlocked = { fg = "#e05252" },
  BeadsHuman = { fg = "#e05252", bold = true },
}
for name, hl in pairs(colors) do
  vim.api.nvim_set_hl(0, name, hl)
end

-- Nearest folder above `start` with a project .beads database.
-- (~/.beads also exists, but it's bd's machine-wide data, not a project: it has no config.yaml/metadata.json.)
local function beads_root(start)
  for dir in vim.fs.parents(start .. "/x") do
    if vim.uv.fs_stat(dir .. "/.beads/metadata.json") or vim.uv.fs_stat(dir .. "/.beads/config.yaml") then
      return dir
    end
  end
end

local function find_root()
  local name = vim.api.nvim_buf_get_name(0)
  local start = (name ~= "" and vim.bo.buftype == "") and vim.fs.dirname(name) or vim.fn.getcwd()
  return beads_root(start) or beads_root(vim.fn.getcwd())
end

-- The beads window, in whichever tab it's in.
local function any_win()
  if not (state.buf and vim.api.nvim_buf_is_valid(state.buf)) then return nil end
  return vim.fn.win_findbuf(state.buf)[1]
end

local function decode(str)
  return pcall(vim.json.decode, str, { luanil = { object = true, array = true } })
end

local function has_label(issue, label)
  for _, l in ipairs(issue.labels or {}) do
    if l == label then return true end
  end
  return false
end

-- Group issues: in progress / ready / waiting on another issue / blocked / deferred / closed.
local function group(issues)
  local by_id = {}
  for _, i in ipairs(issues) do by_id[i.id] = i end
  local groups = { in_progress = {}, ready = {}, waiting = {}, blocked = {}, deferred = {}, closed = {} }
  for _, i in ipairs(issues) do
    if i.status == "open" then
      local waiting = false
      for _, dep in ipairs(i.dependencies or {}) do
        local target = by_id[dep.depends_on_id]
        if dep.type == "blocks" and target and target.status ~= "closed" then waiting = true end
      end
      table.insert(waiting and groups.waiting or groups.ready, i)
    elseif groups[i.status] then
      table.insert(groups[i.status], i)
    else
      table.insert(groups.ready, i)
    end
  end
  local function by_priority(a, b)
    if (a.priority or 9) ~= (b.priority or 9) then return (a.priority or 9) < (b.priority or 9) end
    return (a.updated_at or "") > (b.updated_at or "")
  end
  for k, list in pairs(groups) do
    if k == "closed" then
      table.sort(list, function(a, b) return (a.closed_at or "") > (b.closed_at or "") end)
    else
      table.sort(list, by_priority)
    end
  end
  return groups
end

local sections = {
  { key = "in_progress", label = "In progress", icon = "◐", hl = "BeadsActive" },
  { key = "ready", label = "Ready", icon = "○", hl = "BeadsReady" },
  { key = "waiting", label = "Waiting on another issue", icon = "⧗", hl = "BeadsWaiting" },
  { key = "blocked", label = "Blocked", icon = "✗", hl = "BeadsBlocked" },
  { key = "deferred", label = "Deferred", icon = "❄", hl = "BeadsWaiting" },
  { key = "closed", label = "Closed", icon = "✓", hl = "BeadsDim" },
}

local function render()
  local lines, hls, line_ids = {}, {}, {}
  local function add(text, spans)
    table.insert(lines, text)
    for _, s in ipairs(spans or {}) do table.insert(hls, { #lines - 1, s[1], s[2], s[3] }) end
  end

  local project = state.root and vim.fn.fnamemodify(state.root, ":t") or "no project"
  add(" Beads · " .. project, { { 0, -1, "BeadsTitle" } })

  if not state.root then
    add("")
    add(" No .beads database in this folder or above it.", { { 0, -1, "BeadsDim" } })
    add(" Open a file in a beads project (or cd into one).", { { 0, -1, "BeadsDim" } })
    return lines, hls, line_ids
  end
  if state.error then
    add("")
    add(" bd failed:", { { 0, -1, "BeadsBlocked" } })
    for _, l in ipairs(vim.split(state.error, "\n", { trimempty = true })) do add("   " .. l, { { 0, -1, "BeadsDim" } }) end
    return lines, hls, line_ids
  end
  if not state.issues then
    add("")
    add(" Loading…", { { 0, -1, "BeadsDim" } })
    return lines, hls, line_ids
  end

  local groups = group(state.issues)
  local active = #groups.in_progress + #groups.ready + #groups.waiting + #groups.blocked
  add(string.format(" %d active · %d ready · %d closed", active, #groups.ready, #groups.closed), { { 0, -1, "BeadsDim" } })

  for _, sec in ipairs(sections) do
    local list = groups[sec.key]
    if #list > 0 then
      add("")
      if sec.key == "closed" and not state.show_closed then
        add(string.format(" %s (%d)  c to show", sec.label, #list), { { 0, -1, "BeadsDim" } })
      else
        add(string.format(" %s (%d)", sec.label, #list), { { 0, -1, "BeadsTitle" } })
        for _, i in ipairs(list) do
          local human = has_label(i, "needs-human")
          local prio = i.priority and ("P" .. i.priority) or "  "
          local prefix = string.format(" %s %s %s ", sec.icon, i.id, prio)
          local mark = human and "! " or ""
          local win = any_win()
          local w = win and vim.api.nvim_win_get_width(win) or width
          local max = w - vim.fn.strdisplaywidth(prefix) - #mark - 1
          local title = (i.title or ""):gsub("%s+", " ")
          if vim.fn.strdisplaywidth(title) > max then
            title = vim.fn.strcharpart(title, 0, max - 1) .. "…"
          end
          local text = prefix .. mark .. title
          local icon_end = 1 + #sec.icon
          local id_start = icon_end + 1
          local id_end = id_start + #i.id
          local p_end = id_end + 1 + #prio
          local spans = {
            { 1, icon_end, sec.hl },
            { id_start, id_end, "BeadsId" },
            { id_end + 1, p_end, "BeadsP" .. math.min(i.priority or 3, 3) },
          }
          if human then table.insert(spans, { #prefix, #prefix + 1, "BeadsHuman" }) end
          if sec.key == "closed" then table.insert(spans, { #prefix, #text, "BeadsDim" }) end
          add(text, spans)
          line_ids[#lines] = i.id
        end
      end
    end
  end

  add("")
  add(string.format(" %s%s · ⏎ details · y copy id · c closed · r refresh",
    state.loading and "refreshing… " or "", state.updated and os.date("%H:%M", state.updated) or ""),
    { { 0, -1, "BeadsDim" } })
  return lines, hls, line_ids
end

local function redraw()
  if not (state.buf and vim.api.nvim_buf_is_valid(state.buf)) then return end
  local lines, hls, line_ids = render()
  state.line_ids = line_ids
  vim.bo[state.buf].modifiable = true
  vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, lines)
  vim.bo[state.buf].modifiable = false
  vim.api.nvim_buf_clear_namespace(state.buf, ns, 0, -1)
  for _, h in ipairs(hls) do
    local len = #lines[h[1] + 1]
    local e = h[3] == -1 and len or math.min(h[3], len)
    if e > h[2] then
      vim.api.nvim_buf_set_extmark(state.buf, ns, h[1], h[2], { end_col = e, hl_group = h[4] })
    end
  end
end

local function panel_win()
  if not (state.buf and vim.api.nvim_buf_is_valid(state.buf)) then return nil end
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if vim.api.nvim_win_get_buf(win) == state.buf then return win end
  end
end

local details_changed -- defined with the details column below

-- Run `bd list` in the background; coalesce requests that arrive while one is running.
local function refresh()
  if not state.root then
    redraw()
    return
  end
  if state.loading then
    state.dirty = true
    return
  end
  state.loading = true
  redraw()
  local root = state.root
  vim.system({ "bd", "list", "--json", "--brief", "--all", "--limit", "0" }, { cwd = root, text = true },
    vim.schedule_wrap(function(res)
      state.loading = false
      if root == state.root then
        if res.code == 0 then
          local ok, data = decode(res.stdout)
          state.issues = ok and type(data) == "table" and data or {}
          state.error = (not ok) and "could not read bd output" or nil
          state.updated = os.time()
          details_changed()
        else
          state.error = (res.stderr ~= "" and res.stderr or res.stdout)
        end
      end
      redraw()
      if state.dirty then
        state.dirty = false
        refresh()
      end
    end))
end

local function unwatch()
  if state.watcher then
    state.watcher:stop()
    state.watcher:close()
    state.watcher = nil
  end
end

-- Writes to the database touch .beads/last-touched; reads don't.
local function watch()
  unwatch()
  if not state.root then return end
  local debounce
  state.watcher = vim.uv.new_fs_event()
  state.watcher:start(state.root .. "/.beads", {}, vim.schedule_wrap(function(_, filename)
    if filename and filename:match("%.jsonl") then return end -- ignore exports
    if debounce then debounce:stop() end
    debounce = vim.defer_fn(refresh, 500)
  end))
end

local function set_root(root)
  if root == state.root then return end
  state.root = root
  state.issues, state.error = nil, nil
  watch()
  refresh()
end

-- Details column: `bd show <id>` (bd's own formatted text) for the issue under the cursor.
local details = {
  buf = nil,
  id = nil, -- issue shown (or being loaded)
  cache = {}, -- id -> lines; cleared whenever the issue list reloads
  timer = nil, -- debounce while moving through the list
}

local function details_win()
  if not (details.buf and vim.api.nvim_buf_is_valid(details.buf)) then return nil end
  return vim.fn.win_findbuf(details.buf)[1]
end

local function set_details(lines)
  if not (details.buf and vim.api.nvim_buf_is_valid(details.buf)) then return end
  vim.bo[details.buf].modifiable = true
  vim.api.nvim_buf_set_lines(details.buf, 0, -1, false, lines)
  vim.bo[details.buf].modifiable = false
  vim.api.nvim_buf_clear_namespace(details.buf, ns, 0, -1)
  if lines[1] and #lines[1] > 0 then
    vim.api.nvim_buf_set_extmark(details.buf, ns, 0, 0, { end_col = #lines[1], hl_group = "BeadsTitle" })
  end
  local win = details_win()
  if win then vim.api.nvim_win_set_cursor(win, { 1, 0 }) end
end

local function load_details(id, force)
  if not id or not state.root then return end
  if id == details.id and not force then return end
  details.id = id
  if details.cache[id] then
    set_details(details.cache[id])
    return
  end
  if not force then set_details({ " Loading " .. id .. "…" }) end
  local root = state.root
  vim.system({ "bd", "show", id }, { cwd = root, text = true, env = { NO_COLOR = "1" } },
    vim.schedule_wrap(function(res)
      local text = res.code == 0 and res.stdout or (res.stderr ~= "" and res.stderr or res.stdout)
      local lines = vim.split(text:gsub("\27%[[%d;]*m", ""), "\n")
      while #lines > 0 and lines[#lines] == "" do table.remove(lines) end
      if res.code == 0 and root == state.root then details.cache[id] = lines end
      if id == details.id then set_details(lines) end -- ignore answers for an issue you've moved past
    end))
end

local function cursor_id()
  local win = any_win()
  if not win then return nil end
  return state.line_ids[vim.api.nvim_win_get_cursor(win)[1]]
end

-- Moving through the list: show the issue under the cursor once you pause.
local function follow_cursor()
  if not details_win() then return end
  details.timer = details.timer or vim.uv.new_timer()
  details.timer:stop()
  details.timer:start(120, 0, vim.schedule_wrap(function() load_details(cursor_id()) end))
end

-- The issue list reloaded (database changed): drop cached details and reload the one on screen.
details_changed = function()
  details.cache = {}
  if details_win() and details.id then load_details(details.id, true) end
end

local function ensure_details_buf()
  if details.buf and vim.api.nvim_buf_is_valid(details.buf) then return end
  details.buf = vim.api.nvim_create_buf(false, true)
  vim.bo[details.buf].bufhidden = "hide"
  vim.bo[details.buf].filetype = "beads-details"
  vim.api.nvim_buf_set_name(details.buf, "beads://details")
  vim.bo[details.buf].modifiable = false
  local back = function()
    local win = any_win()
    if win then vim.api.nvim_set_current_win(win) end
  end
  vim.keymap.set("n", "q", back, { buffer = details.buf, nowait = true })
end

-- Open the details column to the right of the list (if it isn't open already).
local function open_details_win(list_win)
  ensure_details_buf()
  local win = details_win()
  if win then return win end
  local cur = vim.api.nvim_get_current_win()
  vim.api.nvim_set_current_win(list_win)
  vim.cmd("rightbelow vsplit")
  win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(win, details.buf)
  for opt, val in pairs({ number = false, relativenumber = false, signcolumn = "no", wrap = true,
    linebreak = true, cursorline = false }) do
    vim.wo[win][opt] = val
  end
  vim.api.nvim_win_set_width(list_win, math.max(50, math.floor(vim.o.columns * 0.45)))
  vim.api.nvim_set_current_win(vim.api.nvim_win_is_valid(cur) and cur or list_win)
  details.id = nil
  if not cursor_id() then set_details({ " Move to an issue to see its details." }) end
  return win
end

-- Enter: show the issue under the cursor and move into the details column.
local function show_details()
  local id = cursor_id()
  if not id then return end
  local win = open_details_win(vim.api.nvim_get_current_win())
  load_details(id)
  vim.api.nvim_set_current_win(win)
end

local function ensure_buf()
  if state.buf and vim.api.nvim_buf_is_valid(state.buf) then return end
  state.buf = vim.api.nvim_create_buf(false, true)
  vim.bo[state.buf].bufhidden = "hide"
  vim.bo[state.buf].filetype = "beads"
  vim.api.nvim_buf_set_name(state.buf, "beads://panel")
  local map = function(lhs, fn) vim.keymap.set("n", lhs, fn, { buffer = state.buf, nowait = true }) end
  map("<CR>", show_details)
  vim.api.nvim_create_autocmd("CursorMoved", { buffer = state.buf, callback = follow_cursor })
  map("r", refresh)
  map("q", function() M.close() end)
  map("c", function()
    state.show_closed = not state.show_closed
    redraw()
  end)
  map("y", function()
    local id = state.line_ids[vim.api.nvim_win_get_cursor(0)[1]]
    if id then
      vim.fn.setreg("+", id)
      vim.fn.setreg('"', id)
      vim.notify("Copied " .. id)
    end
  end)
end

local prev_tab = nil -- the tab you came from, for going back

function M.open()
  local win = any_win()
  if win then -- already open: jump to its tab
    prev_tab = vim.api.nvim_get_current_tabpage()
    vim.api.nvim_set_current_win(win)
    return
  end
  ensure_buf()
  local root = find_root()
  prev_tab = vim.api.nvim_get_current_tabpage()
  vim.cmd("tabnew")
  local scratch = vim.api.nvim_get_current_buf()
  win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(win, state.buf)
  if scratch ~= state.buf then pcall(vim.api.nvim_buf_delete, scratch, { force = true }) end
  for opt, val in pairs({ number = false, relativenumber = false, signcolumn = "no", wrap = false,
    cursorline = true }) do
    vim.wo[win][opt] = val
  end
  open_details_win(win)
  set_root(root)
  redraw()
  if not state.timer then
    state.timer = vim.uv.new_timer()
    state.timer:start(poll_ms, poll_ms, vim.schedule_wrap(function()
      if any_win() then refresh() end
    end))
  end
end

function M.close()
  local win = any_win()
  if win then
    local tab = vim.api.nvim_win_get_tabpage(win)
    if #vim.api.nvim_list_tabpages() > 1 then
      vim.cmd.tabclose(vim.api.nvim_tabpage_get_number(tab))
    else
      vim.api.nvim_win_set_buf(win, vim.api.nvim_create_buf(true, false))
    end
    if prev_tab and vim.api.nvim_tabpage_is_valid(prev_tab) then
      vim.api.nvim_set_current_tabpage(prev_tab)
    end
  end
  unwatch()
  if state.timer then
    state.timer:stop()
    state.timer:close()
    state.timer = nil
  end
  state.root = nil -- re-detect next time it opens
end

-- In the beads tab: go back to where you were. Anywhere else: open or jump to the beads tab.
function M.toggle()
  if panel_win() then
    if prev_tab and vim.api.nvim_tabpage_is_valid(prev_tab) and prev_tab ~= vim.api.nvim_get_current_tabpage() then
      vim.api.nvim_set_current_tabpage(prev_tab)
    else
      vim.cmd("tabprevious")
    end
  else
    M.open()
  end
end

local group = vim.api.nvim_create_augroup("beads_panel", { clear = true })

-- Follow the project of whatever file you switch to (in any tab).
vim.api.nvim_create_autocmd({ "BufEnter", "DirChanged" }, {
  group = group,
  callback = function(args)
    if not any_win() or args.buf == state.buf or vim.bo[args.buf].buftype ~= "" then return end
    local root = find_root()
    if root then set_root(root) end
  end,
})

-- Re-fit titles when the window size changes.
vim.api.nvim_create_autocmd("VimResized", { group = group, callback = function() redraw() end })

-- Closing the tab with :tabclose (rather than q) still stops the watcher and timer.
vim.api.nvim_create_autocmd("TabClosed", {
  group = group,
  callback = function()
    if state.timer and not any_win() then M.close() end
  end,
})

vim.api.nvim_create_user_command("Beads", M.toggle, { desc = "Beads tab" })
vim.keymap.set("n", "<leader>b", M.toggle, { desc = "Beads tab (again: back)" })

return M
