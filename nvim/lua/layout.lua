-- Default startup layout, only when nvim is opened on a folder (`nvim .`, `nvim ~/dev/x`)
-- or with no arguments. Opening a single file (`nvim foo.ts`) stays plain.
--   tab 1: terminal | file tree | editor
--   tab 2: git changes explorer (only if the folder is a git repo with uncommitted changes)
-- If the repo was clean at startup, the git tab opens the first time you save a change.
-- Closing the git tab stops it reopening for the rest of the session (<leader>gd still works).

local group = vim.api.nvim_create_augroup("default_layout", { clear = true })
local layout_active = false
local changes_tab_opened = false

local function changes_tab_exists()
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if vim.bo[vim.api.nvim_win_get_buf(win)].filetype == "codediff-explorer" then
      return true
    end
  end
  return false
end

-- Open the git changes tab in the background, keeping the cursor where it was.
local function open_changes_tab()
  if changes_tab_opened or changes_tab_exists() then
    return
  end
  local changes = vim.fn.systemlist("git status --porcelain 2>/dev/null")
  if vim.v.shell_error ~= 0 or #changes == 0 then
    return
  end
  changes_tab_opened = true
  local tab, win = vim.api.nvim_get_current_tabpage(), vim.api.nvim_get_current_win()
  local ntabs = #vim.api.nvim_list_tabpages()
  vim.cmd("CodeDiff")
  -- CodeDiff opens its tab asynchronously; switch back once it appears.
  vim.wait(3000, function() return #vim.api.nvim_list_tabpages() > ntabs end, 50)
  if vim.api.nvim_tabpage_is_valid(tab) then
    vim.api.nvim_set_current_tabpage(tab)
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_set_current_win(win)
    end
  end
end

vim.api.nvim_create_autocmd("VimEnter", {
  group = group,
  nested = true,
  callback = function()
    local argc = vim.fn.argc()
    local dir = argc == 1 and vim.fn.argv(0) or nil
    if argc > 1 or (dir and vim.fn.isdirectory(dir) == 0) then
      return
    end
    layout_active = true

    if dir then
      vim.cmd.cd(vim.fn.fnameescape(dir))
      -- Replace the directory buffer with an empty one so the editor area isn't a file listing.
      local dirbuf = vim.api.nvim_get_current_buf()
      vim.cmd.enew()
      pcall(vim.api.nvim_buf_delete, dirbuf, { force = true })
    end

    local editor = vim.api.nvim_get_current_win()
    vim.cmd("Neotree show left")
    vim.cmd("TermToggle") -- opens at the far left, in front of the tree
    -- Leave the cursor in the editor, not the tree or terminal.
    vim.cmd("stopinsert")
    vim.api.nvim_set_current_win(editor)

    open_changes_tab()
  end,
})

vim.api.nvim_create_autocmd("BufWritePost", {
  group = group,
  callback = function()
    if layout_active and vim.bo.buftype == "" then
      vim.schedule(open_changes_tab)
    end
  end,
})
