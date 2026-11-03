-- Bootstrap lazy.nvim plugin manager
local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not vim.uv.fs_stat(lazypath) then
  vim.fn.system({
    "git", "clone", "--filter=blob:none",
    "https://github.com/folke/lazy.nvim.git",
    "--branch=stable",
    lazypath,
  })
end
vim.opt.rtp:prepend(lazypath)

-- Load core config
require("options")
require("keymaps")

-- Load plugins
require("lazy").setup("plugins", {
  change_detection = { notify = false },
})

-- Default startup layout (file tree + git changes tab)
require("layout")

-- <leader>p / :Panels menu
require("panels")

-- <leader>t bottom terminal panel
require("terminal")

-- <leader>ai Claude context / usage card
require("context_panel")

-- Quick Look previews (<leader>o, P in the file tree)
require("quicklook")

-- <leader>b beads issues panel
require("beads")

-- ask before quitting while the terminal is running
require("quit_guard")

-- <leader>ac Claude conversation tab (turns of the current session)
require("claude_turns")
