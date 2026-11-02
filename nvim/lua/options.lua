local opt = vim.opt

-- Line numbers
opt.number = true
opt.relativenumber = true

-- Indentation (2 spaces — standard for JS/TS/CSS/HTML)
opt.tabstop = 2
opt.shiftwidth = 2
opt.softtabstop = 2
opt.expandtab = true
opt.smartindent = true

-- Search
opt.ignorecase = true
opt.smartcase = true
opt.hlsearch = true
opt.incsearch = true

-- Appearance
opt.termguicolors = true
opt.signcolumn = "yes"
opt.cursorline = true
opt.scrolloff = 8
opt.sidescrolloff = 8
opt.wrap = false

-- Splits (match WebStorm behaviour — new splits go right/below)
opt.splitright = true
opt.splitbelow = true

-- System clipboard (yank/paste works with Cmd+C/Cmd+V)
opt.clipboard = "unnamedplus"

-- Persistent undo (survives closing the file)
opt.undofile = true

-- Faster updates (for git signs, LSP diagnostics)
opt.updatetime = 250
opt.timeoutlen = 300

-- Don't show mode in command line (lualine handles it)
opt.showmode = false

-- Better completion experience
opt.completeopt = { "menu", "menuone", "noselect" }

-- File encoding
opt.fileencoding = "utf-8"

-- Mouse support
opt.mouse = "a"
