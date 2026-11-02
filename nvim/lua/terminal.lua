-- Terminal panel: a full-height column on the left (run `claude`, `team architect`, etc. here).
-- <leader>t toggles it. The shell keeps running while hidden, so reopening shows the same session.
-- Inside the terminal: Ctrl-Space returns to Normal mode (then <leader>t hides it, Ctrl-l moves right).
-- (Not Esc: Claude Code uses Esc to interrupt and Esc Esc to rewind, so Esc goes straight through.)

-- Width: this fraction of the screen, but never narrower than min_width columns.
local width_fraction = 0.4
local min_width = 80
local term_buf = nil

local function term_win()
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if vim.api.nvim_win_get_buf(win) == term_buf then
      return win
    end
  end
end

local M = {}

local function term_width()
  return math.max(min_width, math.floor(vim.o.columns * width_fraction))
end

-- Put the terminal back at the far left (used when another panel, e.g. the file tree, opens left of it).
function M.pin_left()
  local win = term_buf and vim.api.nvim_buf_is_valid(term_buf) and term_win()
  if not win then return false end
  vim.fn.win_execute(win, "wincmd H")
  vim.api.nvim_win_set_width(win, term_width())
  return true
end

local function toggle()
  local win = term_buf and vim.api.nvim_buf_is_valid(term_buf) and term_win()
  if win then
    vim.api.nvim_win_hide(win)
    return
  end

  vim.cmd("topleft " .. term_width() .. "vsplit")
  if term_buf and vim.api.nvim_buf_is_valid(term_buf) then
    vim.api.nvim_win_set_buf(0, term_buf)
  else
    vim.cmd.terminal()
    term_buf = vim.api.nvim_get_current_buf()
    vim.bo[term_buf].buflisted = false -- keep it out of the buffer tabs
  end
  vim.wo.number = false
  vim.wo.relativenumber = false
  vim.wo.signcolumn = "no"
  vim.wo.winfixwidth = true
  vim.cmd.startinsert()
end

vim.api.nvim_create_user_command("TermToggle", toggle, { desc = "Toggle terminal panel" })
vim.keymap.set("n", "<leader>t", toggle, { desc = "Toggle terminal panel" })
vim.keymap.set("t", "<C-Space>", [[<C-\><C-n>]], { desc = "Terminal: back to Normal mode" })

-- When you click or move back into the terminal, start typing straight away.
vim.api.nvim_create_autocmd("BufEnter", {
  group = vim.api.nvim_create_augroup("terminal_panel", { clear = true }),
  callback = function(args)
    if args.buf == term_buf then
      vim.cmd.startinsert()
    end
  end,
})

return M
