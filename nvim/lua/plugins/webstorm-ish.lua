-- WebStorm-style git diff. (Claude runs in the plain terminal panel: <leader>t, see lua/terminal.lua.)

-- Default branch of the current repo (origin/HEAD → "main"/"master"/...), for "diff vs main".
local function default_branch()
  local ref = vim.fn.systemlist("git rev-parse --abbrev-ref origin/HEAD 2>/dev/null")[1]
  if vim.v.shell_error == 0 and ref and ref ~= "" then
    return (ref:gsub("^origin/", ""))
  end
  return "main"
end

return {
  -- VS Code / JetBrains-style side-by-side diff with line + character highlighting,
  -- a changed-files explorer (stage, unstage, restore), file/repo history and merge conflicts.
  {
    "esmuellert/codediff.nvim",
    cmd = "CodeDiff",
    keys = {
      { "<leader>gd", "<cmd>CodeDiff<cr>", desc = "Changes (commit/diff explorer)" },
      { "<leader>gD", "<cmd>CodeDiff file HEAD<cr>", desc = "Diff this file vs HEAD" },
      { "<leader>gm", function() vim.cmd("CodeDiff " .. default_branch() .. "...") end, desc = "Diff branch vs main" },
      { "<leader>gh", "<cmd>CodeDiff history %<cr>", desc = "File history" },
      { "<leader>gH", "<cmd>CodeDiff history<cr>", desc = "Repo history" },
    },
  },

  -- Name the key groups in the which-key popup
  {
    "folke/which-key.nvim",
    opts = {
      spec = {
        { "<leader>a", group = "AI / Claude" },
        { "<leader>g", group = "Git" },
        { "<leader>f", group = "Find" },
      },
    },
  },
}
