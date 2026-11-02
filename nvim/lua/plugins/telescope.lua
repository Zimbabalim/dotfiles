return {
  "nvim-telescope/telescope.nvim",
  branch = "master", -- 0.1.x is unmaintained and breaks with the new nvim-treesitter
  dependencies = {
    "nvim-lua/plenary.nvim",
    {
      "nvim-telescope/telescope-fzf-native.nvim",
      build = "make",
    },
  },
  config = function()
    local telescope = require("telescope")
    telescope.setup({
      defaults = {
        file_ignore_patterns = {
          "node_modules",
          ".git/",
          "dist/",
          "build/",
          "target/",       -- Rust build output
          "bin/obj/",      -- C# build output
          "%.lock",
        },
        layout_config = {
          horizontal = { preview_width = 0.55 },
        },
      },
      pickers = {
        find_files = {
          hidden = true, -- show dotfiles
        },
      },
    })
    telescope.load_extension("fzf")
  end,
}
