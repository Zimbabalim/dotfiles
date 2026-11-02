-- macOS Quick Look for images (and PDFs, video, anything Finder can preview).
--   P in the file tree   → preview the file under the cursor
--   <leader>o            → preview the current file
-- Close the preview with Esc or Space in the Quick Look window.

local M = {}
local current -- the running qlmanage process, so a new preview replaces the old one

function M.preview(path)
  if not path or path == "" then return end
  if vim.fn.filereadable(path) == 0 and vim.fn.isdirectory(path) == 0 then
    vim.notify("Quick Look: no such file: " .. path, vim.log.levels.WARN)
    return
  end
  if current then pcall(function() current:kill(15) end) end
  current = vim.system({ "qlmanage", "-p", path }, { text = true }, function() current = nil end)
end

vim.keymap.set("n", "<leader>o", function() M.preview(vim.fn.expand("%:p")) end,
  { desc = "Quick Look current file" })

return M
