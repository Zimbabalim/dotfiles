-- Claude conversation tab: the current Claude Code session, turn by turn.
-- Left: your prompts in order (with how many files / tools each turn used).
-- Right: the whole turn for the one under the cursor: your prompt, Claude's reply, the tools it ran.
-- Reads the session transcript (~/.claude/projects/…/<session>.jsonl) and follows it live.
--
-- <leader>ac opens the tab, or jumps to it; pressed in the tab it goes back to the previous tab.
-- The session is the newest one for nvim's folder (the same one the <leader>ai card shows).
--
-- Keys in the list:
--   Enter  jump into the turn on the right   y  copy Claude's reply
--   q      close the tab
-- In the turn column: q (or Ctrl-h) goes back to the list.

local M = {}

local ns = vim.api.nvim_create_namespace("claude_turns")
local file_tools = { Edit = true, Write = true, MultiEdit = true, NotebookEdit = true }

for name, hl in pairs({
  ClaudeTurnsTitle = { fg = "#e6e6e6", bold = true },
  ClaudeTurnsDim = { fg = "#8a8a8a" },
  ClaudeTurnsTime = { fg = "#7aa2f7" },
  ClaudeTurnsMark = { fg = "#e8743b" },
}) do
  vim.api.nvim_set_hl(0, name, hl)
end

local state = {
  list_buf = nil,
  turn_buf = nil,
  transcript = nil, -- path being shown
  offset = 0, -- bytes of the transcript already read
  partial = "", -- an incomplete last line, finished by the next read
  turns = {},
  line_turn = {}, -- list buffer line -> turn index
  shown = nil, -- turn index on the right
  shown_count = 0, -- how many items that turn had when drawn (redraw when it grows)
  timer = nil,
  ticks = 0,
  prev_tab = nil,
  project = nil,
}

local function decode(str)
  return pcall(vim.json.decode, str, { luanil = { object = true, array = true } })
end

local function local_time(ts)
  local y, mo, d, h, mi, sec = (ts or ""):match("^(%d+)-(%d+)-(%d+)T(%d+):(%d+):(%d+)")
  if not y then return "" end
  local now = os.time()
  local offset = os.time(os.date("*t", now)) - os.time(os.date("!*t", now))
  return os.date("%H:%M", os.time({ year = y, month = mo, day = d, hour = h, min = mi, sec = sec, isdst = false }) + offset)
end

local function text_of(content)
  if type(content) == "string" then return content end
  local parts = {}
  for _, b in ipairs(type(content) == "table" and content or {}) do
    if type(b) == "table" and b.type == "text" and b.text then table.insert(parts, b.text) end
  end
  return table.concat(parts, "\n")
end

local function has_tool_result(content)
  if type(content) ~= "table" then return false end
  for _, b in ipairs(content) do
    if type(b) == "table" and b.type == "tool_result" then return true end
  end
  return false
end

local function tag(text, name)
  return text:match("<" .. name .. ">(.-)</" .. name .. ">")
end

-- One line describing a tool call: "Bash · Run the tests", "Edit · layout.lua".
local function tool_summary(b)
  local input = type(b.input) == "table" and b.input or {}
  local what = input.description or input.file_path or input.notebook_path or input.pattern
    or input.url or input.query or input.prompt or input.command or input.skill or ""
  if type(what) ~= "string" then what = "" end
  if input.file_path or input.notebook_path then what = vim.fs.basename(what) end
  what = what:gsub("%s+", " ")
  if #what > 100 then what = what:sub(1, 100) .. "…" end
  return what ~= "" and (b.name .. " · " .. what) or b.name
end

local function new_turn(kind, time, prompt)
  local t = { kind = kind, time = time, prompt = prompt, items = {}, files = {}, nfiles = 0, ntools = 0 }
  table.insert(state.turns, t)
  return t
end

local function current_turn(time)
  return state.turns[#state.turns] or new_turn("start", time, "")
end

-- Turn one transcript record into turns / items.
local function add_record(r)
  if type(r) ~= "table" or r.isSidechain then return end
  local msg = type(r.message) == "table" and r.message or {}
  local time = local_time(r.timestamp)

  if r.type == "user" then
    local content = msg.content
    if r.isMeta or has_tool_result(content) then return end
    local text = text_of(content)
    if r.isCompactSummary then
      new_turn("summary", time, text)
      return
    end
    local origin = type(r.origin) == "table" and r.origin.kind or nil
    if origin == "task-notification" or text:match("^%s*<task%-notification>") then
      local summary = tag(text, "summary") or "background task update"
      table.insert(current_turn(time).items, { kind = "note", text = summary })
      return
    end
    local stdout = tag(text, "bash%-stdout") or tag(text, "local%-command%-stdout")
    if stdout then
      local err = tag(text, "bash%-stderr")
      if err and err ~= "" then stdout = stdout .. "\n" .. err end
      if stdout ~= "" then table.insert(current_turn(time).items, { kind = "output", text = stdout }) end
      return
    end
    local bash = tag(text, "bash%-input")
    if bash then
      new_turn("bash", time, "! " .. vim.trim(bash))
      return
    end
    local cmd = tag(text, "command%-name")
    if cmd then
      local args = tag(text, "command%-args") or ""
      new_turn("command", time, vim.trim(cmd .. " " .. args))
      return
    end
    text = text:gsub("<system%-reminder>.-</system%-reminder>", "")
    text = vim.trim(text)
    if text ~= "" then new_turn("prompt", time, text) end

  elseif r.type == "assistant" then
    local t = current_turn(time)
    for _, b in ipairs(type(msg.content) == "table" and msg.content or {}) do
      if type(b) == "table" and b.type == "text" and b.text and vim.trim(b.text) ~= "" then
        table.insert(t.items, { kind = "text", text = b.text })
      elseif type(b) == "table" and b.type == "tool_use" then
        table.insert(t.items, { kind = "tool", text = tool_summary(b) })
        t.ntools = t.ntools + 1
        local input = type(b.input) == "table" and b.input or {}
        local path = input.file_path or input.notebook_path
        if file_tools[b.name] and type(path) == "string" and not t.files[path] then
          t.files[path] = true
          t.nfiles = t.nfiles + 1
        end
      end
    end
  end
end

-- Read whatever has been added to the transcript since last time.
local function read_new()
  local path = state.transcript
  if not path then return false end
  local size = vim.fn.getfsize(path)
  if size < 0 or size == state.offset then return false end
  if size < state.offset then -- rewritten: start again
    state.offset, state.partial, state.turns = 0, "", {}
  end
  local f = io.open(path, "r")
  if not f then return false end
  f:seek("set", state.offset)
  local chunk = f:read("*a") or ""
  f:close()
  state.offset = state.offset + #chunk
  local data = state.partial .. chunk
  local last_nl = data:match(".*()\n")
  if not last_nl then
    state.partial = data
    return false
  end
  state.partial = data:sub(last_nl + 1)
  for line in data:sub(1, last_nl - 1):gmatch("[^\n]+") do
    -- Skip the bulky record types early, before decoding them.
    if line:find('"type":"user"', 1, true) or line:find('"type":"assistant"', 1, true) then
      local ok, r = decode(line)
      if ok then add_record(r) end
    end
  end
  return true
end

-- Which transcript to show: the session the context card picked; else the newest transcript
-- for this folder in ~/.claude/projects.
local function find_transcript()
  local ok, cp = pcall(require, "context_panel")
  if ok and cp.current_session then
    local d, _, matched = cp.current_session()
    if d and matched and d.transcript_path and vim.fn.filereadable(d.transcript_path) == 1 then
      return d.transcript_path
    end
  end
  local dir = vim.fn.expand("~/.claude/projects/") .. vim.fn.getcwd():gsub("[^%w]", "-")
  local best, best_mtime
  for _, p in ipairs(vim.fn.glob(dir .. "/*.jsonl", false, true)) do
    local m = vim.fn.getftime(p)
    if not best or m > best_mtime then best, best_mtime = p, m end
  end
  return best
end

local function list_win()
  if not (state.list_buf and vim.api.nvim_buf_is_valid(state.list_buf)) then return nil end
  return vim.fn.win_findbuf(state.list_buf)[1]
end

local function turn_win()
  if not (state.turn_buf and vim.api.nvim_buf_is_valid(state.turn_buf)) then return nil end
  return vim.fn.win_findbuf(state.turn_buf)[1]
end

local function set_lines(buf, lines, hls)
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  for _, h in ipairs(hls or {}) do
    local len = #(lines[h[1] + 1] or "")
    local e = h[3] == -1 and len or math.min(h[3], len)
    if e > h[2] then vim.api.nvim_buf_set_extmark(buf, ns, h[1], h[2], { end_col = e, hl_group = h[4] }) end
  end
end

local function first_line(text)
  local line = (text or ""):gsub("<pasted_content.-</pasted_content>", "[pasted text]")
  line = line:match("^%s*([^\n]*)") or ""
  return line
end

local function draw_list()
  if not (state.list_buf and vim.api.nvim_buf_is_valid(state.list_buf)) then return end
  local win = list_win()
  local width = win and vim.api.nvim_win_get_width(win) or 60
  local lines, hls, line_turn = {}, {}, {}
  local function add(text, spans, turn)
    table.insert(lines, text)
    for _, s in ipairs(spans or {}) do table.insert(hls, { #lines - 1, s[1], s[2], s[3] }) end
    line_turn[#lines] = turn
  end
  local nprompts = 0
  for _, t in ipairs(state.turns) do
    if t.kind ~= "start" and t.kind ~= "summary" then nprompts = nprompts + 1 end
  end
  local title = " Claude · " .. (state.project or "?")
  add(title .. string.format(" · %d turns", nprompts), { { 0, #title, "ClaudeTurnsTitle" }, { #title, -1, "ClaudeTurnsDim" } })
  add("")
  if not state.transcript then
    add(" No Claude Code session found for this folder.", { { 0, -1, "ClaudeTurnsDim" } })
    add(" Start `claude` here (e.g. in the terminal column).", { { 0, -1, "ClaudeTurnsDim" } })
  end
  for i, t in ipairs(state.turns) do
    if t.kind == "summary" then
      add(" ⋯ earlier conversation summarized", { { 0, -1, "ClaudeTurnsDim" } }, i)
    elseif t.kind ~= "start" or #t.items > 0 then
      local prefix = " ▸ " .. t.time .. " "
      local text = t.kind == "start" and "(session start)" or first_line(t.prompt)
      local max = width - vim.fn.strdisplaywidth(prefix) - 1
      if vim.fn.strdisplaywidth(text) > max then
        text = vim.fn.strcharpart(text, 0, math.max(max - 1, 1)) .. "…"
      end
      add(prefix .. text, { { 0, 4, "ClaudeTurnsMark" }, { 4, #prefix, "ClaudeTurnsTime" } }, i)
      local bits = {}
      if t.nfiles > 0 then table.insert(bits, ("✎ %d file%s"):format(t.nfiles, t.nfiles == 1 and "" or "s")) end
      if t.ntools > 0 then table.insert(bits, ("⚙ %d tool%s"):format(t.ntools, t.ntools == 1 and "" or "s")) end
      if #bits > 0 then add("         " .. table.concat(bits, " · "), { { 0, -1, "ClaudeTurnsDim" } }, i) end
    end
  end
  add("")
  add(" ⏎ read turn · y copy reply · q close", { { 0, -1, "ClaudeTurnsDim" } })
  set_lines(state.list_buf, lines, hls)
  state.line_turn = line_turn
end

-- The whole turn as markdown: prompt, Claude's text, tool calls as quoted lines.
local function draw_turn(i)
  if not (state.turn_buf and vim.api.nvim_buf_is_valid(state.turn_buf)) then return end
  local t = state.turns[i]
  if not t then
    set_lines(state.turn_buf, { "Move to a turn to read it." })
    state.shown, state.shown_count = nil, 0
    return
  end
  local lines = {}
  local function add_text(text)
    for _, l in ipairs(vim.split(text, "\n")) do table.insert(lines, l) end
  end
  if t.kind == "summary" then
    table.insert(lines, "## Summary of the earlier conversation")
    table.insert(lines, "")
    add_text(t.prompt)
  else
    if t.kind ~= "start" then
      table.insert(lines, "## You · " .. t.time)
      table.insert(lines, "")
      if t.kind == "bash" or t.kind == "command" then
        table.insert(lines, "`" .. t.prompt .. "`")
      else
        add_text(t.prompt)
      end
      table.insert(lines, "")
    end
    local claude_started = false
    local in_tools = false
    for _, item in ipairs(t.items) do
      if item.kind == "output" then
        table.insert(lines, "```")
        add_text(vim.trim(item.text))
        table.insert(lines, "```")
        table.insert(lines, "")
      else
        if not claude_started then
          table.insert(lines, "## Claude")
          table.insert(lines, "")
          claude_started = true
        end
        if item.kind == "tool" or item.kind == "note" then
          table.insert(lines, (item.kind == "tool" and "> ⚙ " or "> ⏰ ") .. item.text)
          in_tools = true
        else
          if in_tools then table.insert(lines, "") end
          in_tools = false
          add_text(vim.trim(item.text))
          table.insert(lines, "")
        end
      end
    end
    if #t.items == 0 then table.insert(lines, "_(no reply yet)_") end
  end
  while #lines > 0 and lines[#lines] == "" do table.remove(lines) end
  local same = state.shown == i
  set_lines(state.turn_buf, lines)
  state.shown, state.shown_count = i, #t.items
  local win = turn_win()
  if win and not same then vim.api.nvim_win_set_cursor(win, { 1, 0 }) end
end

local function cursor_turn()
  local win = list_win()
  return win and state.line_turn[vim.api.nvim_win_get_cursor(win)[1]] or nil
end

local function last_turn_line()
  for l = #vim.api.nvim_buf_get_lines(state.list_buf, 0, -1, false), 1, -1 do
    if state.line_turn[l] == #state.turns then
      -- the turn's first line (the second is its file/tool count)
      while l > 1 and state.line_turn[l - 1] == #state.turns do l = l - 1 end
      return l
    end
  end
end

-- New lines in the transcript, or a new session: redraw, keeping up with the latest turn
-- if that's where the cursor was.
local function update(force_session)
  if force_session or state.ticks % 5 == 0 then
    local t = find_transcript()
    if t ~= state.transcript then
      state.transcript, state.offset, state.partial, state.turns = t, 0, "", {}
      state.shown = nil
    end
  end
  state.ticks = state.ticks + 1
  local before = #state.turns
  local was_on_last = before == 0 or cursor_turn() == before
  if not read_new() and not force_session then return end
  draw_list()
  local win = list_win()
  if win and was_on_last and #state.turns > 0 then
    local l = last_turn_line()
    if l then vim.api.nvim_win_set_cursor(win, { l, 0 }) end
  end
  local i = cursor_turn()
  if i and (i ~= state.shown or #state.turns[i].items ~= state.shown_count) then draw_turn(i) end
end

-- The turn column, to the right of the list (made again if it was closed).
local function open_turn_win()
  local twin = turn_win()
  if twin then return twin end
  local win = list_win()
  if not win then return nil end
  vim.api.nvim_set_current_win(win)
  vim.cmd("rightbelow vsplit")
  twin = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(twin, state.turn_buf)
  for opt, val in pairs({ number = false, relativenumber = false, signcolumn = "no", wrap = true,
    linebreak = true, breakindent = true, conceallevel = 2 }) do
    vim.wo[twin][opt] = val
  end
  vim.api.nvim_win_set_width(win, math.max(50, math.floor(vim.o.columns * 0.4)))
  vim.api.nvim_set_current_win(win)
  return twin
end

local function ensure_bufs()
  if not (state.list_buf and vim.api.nvim_buf_is_valid(state.list_buf)) then
    state.list_buf = vim.api.nvim_create_buf(false, true)
    vim.bo[state.list_buf].bufhidden = "hide"
    vim.bo[state.list_buf].filetype = "claude-turns"
    vim.api.nvim_buf_set_name(state.list_buf, "claude://turns")
    local map = function(lhs, fn) vim.keymap.set("n", lhs, fn, { buffer = state.list_buf, nowait = true }) end
    map("q", function() M.close() end)
    map("<CR>", function()
      local i = cursor_turn()
      if not i then return end
      local twin = open_turn_win()
      draw_turn(i)
      if twin then vim.api.nvim_set_current_win(twin) end
    end)
    map("y", function()
      local t = state.turns[cursor_turn() or 0]
      if not t then return end
      local parts = {}
      for _, item in ipairs(t.items) do
        if item.kind == "text" then table.insert(parts, vim.trim(item.text)) end
      end
      vim.fn.setreg("+", table.concat(parts, "\n\n"))
      vim.notify("Copied Claude's reply (" .. #parts .. " part" .. (#parts == 1 and "" or "s") .. ")")
    end)
    vim.api.nvim_create_autocmd("CursorMoved", {
      buffer = state.list_buf,
      callback = function()
        local i = cursor_turn()
        if i and i ~= state.shown then draw_turn(i) end
      end,
    })
  end
  if not (state.turn_buf and vim.api.nvim_buf_is_valid(state.turn_buf)) then
    state.turn_buf = vim.api.nvim_create_buf(false, true)
    vim.bo[state.turn_buf].bufhidden = "hide"
    vim.api.nvim_buf_set_name(state.turn_buf, "claude://turn")
    vim.bo[state.turn_buf].filetype = "markdown"
    vim.bo[state.turn_buf].modifiable = false
    vim.keymap.set("n", "q", function()
      if list_win() then vim.api.nvim_set_current_win(list_win()) end
    end, { buffer = state.turn_buf, nowait = true })
  end
end

function M.open()
  local win = list_win()
  if win then
    state.prev_tab = vim.api.nvim_get_current_tabpage()
    vim.api.nvim_set_current_win(win)
    return
  end
  ensure_bufs()
  state.project = vim.fs.basename(vim.fn.getcwd())
  state.prev_tab = vim.api.nvim_get_current_tabpage()
  vim.cmd("tabnew")
  local scratch = vim.api.nvim_get_current_buf()
  win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(win, state.list_buf)
  pcall(vim.api.nvim_buf_delete, scratch, { force = true })
  for opt, val in pairs({ number = false, relativenumber = false, signcolumn = "no", wrap = false, cursorline = true }) do
    vim.wo[win][opt] = val
  end
  open_turn_win()
  -- Start from scratch each time the tab opens (cheap: the read skips the bulky records).
  state.transcript, state.offset, state.partial, state.turns, state.shown = nil, 0, "", {}, nil
  state.ticks = 0
  update(true)
  draw_list()
  if not cursor_turn() then draw_turn(nil) end
  if not state.timer then
    state.timer = vim.uv.new_timer()
    state.timer:start(1000, 1000, vim.schedule_wrap(function()
      if list_win() then update(false) end
    end))
  end
end

function M.close()
  local win = list_win() or turn_win()
  if win then
    local tab = vim.api.nvim_win_get_tabpage(win)
    if #vim.api.nvim_list_tabpages() > 1 then
      vim.cmd.tabclose(vim.api.nvim_tabpage_get_number(tab))
    end
    if state.prev_tab and vim.api.nvim_tabpage_is_valid(state.prev_tab) then
      vim.api.nvim_set_current_tabpage(state.prev_tab)
    end
  end
  if state.timer then
    state.timer:stop()
    state.timer:close()
    state.timer = nil
  end
end

-- In the tab: go back to where you were. Anywhere else: open or jump to the tab.
function M.toggle()
  local win = list_win() or turn_win()
  if win and vim.api.nvim_win_get_tabpage(win) == vim.api.nvim_get_current_tabpage() then
    if state.prev_tab and vim.api.nvim_tabpage_is_valid(state.prev_tab) and state.prev_tab ~= vim.api.nvim_get_current_tabpage() then
      vim.api.nvim_set_current_tabpage(state.prev_tab)
    else
      vim.cmd("tabprevious")
    end
  else
    M.open()
  end
end

local group = vim.api.nvim_create_augroup("claude_turns", { clear = true })
vim.api.nvim_create_autocmd("TabClosed", {
  group = group,
  callback = function()
    if state.timer and not list_win() then M.close() end
  end,
})
vim.api.nvim_create_autocmd("VimResized", { group = group, callback = function() draw_list() end })

vim.api.nvim_create_user_command("ClaudeTurns", M.toggle, { desc = "Claude conversation tab" })
vim.keymap.set("n", "<leader>ac", M.toggle, { desc = "Claude conversation (turns)" })

M._state = state -- for debugging

return M
