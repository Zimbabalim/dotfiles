-- Leader key = Space (most common modern choice)
vim.g.mapleader = " "
vim.g.maplocalleader = " "

local map = vim.keymap.set

-- ── Essential survival keymaps (coming from nano/no-vim background) ──

-- Save file: Ctrl+S (like WebStorm / every other editor)
map({ "n", "i", "v" }, "<C-s>", "<cmd>w<cr><esc>", { desc = "Save file" })

-- Quit: leader+q
map("n", "<leader>q", "<cmd>q<cr>", { desc = "Quit" })

-- Clear search highlight with Escape
map("n", "<Esc>", "<cmd>nohlsearch<cr>", { desc = "Clear search highlight" })

-- ── Navigation ──

-- Move between splits with Ctrl+hjkl (much easier than Ctrl+W then direction)
map("n", "<C-h>", "<C-w>h", { desc = "Move to left split" })
map("n", "<C-j>", "<C-w>j", { desc = "Move to lower split" })
map("n", "<C-k>", "<C-w>k", { desc = "Move to upper split" })
map("n", "<C-l>", "<C-w>l", { desc = "Move to right split" })

-- Move lines up/down in visual mode (like Alt+Up/Down in WebStorm)
map("v", "J", ":m '>+1<cr>gv=gv", { desc = "Move line down" })
map("v", "K", ":m '<-2<cr>gv=gv", { desc = "Move line up" })

-- Better indenting (stays in visual mode after indent)
map("v", "<", "<gv", { desc = "Indent left" })
map("v", ">", ">gv", { desc = "Indent right" })

-- ── Telescope (fuzzy finding — replaces WebStorm's search everywhere) ──

map("n", "<leader>ff", "<cmd>Telescope find_files<cr>", { desc = "Find files" })
map("n", "<leader>fg", "<cmd>Telescope live_grep<cr>", { desc = "Find in files (grep)" })
map("n", "<leader>fb", "<cmd>Telescope buffers<cr>", { desc = "Find open buffers" })
map("n", "<leader>fh", "<cmd>Telescope help_tags<cr>", { desc = "Search help" })
map("n", "<leader>fr", "<cmd>Telescope oldfiles<cr>", { desc = "Recent files" })
map("n", "<leader>fd", "<cmd>Telescope diagnostics<cr>", { desc = "Find diagnostics" })
map("n", "<leader>fc", "<cmd>Telescope colorscheme enable_preview=true<cr>", { desc = "Colour schemes (live preview)" })

-- Double-tap leader for find files (like double-shift in WebStorm)
map("n", "<leader><leader>", "<cmd>Telescope find_files<cr>", { desc = "Find files" })

-- ── File explorer ──

map("n", "<leader>e", "<cmd>Neotree toggle<cr>", { desc = "Toggle file explorer" })

-- ── Buffers (like tabs in WebStorm) ──

map("n", "<S-l>", "<cmd>bnext<cr>", { desc = "Next buffer" })
map("n", "<S-h>", "<cmd>bprevious<cr>", { desc = "Previous buffer" })
map("n", "<leader>x", "<cmd>bdelete<cr>", { desc = "Close buffer" })

-- ── LSP keymaps (set up when an LSP attaches to a buffer) ──

vim.api.nvim_create_autocmd("LspAttach", {
  callback = function(event)
    local opts = function(desc)
      return { buffer = event.buf, desc = desc }
    end

    map("n", "gd", vim.lsp.buf.definition, opts("Go to definition"))
    map("n", "gr", vim.lsp.buf.references, opts("Find references"))
    map("n", "gi", vim.lsp.buf.implementation, opts("Go to implementation"))
    map("n", "K", vim.lsp.buf.hover, opts("Hover documentation"))
    map("n", "<leader>rn", vim.lsp.buf.rename, opts("Rename symbol"))
    map("n", "<leader>ca", vim.lsp.buf.code_action, opts("Code action"))
    map("n", "<leader>D", vim.lsp.buf.type_definition, opts("Type definition"))
    map("n", "[d", function() vim.diagnostic.jump({ count = -1, float = true }) end, opts("Previous diagnostic"))
    map("n", "]d", function() vim.diagnostic.jump({ count = 1, float = true }) end, opts("Next diagnostic"))
    map("n", "<leader>d", vim.diagnostic.open_float, opts("Line diagnostics"))
  end,
})

-- ── Mouse copy ──
-- Drag with the mouse to select inside one panel; letting go copies it to the Mac clipboard
-- (like iTerm's copy-on-select, but the selection stays within the panel you started in).
-- In the terminal column it then goes straight back to typing.
map("x", "<LeftRelease>", function()
  vim.cmd('normal! "+y')
  if vim.bo.buftype == "terminal" then vim.cmd.startinsert() end
end, { desc = "Copy mouse selection" })

-- Briefly flash whatever was just copied.
vim.api.nvim_create_autocmd("TextYankPost", {
  group = vim.api.nvim_create_augroup("yank_flash", { clear = true }),
  callback = function() vim.hl.on_yank({ timeout = 200 }) end,
})
