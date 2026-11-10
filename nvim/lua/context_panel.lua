-- Claude context panel (like the "Context" card in Claude Code on the web).
-- <leader>ai toggles a floating card in the top-right corner that live-updates as Claude works.
--
-- Data comes from ~/.cache/claude-context/<session>.json, written by ~/.claude/statusline-tee.sh
-- (Claude Code's statusline hook). It shows the most recently active Claude session whose
-- project folder is nvim's current folder, or the most recent session anywhere if none match.
--
-- Claude Code doesn't expose the per-category breakdown that /context shows, so the split here is
-- an estimate: the size of the session's first request ≈ system prompt + tools + skills + memory;
-- everything above that ≈ conversation.
--
-- Background tasks (shell commands and subagents Claude started in the background) are read from
-- the session transcript: the launch entry gives the description and start time, and the
-- <task-notification> Claude receives later gives the final status.
--
-- Files Claude touched come from the same transcript: successful Edit / Write / NotebookEdit calls.
-- Click a file, or focus the card (<leader>ai again) and press Enter on it, to open it.
--
-- Mouse: drag the top border (the title row) to move the card. Drag the left, right or bottom
-- border, or a bottom corner, to resize it. Dragging the bottom border down past the last line of
-- content puts the height back on automatic.

local M = {}

local data_dir = vim.fn.expand("~/.cache/claude-context")
local width = 44
local min_width, min_height = 30, 3
local ns = vim.api.nvim_create_namespace("claude_context_panel")
local state = {
  buf = nil, win = nil, watcher = nil, timer = nil, line_files = {},
  line_count = 1,
  row = nil, col = nil, -- nil until dragged: the card sits in the top-right corner
  height = nil, -- nil until resized: the card is as tall as its content
}
local baseline_cache = {} -- session_id -> tokens in first request

local colors = {
  ClaudeCtxTitle = { fg = "#e6e6e6", bold = true },
  ClaudeCtxDim = { fg = "#8a8a8a" },
  ClaudeCtxSystem = { fg = "#3b8eea" },
  ClaudeCtxConvo = { fg = "#e8743b" },
  ClaudeCtxFree = { fg = "#3a3a3a" },
  ClaudeCtxWarn = { fg = "#d9a520", bold = true },
  ClaudeCtxBad = { fg = "#e05252", bold = true },
  ClaudeCtxGood = { fg = "#3fb68b" },
}
for name, hl in pairs(colors) do
  vim.api.nvim_set_hl(0, name, hl)
end

-- Decode JSON with null → nil (by default null becomes vim.NIL, which can't be indexed).
local function decode(str)
  return pcall(vim.json.decode, str, { luanil = { object = true, array = true } })
end

local function read_json(path)
  local f = io.open(path, "r")
  if not f then return nil end
  local ok, decoded = decode(f:read("*a"))
  f:close()
  return ok and decoded or nil
end

-- Pick the session to show: newest file for nvim's cwd, else newest overall.
local function current_session()
  local cwd = vim.fn.getcwd()
  local best, best_any
  for _, path in ipairs(vim.fn.glob(data_dir .. "/*.json", false, true)) do
    local mtime = vim.fn.getftime(path)
    local entry = { path = path, mtime = mtime }
    if not best_any or mtime > best_any.mtime then best_any = entry end
    local d = read_json(path)
    local proj = d and d.workspace and (d.workspace.project_dir or d.workspace.current_dir)
    if proj == cwd and (not best or mtime > best.mtime) then best = entry end
  end
  local pick = best or best_any
  return pick and read_json(pick.path), pick and pick.mtime, best ~= nil
end

-- Tokens sent in the session's first API request (system prompt, tools, skills, first message).
local function baseline(d)
  if baseline_cache[d.session_id] then return baseline_cache[d.session_id] end
  local f = d.transcript_path and io.open(d.transcript_path, "r")
  if not f then return nil end
  for line in f:lines() do
    if line:find('"usage"', 1, true) and line:find('"type":"assistant"', 1, true) then
      local ok, e = decode(line)
      local u = ok and e.message and e.message.usage
      if u then
        local n = (u.input_tokens or 0) + (u.cache_creation_input_tokens or 0) + (u.cache_read_input_tokens or 0)
        f:close()
        baseline_cache[d.session_id] = n
        return n
      end
    end
  end
  f:close()
end

local function fmt_tokens(n)
  if n >= 1e6 then return (string.format("%.1fM", n / 1e6):gsub("%.0M", "M")) end
  if n >= 1e3 then return string.format("%.1fk", n / 1e3) end
  return tostring(n)
end

local function fmt_duration(ms)
  local m = math.floor(ms / 60000)
  if m < 60 then return m .. "m" end
  return string.format("%dh %dm", math.floor(m / 60), m % 60)
end

local function fmt_until(epoch)
  local s = math.max(0, epoch - os.time())
  local d, h, m = math.floor(s / 86400), math.floor(s % 86400 / 3600), math.floor(s % 3600 / 60)
  if d > 0 then return string.format("%dd %dh", d, h) end
  if h > 0 then return string.format("%dh %dm", h, m) end
  return m .. "m"
end

-- Seconds as "45s" / "12m" / "1h 5m".
local function fmt_elapsed(s)
  s = math.max(0, math.floor(s))
  if s < 60 then return s .. "s" end
  if s < 3600 then return math.floor(s / 60) .. "m" end
  return string.format("%dh %dm", math.floor(s / 3600), math.floor(s % 3600 / 60))
end

-- "2026-10-30T15:59:12.123Z" (UTC) → epoch seconds.
local function iso_to_epoch(ts)
  local y, mo, d, h, mi, sec = (ts or ""):match("(%d+)-(%d+)-(%d+)T(%d+):(%d+):(%d+)")
  if not y then return nil end
  local now = os.time()
  local loc, utc = os.date("*t", now), os.date("!*t", now)
  utc.isdst = loc.isdst
  local utc_offset = os.time(loc) - os.time(utc)
  return os.time({ year = y, month = mo, day = d, hour = h, min = mi, sec = sec, isdst = false }) + utc_offset
end

local function text_of(content)
  if type(content) == "string" then return content end
  local parts = {}
  for _, b in ipairs(type(content) == "table" and content or {}) do
    if type(b) == "table" and b.type == "text" and b.text then table.insert(parts, b.text) end
  end
  return table.concat(parts, "\n")
end

-- Background tasks per transcript, read incrementally (transcripts can be tens of MB).
local tasks_cache = {} -- transcript path -> { offset, pending, by_id, list }
local background_tools = { Bash = "shell", Agent = "agent", Task = "agent", Monitor = "monitor" }
local file_tools = { Edit = true, Write = true, MultiEdit = true, NotebookEdit = true }

-- The live Claude process for a session, from ~/.claude/sessions/<pid>.json (nil if not running).
local function session_process(session_id)
  for _, path in ipairs(vim.fn.glob(vim.fn.expand("~/.claude/sessions") .. "/*.json", false, true)) do
    local p = read_json(path)
    if p and p.sessionId == session_id and p.pid and vim.uv.kill(p.pid, 0) == 0 then
      return p
    end
  end
end

local function scan_tasks(path)
  local c = tasks_cache[path]
  if not c then
    c = { offset = 0, pending = {}, by_id = {}, by_task = {}, list = {}, file_ops = {}, files = {} }
    tasks_cache[path] = c
  end
  local f = io.open(path, "r")
  if not f then return c end
  f:seek("set", c.offset)
  local chunk = f:read("*a") or ""
  f:close()
  local last_nl = chunk:match(".*()\n") -- only consume complete lines
  if not last_nl then return c end
  c.offset = c.offset + last_nl

  for line in chunk:sub(1, last_nl):gmatch("[^\n]+") do
    if line:find("tool_use", 1, true) or line:find("task-notification", 1, true) then
      local ok, e = decode(line)
      local content = ok and e and e.message and e.message.content
      if type(content) == "table" then
        for _, b in ipairs(content) do
          if b.type == "tool_use" and b.name == "TaskStop" then
            local t = c.by_task[(b.input or {}).task_id or (b.input or {}).shell_id or ""]
            if t and t.status == "running" then
              t.status = "stopped"
              t.finished = iso_to_epoch(e.timestamp)
            end
          elseif b.type == "tool_use" and background_tools[b.name] then
            local input = b.input or {}
            c.pending[b.id] = {
              kind = background_tools[b.name],
              desc = input.description or input.command or b.name,
              started = iso_to_epoch(e.timestamp),
            }
          elseif b.type == "tool_use" and file_tools[b.name] then
            local input = b.input or {}
            local path = input.file_path or input.notebook_path
            if path then c.file_ops[b.id] = { path = path, tool = b.name } end
          elseif b.type == "tool_result" and c.file_ops[b.tool_use_id] then
            local op = c.file_ops[b.tool_use_id]
            c.file_ops[b.tool_use_id] = nil
            if not b.is_error then
              local fe = c.files[op.path]
              if not fe then
                fe = { path = op.path, edits = 0 }
                c.files[op.path] = fe
              end
              fe.edits = fe.edits + 1
              fe.last = iso_to_epoch(e.timestamp) or os.time()
              if text_of(b.content):find("^File created") then fe.created = true end
            end
          elseif b.type == "tool_result" and c.pending[b.tool_use_id] then
            local r = text_of(b.content)
            -- Match Claude Code's own launch messages only (not command output that mentions them).
            if r:find("^Command running in background with ID:") or r:find("^Command did not complete.-moved to the background")
              or r:find("^Async agent launched") then
              local t = c.pending[b.tool_use_id]
              t.status = "running"
              c.by_id[b.tool_use_id] = t
              local task_id = r:match("with ID: (%w+)") or r:match("%(ID: (%w+)%)") or r:match("agentId: (%w+)")
              if task_id then c.by_task[task_id] = t end
              table.insert(c.list, t)
            end
            c.pending[b.tool_use_id] = nil
          end
        end
      end
      local txt = ok and e and e.type == "user" and text_of(content) or ""
      for block in txt:gmatch("<task%-notification>(.-)</task%-notification>") do
        local t = c.by_id[block:match("<tool%-use%-id>(.-)</tool%-use%-id>") or ""]
        if t then
          t.status = block:match("<status>(.-)</status>") or "completed"
          t.finished = iso_to_epoch(e.timestamp)
        end
      end
    end
  end
  return c
end

local function pct_hl(p)
  if p >= 80 then return "ClaudeCtxBad" elseif p >= 50 then return "ClaudeCtxWarn" end
  return "ClaudeCtxGood"
end

-- Build lines + highlights. Each highlight: { line, col_start, col_end, group } (byte columns).
local function render()
  local lines, hls, line_files = {}, {}, {}
  local function add(text, spans)
    table.insert(lines, text)
    for _, s in ipairs(spans or {}) do
      table.insert(hls, { #lines - 1, s[1], s[2], s[3] })
    end
  end
  local function row(left, right, left_hl, right_hl)
    local pad = width - 2 - vim.fn.strdisplaywidth(left) - vim.fn.strdisplaywidth(right)
    local text = " " .. left .. string.rep(" ", math.max(1, pad)) .. right
    add(text, {
      { 1, 1 + #left, left_hl },
      { #text - #right, #text, right_hl },
    })
  end

  local d, mtime, matched = current_session()
  if not d or not d.context_window then
    add(" Context", { { 0, -1, "ClaudeCtxTitle" } })
    add("")
    add(" No Claude session data yet.", { { 0, -1, "ClaudeCtxDim" } })
    add(" Start Claude (<leader>t, run claude),", { { 0, -1, "ClaudeCtxDim" } })
    add(" send a message; this fills in by itself.", { { 0, -1, "ClaudeCtxDim" } })
    return lines, hls
  end

  local cw = d.context_window
  local u = cw.current_usage or {}
  local used = (u.input_tokens or 0) + (u.cache_creation_input_tokens or 0) + (u.cache_read_input_tokens or 0)
  local size = cw.context_window_size or 200000
  local pct = used / size * 100
  local sys = math.min(baseline(d) or 0, used)
  local convo = used - sys
  local free = size - used

  row("Context", (d.model and d.model.display_name or ""), "ClaudeCtxTitle", "ClaudeCtxDim")
  if not matched then
    add(" (newest session — none for this folder)", { { 0, -1, "ClaudeCtxDim" } })
  end
  row(string.format("%d%% used", math.floor(pct + 0.5)), fmt_tokens(used) .. " / " .. fmt_tokens(size), pct_hl(pct), "ClaudeCtxDim")

  -- Usage bar: system (blue) | conversation (orange) | free (grey). Each cell is 3 bytes ("█").
  local cells = width - 2
  local sys_cells = sys > 0 and math.max(1, math.floor(sys / size * cells + 0.5)) or 0
  local convo_cells = convo > 0 and math.max(1, math.floor(convo / size * cells + 0.5)) or 0
  local free_cells = math.max(0, cells - sys_cells - convo_cells)
  local bar = " " .. string.rep("█", sys_cells + convo_cells + free_cells)
  local b1 = 1 + sys_cells * 3
  local b2 = b1 + convo_cells * 3
  add(bar, { { 1, b1, "ClaudeCtxSystem" }, { b1, b2, "ClaudeCtxConvo" }, { b2, #bar, "ClaudeCtxFree" } })
  add("")

  local function cat(label, n, hl)
    local right = string.format("%7s  %5.1f%%", fmt_tokens(n), n / size * 100)
    local left = "■ " .. label
    local text = " " .. left .. string.rep(" ", width - 2 - vim.fn.strdisplaywidth(left) - #right) .. right
    add(text, { { 1, 1 + #"■", hl }, { 1 + #"■", #text - #right, "Normal" }, { #text - #right, #text, "ClaudeCtxDim" } })
  end
  cat("System, tools, skills ~", sys, "ClaudeCtxSystem")
  cat("Conversation ~", convo, "ClaudeCtxConvo")
  cat("Free space", free, "ClaudeCtxFree")
  add("")

  add(" Session", { { 0, -1, "ClaudeCtxTitle" } })
  local c = d.cost or {}
  local proc = session_process(d.session_id)
  if d.session_name then row("  Name", d.session_name, "ClaudeCtxDim", "Normal") end
  if not proc then
    row("  Claude", "not running", "ClaudeCtxDim", "ClaudeCtxDim")
  elseif proc.status == "busy" then
    row("  Claude", "● working", "ClaudeCtxDim", "ClaudeCtxWarn")
  else
    row("  Claude", proc.status or "idle", "ClaudeCtxDim", "ClaudeCtxGood")
  end
  row("  Cost", string.format("$%.2f", c.total_cost_usd or 0), "ClaudeCtxDim", "Normal")
  row("  Duration", fmt_duration(c.total_duration_ms or 0), "ClaudeCtxDim", "Normal")
  local plus, minus = "+" .. (c.total_lines_added or 0), "-" .. (c.total_lines_removed or 0)
  row("  Lines changed", plus .. " " .. minus, "ClaudeCtxDim", "Normal")
  local last = lines[#lines]
  table.insert(hls, { #lines - 1, #last - #plus - 1 - #minus, #last - #minus - 1, "ClaudeCtxGood" })
  table.insert(hls, { #lines - 1, #last - #minus, #last, "ClaudeCtxBad" })
  local pc = d.prompt_cache
  if pc then
    local warm = pc.warm and "warm" or "cold"
    row("  Prompt cache", string.format("%s · %d%% hits", warm, math.floor((pc.hit_ratio or 0) * 100 + 0.5)),
      "ClaudeCtxDim", pc.warm and "ClaudeCtxGood" or "ClaudeCtxWarn")
  end

  local scan = d.transcript_path and scan_tasks(d.transcript_path) or { list = {}, files = {} }
  local tasks = scan.list
  if #tasks > 0 then
    local running, finished = {}, {}
    for _, t in ipairs(tasks) do
      -- Background tasks die with their Claude process, which doesn't record a status for them.
      local status = (t.status == "running" and not proc) and "ended" or t.status
      table.insert(status == "running" and running or finished, { t = t, status = status })
    end
    add("")
    row("Background tasks", #running > 0 and (#running .. " running") or "none running",
      "ClaudeCtxTitle", #running > 0 and "ClaudeCtxWarn" or "ClaudeCtxDim")
    local shown = {}
    for _, t in ipairs(running) do table.insert(shown, t) end
    for i = #finished, math.max(1, #finished - 2), -1 do table.insert(shown, finished[i]) end -- last 3 finished
    for _, item in ipairs(shown) do
      local t, status = item.t, item.status
      local icon, hl, right
      if status == "running" then
        icon, hl, right = "●", "ClaudeCtxWarn", t.started and fmt_elapsed(os.time() - t.started) or ""
      elseif status == "completed" then
        icon, hl, right = "✓", "ClaudeCtxGood", "done"
      elseif status == "stopped" or status == "ended" then
        icon, hl, right = "■", "ClaudeCtxDim", status
      else
        icon, hl, right = "✗", "ClaudeCtxBad", status
      end
      local tag = t.kind == "agent" and "agent: " or ""
      local max = width - 7 - #right
      local label = (tag .. t.desc):gsub("%s+", " ")
      if vim.fn.strdisplaywidth(label) > max then
        label = vim.fn.strcharpart(label, 0, max - 1) .. "…"
      end
      local left = icon .. " " .. label
      local pad = width - 4 - vim.fn.strdisplaywidth(left) - #right
      local text = "   " .. left .. string.rep(" ", math.max(1, pad)) .. right
      add(text, {
        { 3, 3 + #icon, hl },
        { #text - #right, #text, status == "running" and "ClaudeCtxDim" or hl },
      })
    end
  end

  -- Files Claude touched, most recent first.
  local files = vim.tbl_values(scan.files)
  if #files > 0 then
    table.sort(files, function(a, b) return a.last > b.last end)
    local max_files = 8
    add("")
    row("Files changed", #files > max_files and (#files .. " · newest " .. max_files) or tostring(#files),
      "ClaudeCtxTitle", "ClaudeCtxDim")
    local root = (d.workspace and d.workspace.project_dir or d.cwd or "") .. "/"
    for i = 1, math.min(#files, max_files) do
      local fe = files[i]
      local rel = fe.path:sub(1, #root) == root and fe.path:sub(#root + 1) or vim.fn.fnamemodify(fe.path, ":~")
      local right = (fe.created and "new " or "") .. "×" .. fe.edits
      local max = width - 6 - vim.fn.strdisplaywidth(right)
      if vim.fn.strdisplaywidth(rel) > max then
        rel = "…" .. vim.fn.strcharpart(rel, vim.fn.strchars(rel) - max + 1)
      end
      local pad = width - 4 - vim.fn.strdisplaywidth(rel) - vim.fn.strdisplaywidth(right)
      local text = "   " .. rel .. string.rep(" ", math.max(1, pad)) .. right
      add(text, {
        { 3, 3 + #rel, "Directory" },
        { #text - #right, #text, fe.created and "ClaudeCtxGood" or "ClaudeCtxDim" },
      })
      line_files[#lines] = fe.path
    end
  end

  local rl = d.rate_limits
  if rl then
    add("")
    add(" Usage limits", { { 0, -1, "ClaudeCtxTitle" } })
    for _, k in ipairs({ { "five_hour", "5-hour" }, { "seven_day", "Weekly" } }) do
      local r = rl[k[1]]
      if r then
        row("  " .. k[2], string.format("%d%%  resets in %s", r.used_percentage or 0, fmt_until(r.resets_at or 0)),
          "ClaudeCtxDim", pct_hl(r.used_percentage or 0))
      end
    end
  end

  add("")
  add(" updated " .. os.date("%H:%M:%S", mtime) .. " · q close · ⏎/click open", { { 0, -1, "ClaudeCtxDim" } })
  return lines, hls, line_files
end

-- Rows the card can use: everything above the command line.
local function screen_rows()
  return vim.o.lines - vim.o.cmdheight
end

-- Where the card goes right now, kept fully on screen and below the buffer tabs (row 0).
-- This doesn't change the stored position, so the card returns to it if the terminal grows back.
local function placement()
  local columns = vim.o.columns
  local w = math.min(width, columns - 2)
  local h = math.max(1, math.min(state.height or state.line_count, state.line_count, screen_rows() - 3))
  local row = math.max(1, math.min(state.row or 1, screen_rows() - h - 2))
  local col = math.max(0, math.min(state.col or columns - w - 3, columns - w - 2))
  return { relative = "editor", anchor = "NW", row = row, col = col, width = w, height = h }
end

local function place()
  if state.win and vim.api.nvim_win_is_valid(state.win) then
    vim.api.nvim_win_set_config(state.win, placement())
  end
end

local function redraw()
  if not (state.buf and vim.api.nvim_buf_is_valid(state.buf)) then return end
  local lines, hls, line_files = render()
  state.line_files = line_files or {}
  state.line_count = #lines
  vim.bo[state.buf].modifiable = true
  vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, lines)
  vim.bo[state.buf].modifiable = false
  vim.api.nvim_buf_clear_namespace(state.buf, ns, 0, -1)
  for _, h in ipairs(hls) do
    local line_len = #lines[h[1] + 1]
    local e = h[3] == -1 and line_len or math.min(h[3], line_len)
    if e > h[2] then
      vim.api.nvim_buf_set_extmark(state.buf, ns, h[1], h[2], { end_col = e, hl_group = h[4] })
    end
  end
  place()
end

local function watch()
  if state.watcher then return end
  vim.fn.mkdir(data_dir, "p")
  state.watcher = vim.uv.new_fs_event()
  state.watcher:start(data_dir, {}, vim.schedule_wrap(function() redraw() end))
  -- Also redraw every 5s so task timers tick and new transcript entries show up.
  state.timer = vim.uv.new_timer()
  state.timer:start(5000, 5000, vim.schedule_wrap(function() redraw() end))
end

local function unwatch()
  if state.watcher then
    state.watcher:stop()
    state.watcher:close()
    state.watcher = nil
  end
  if state.timer then
    state.timer:stop()
    state.timer:close()
    state.timer = nil
  end
end

-- Mouse move / resize. The grab in progress: which edges are held, and where the mouse and the
-- card were when it started.
local drag = nil

local function start_drag(m)
  if m.winid ~= state.win then return nil end
  local c = vim.api.nvim_win_get_config(state.win)
  local y, x = m.screenrow - 1, m.screencol - 1 -- 0-based, like the window config
  local bottom = y == c.row + c.height + 1
  local left, right = x == c.col, x == c.col + c.width + 1
  local move = y == c.row
  if not (move or bottom or left or right) then return nil end -- a click on the contents
  return {
    move = move, bottom = bottom, left = left, right = right,
    y = m.screenrow, x = m.screencol, row = c.row, col = c.col, width = c.width, height = c.height,
  }
end

-- Render only on release: each render re-reads every session file. Until then the text just clips.
local function update_drag(d, m)
  local dy, dx = m.screenrow - d.y, m.screencol - d.x
  if d.move then
    state.row, state.col = d.row + dy, d.col + dx
  else
    if d.bottom then
      local h = math.max(min_height, math.min(d.height + dy, screen_rows() - d.row - 2))
      state.height = h < state.line_count and h or nil
    end
    if d.left or d.right then
      state.row, state.col = d.row, d.col
      if d.right then
        width = math.max(min_width, math.min(d.width + dx, vim.o.columns - d.col - 2))
      else
        width = math.max(min_width, math.min(d.width - dx, d.col + d.width))
        state.col = d.col + d.width - width -- the right edge stays put
      end
    end
  end
  place()
end

-- Returns whether a drag was in progress, so the mouse release is known to be ours.
local function end_drag()
  local d = drag
  if not d then return false end
  drag = nil
  vim.schedule(function()
    if width ~= d.width then redraw() end
  end)
  return true
end

-- Mouse keys are mapped globally because the card usually isn't the focused window. Anything that
-- isn't a grab on the card's border is passed through untouched. Windows can't be changed while
-- an expr mapping runs, hence vim.schedule. Visual mode is left out on purpose: keymaps.lua has
-- its own <LeftRelease> there for copy-on-select.
local function map_mouse(key, handler)
  for _, clicks in ipairs({ "", "2-", "3-", "4-" }) do
    local lhs = "<" .. clicks .. key .. ">"
    vim.keymap.set({ "n", "i", "t" }, lhs, function()
      return handler() and "" or lhs
    end, { expr = true, desc = "Claude panel: drag to move / resize" })
  end
end

map_mouse("LeftMouse", function()
  drag = start_drag(vim.fn.getmousepos())
  return drag ~= nil
end)

map_mouse("LeftDrag", function()
  if not drag then return false end
  local d, m = drag, vim.fn.getmousepos()
  vim.schedule(function() update_drag(d, m) end)
  return true
end)

map_mouse("LeftRelease", end_drag)

function M.close()
  if state.win and vim.api.nvim_win_is_valid(state.win) then
    vim.api.nvim_win_close(state.win, true)
  end
  state.win = nil
  unwatch()
end

function M.open()
  if not (state.buf and vim.api.nvim_buf_is_valid(state.buf)) then
    state.buf = vim.api.nvim_create_buf(false, true)
    vim.bo[state.buf].bufhidden = "hide"
    vim.bo[state.buf].filetype = "claude-context"
    vim.keymap.set("n", "q", M.close, { buffer = state.buf, nowait = true })
    vim.keymap.set("n", "<CR>", M.open_file_under_cursor, { buffer = state.buf, nowait = true })
    -- A plain click on a file row opens it too. (Cmd-click is iTerm's own: it opens the file
    -- in the default app, and nvim never sees it.)
    -- (This takes priority over the global mapping while the card is focused, so it has to end
    -- drags too, or letting go of a border would open whatever file the cursor is on.)
    vim.keymap.set("n", "<LeftRelease>", function()
      if end_drag() then return end
      if state.line_files[vim.api.nvim_win_get_cursor(0)[1]] then M.open_file_under_cursor() end
    end, { buffer = state.buf })
  end
  state.win = vim.api.nvim_open_win(state.buf, false, vim.tbl_extend("force", placement(), {
    style = "minimal",
    border = "rounded",
    title = " Claude ",
    title_pos = "left",
    focusable = true,
    zindex = 40,
  }))
  vim.wo[state.win].winhighlight = "Normal:NormalFloat,FloatBorder:FloatBorder"
  vim.wo[state.win].wrap = false -- narrow or mid-resize, clip the text instead of wrapping it
  redraw()
  watch()
end

-- Enter on a file row: open it in the editor (not the terminal / tree / other floats).
function M.open_file_under_cursor()
  local path = state.line_files[vim.api.nvim_win_get_cursor(0)[1]]
  if not path then return end
  local target
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    local buf = vim.api.nvim_win_get_buf(win)
    if vim.api.nvim_win_get_config(win).relative == "" and vim.bo[buf].buftype == ""
      and vim.bo[buf].filetype ~= "neo-tree" then
      target = win
      break
    end
  end
  if not target then
    vim.cmd("botright vsplit")
    target = vim.api.nvim_get_current_win()
  end
  vim.api.nvim_set_current_win(target)
  vim.cmd.edit(vim.fn.fnameescape(path))
end

-- First press opens the card, second press moves the cursor into it, third closes it.
function M.toggle()
  if not (state.win and vim.api.nvim_win_is_valid(state.win)) then
    M.open()
  elseif vim.api.nvim_get_current_win() ~= state.win then
    vim.api.nvim_set_current_win(state.win)
  else
    M.close()
  end
end

-- When the terminal is resized, keep the card in its corner (or, if dragged, on screen).
vim.api.nvim_create_autocmd("VimResized", {
  group = vim.api.nvim_create_augroup("claude_context_panel", { clear = true }),
  callback = place,
})

vim.api.nvim_create_user_command("ClaudeContext", M.toggle, { desc = "Toggle Claude context panel" })
vim.keymap.set("n", "<leader>ai", M.toggle, { desc = "Claude context / usage panel" })

M.scan_tasks = scan_tasks -- exposed for debugging
M.current_session = current_session -- used by the conversation tab (claude_turns.lua)

return M
