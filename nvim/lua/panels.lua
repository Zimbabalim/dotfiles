-- Panel menu: <leader>p opens a searchable list of panels/views; Enter opens the selected one.

local panels = {
  { "File tree", "<leader>e", "Neotree toggle" },
  { "Claude context & usage", "<leader>ai", "ClaudeContext" },
  { "Terminal", "<leader>t", "TermToggle" },
  { "Beads issues (tab)", "<leader>b", "Beads" },
  { "Git changes", "<leader>gd", "CodeDiff" },
  { "Git: this file vs HEAD", "<leader>gD", "CodeDiff file HEAD" },
  { "Git: file history", "<leader>gh", "CodeDiff history %" },
  { "Git: repo history", "<leader>gH", "CodeDiff history" },
  { "Find files", "<leader><leader>", "Telescope find_files" },
  { "Find in files (grep)", "<leader>fg", "Telescope live_grep" },
  { "Recent files", "<leader>fr", "Telescope oldfiles" },
  { "Open buffers", "<leader>fb", "Telescope buffers" },
  { "Diagnostics (errors/warnings)", "<leader>fd", "Telescope diagnostics" },
  { "Help", "<leader>fh", "Telescope help_tags" },
  { "Colour schemes (live preview)", "<leader>fc", "Telescope colorscheme enable_preview=true" },
  { "Quick Look current file", "<leader>o", "lua require('quicklook').preview(vim.fn.expand('%:p'))" },
  { "Plugins (lazy.nvim)", "", "Lazy" },
  { "Language servers & tools (Mason)", "", "Mason" },
}

local function open_menu()
  local pickers = require("telescope.pickers")
  local finders = require("telescope.finders")
  local conf = require("telescope.config").values
  local actions = require("telescope.actions")
  local action_state = require("telescope.actions.state")

  pickers.new(require("telescope.themes").get_dropdown({ previewer = false }), {
    prompt_title = "Panels",
    finder = finders.new_table({
      results = panels,
      entry_maker = function(p)
        local label = p[2] ~= "" and string.format("%-34s %s", p[1], p[2]) or p[1]
        return { value = p, display = label, ordinal = p[1] }
      end,
    }),
    sorter = conf.generic_sorter({}),
    attach_mappings = function(bufnr)
      actions.select_default:replace(function()
        local entry = action_state.get_selected_entry()
        actions.close(bufnr)
        if entry then
          vim.cmd(entry.value[3])
        end
      end)
      return true
    end,
  }):find()
end

vim.api.nvim_create_user_command("Panels", open_menu, { desc = "Pick a panel to open" })
vim.keymap.set("n", "<leader>p", open_menu, { desc = "Panels menu" })
