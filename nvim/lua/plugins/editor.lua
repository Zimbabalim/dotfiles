return {
  -- Autopairs (auto-close brackets, quotes, etc.)
  {
    "windwp/nvim-autopairs",
    event = "InsertEnter",
    config = function()
      require("nvim-autopairs").setup()
    end,
  },

  -- Auto-close and rename HTML/JSX tags
  {
    "windwp/nvim-ts-autotag",
    event = "InsertEnter",
    config = function()
      require("nvim-ts-autotag").setup()
    end,
  },

  -- Comment toggling (gcc to toggle line, gc in visual mode)
  {
    "numToStr/Comment.nvim",
    event = { "BufReadPost", "BufNewFile" },
    config = function()
      require("Comment").setup()
    end,
  },

  -- Git signs in the gutter (like WebStorm's gutter indicators)
  {
    "lewis6991/gitsigns.nvim",
    event = { "BufReadPre", "BufNewFile" },
    config = function()
      require("gitsigns").setup({
        signs = {
          add = { text = "+" },
          change = { text = "~" },
          delete = { text = "_" },
          topdelete = { text = "-" },
          changedelete = { text = "~" },
        },
        on_attach = function(bufnr)
          local gs = package.loaded.gitsigns
          local map = vim.keymap.set
          local opts = function(desc)
            return { buffer = bufnr, desc = desc }
          end

          map("n", "]c", gs.next_hunk, opts("Next git change"))
          map("n", "[c", gs.prev_hunk, opts("Previous git change"))
          map("n", "<leader>gp", gs.preview_hunk, opts("Preview git change"))
          map("n", "<leader>gb", gs.blame_line, opts("Git blame line"))
        end,
      })
    end,
  },

  -- Indent guides (subtle vertical lines showing indent level)
  {
    "lukas-reineke/indent-blankline.nvim",
    main = "ibl",
    event = { "BufReadPost", "BufNewFile" },
    config = function()
      require("ibl").setup({
        indent = { char = "│" },
        scope = { enabled = true },
      })
    end,
  },

  -- Surround (quickly add/change/delete surrounding chars)
  -- ys" to surround with quotes, cs"' to change " to ', ds" to delete quotes
  {
    "kylechui/nvim-surround",
    event = { "BufReadPost", "BufNewFile" },
    config = function()
      require("nvim-surround").setup()
    end,
  },

  -- Which-key: shows available keybindings as you type (great for learning)
  {
    "folke/which-key.nvim",
    event = "VeryLazy",
    opts = {
      delay = 500,
    },
  },

  -- Buffer tabs at the top (like browser/editor tabs)
  {
    "akinsho/bufferline.nvim",
    version = "*",
    dependencies = { "nvim-tree/nvim-web-devicons" },
    config = function()
      require("bufferline").setup({
        options = {
          diagnostics = "nvim_lsp",
          offsets = {
            { filetype = "neo-tree", text = "Explorer", text_align = "center" },
          },
          show_close_icon = false,
        },
      })
    end,
  },
}
