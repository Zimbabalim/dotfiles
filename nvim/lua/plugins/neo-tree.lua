return {
  "nvim-neo-tree/neo-tree.nvim",
  branch = "v3.x",
  dependencies = {
    "nvim-lua/plenary.nvim",
    "nvim-tree/nvim-web-devicons",
    "MunifTanjim/nui.nvim",
  },
  config = function()
    require("neo-tree").setup({
      close_if_last_window = true,
      event_handlers = {
        -- Panel order is: terminal | file tree | editor | beads.
        -- The tree opens at the far left, so if the terminal is open, move the terminal back in front of it.
        {
          event = "neo_tree_window_after_open",
          handler = function(args)
            if require("terminal").pin_left() and args.winid and vim.api.nvim_win_is_valid(args.winid) then
              vim.api.nvim_win_set_width(args.winid, 35)
            end
          end,
        },
      },
      filesystem = {
        follow_current_file = { enabled = true },
        filtered_items = {
          hide_dotfiles = false,
          hide_gitignored = false,
          hide_by_name = {
            "node_modules",
            ".git",
          },
        },
      },
      window = {
        width = 35,
        mappings = {
          ["<space>"] = "none", -- don't conflict with leader key
          -- P: macOS Quick Look (images, PDFs, video…) instead of neo-tree's text preview
          ["P"] = function(state)
            local node = state.tree:get_node()
            if node then require("quicklook").preview(node.path or node:get_id()) end
          end,
        },
      },
    })
  end,
}
