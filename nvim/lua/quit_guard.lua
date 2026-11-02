-- Ask before quitting nvim while the terminal panel has something running in it (e.g. Claude).
-- nvim itself doesn't stop you: :qa just kills the terminal and whatever is in it.
-- Covers :q (when it would close the last window), :qa / :qall / :wqa / :xa.
-- Add ! to skip the question (:qa!, :q!), as usual.
-- (Closing the iTerm tab is iTerm's side: Profiles → Session → Prompt before closing.)

local function running_terminals()
  local n = 0
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(buf) and vim.bo[buf].buftype == "terminal" then
      local chan = vim.bo[buf].channel
      if chan > 0 and vim.fn.jobwait({ chan }, 0)[1] == -1 then n = n + 1 end
    end
  end
  return n
end

-- Would :q in the current window exit nvim? (neo-tree closes itself when it's the last window left.)
local function q_exits()
  if #vim.api.nvim_list_tabpages() > 1 then return false end
  local others = 0
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    local buf = vim.api.nvim_win_get_buf(win)
    if win ~= vim.api.nvim_get_current_win() and vim.api.nvim_win_get_config(win).relative == ""
        and vim.bo[buf].filetype ~= "neo-tree" then
      others = others + 1
    end
  end
  return others == 0
end

local function ok_to_quit()
  local n = running_terminals()
  if n == 0 then return true end
  local msg = n == 1 and "The terminal is still running. Quit nvim anyway?"
    or ("%d terminals are still running. Quit nvim anyway?"):format(n)
  return vim.fn.confirm(msg, "&Quit\n&Cancel", 2) == 1
end

-- cmd: the real command to run once it's OK; whole: true if it always exits nvim (not :q).
local function guarded(cmd, whole)
  return function(opts)
    local exits = whole or q_exits()
    if not opts.bang and exits and not ok_to_quit() then return end
    -- "confirm" still asks about unsaved files, as plain :q / :qa would refuse them.
    vim.cmd((opts.bang and "" or "confirm ") .. cmd .. (opts.bang and "!" or ""))
  end
end

local commands = {
  { "q", "GuardedQ", "quit", false },
  { "quit", "GuardedQ", "quit", false },
  { "qa", "GuardedQa", "qall", true },
  { "qall", "GuardedQa", "qall", true },
  { "quitall", "GuardedQa", "qall", true },
  { "wqa", "GuardedWqa", "wqall", true },
  { "wqall", "GuardedWqa", "wqall", true },
  { "xa", "GuardedWqa", "wqall", true },
  { "xall", "GuardedWqa", "wqall", true },
}

for _, c in ipairs(commands) do
  local typed, name, real, whole = c[1], c[2], c[3], c[4]
  pcall(vim.api.nvim_create_user_command, name, guarded(real, whole), { bang = true })
  -- Only rewrite when it's the whole command typed at the : prompt, not part of something else.
  vim.keymap.set("ca", typed, function()
    return (vim.fn.getcmdtype() == ":" and vim.fn.getcmdline() == typed) and name or typed
  end, { expr = true })
end
