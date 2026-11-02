return {
  -- Mason: auto-installs LSP servers, linters, formatters
  {
    "williamboman/mason.nvim",
    build = ":MasonUpdate",
    config = function()
      require("mason").setup()
    end,
  },

  -- Bridge between Mason and lspconfig
  {
    "williamboman/mason-lspconfig.nvim",
    dependencies = { "williamboman/mason.nvim", "neovim/nvim-lspconfig" },
    config = function()
      require("mason-lspconfig").setup({
        ensure_installed = {
          -- Frontend (primary stack)
          "ts_ls",          -- TypeScript/JavaScript
          "eslint",         -- ESLint integration
          "cssls",          -- CSS
          "html",           -- HTML
          "emmet_ls",       -- Emmet abbreviations (div.foo>span -> HTML)
          "jsonls",         -- JSON
          "tailwindcss",    -- Tailwind CSS (if you use it)
          -- Occasional
          "rust_analyzer",  -- Rust
          "omnisharp",      -- C#
          -- Config
          "lua_ls",         -- For editing Neovim config
        },
      })
    end,
  },

  -- LSP config (Neovim 0.11+ native API: vim.lsp.config).
  -- mason-lspconfig automatically calls vim.lsp.enable() for every installed server,
  -- so here we only set shared + per-server settings.
  {
    "neovim/nvim-lspconfig",
    event = { "BufReadPre", "BufNewFile" },
    dependencies = {
      "williamboman/mason-lspconfig.nvim",
      "hrsh7th/cmp-nvim-lsp",
    },
    config = function()
      -- Shared settings for every server
      vim.lsp.config("*", {
        capabilities = require("cmp_nvim_lsp").default_capabilities(),
      })

      -- Emmet
      vim.lsp.config("emmet_ls", {
        filetypes = { "html", "css", "scss", "javascript", "javascriptreact", "typescript", "typescriptreact" },
      })

      -- JSON (with schema support like package.json, tsconfig, etc.)
      vim.lsp.config("jsonls", {
        settings = {
          json = {
            validate = { enable = true },
          },
        },
      })

      -- Rust
      vim.lsp.config("rust_analyzer", {
        settings = {
          ["rust-analyzer"] = {
            checkOnSave = { command = "clippy" },
          },
        },
      })

      -- Lua (for editing this Neovim config)
      vim.lsp.config("lua_ls", {
        settings = {
          Lua = {
            diagnostics = { globals = { "vim" } },
            workspace = { checkThirdParty = false },
          },
        },
      })

      -- Format on save. ESLint gets auto-fix; servers that would fight the
      -- formatter (emmet, tailwind) are skipped.
      local no_format = { emmet_ls = true, tailwindcss = true, eslint = true }
      vim.api.nvim_create_autocmd("LspAttach", {
        callback = function(event)
          local client = vim.lsp.get_client_by_id(event.data.client_id)
          if not client then
            return
          end
          if client.name == "eslint" then
            vim.api.nvim_create_autocmd("BufWritePre", {
              buffer = event.buf,
              command = "LspEslintFixAll",
            })
          elseif not no_format[client.name] and client:supports_method("textDocument/formatting") then
            vim.api.nvim_create_autocmd("BufWritePre", {
              buffer = event.buf,
              callback = function()
                vim.lsp.buf.format({ bufnr = event.buf, id = client.id, timeout_ms = 2000 })
              end,
            })
          end
        end,
      })

      -- Nicer diagnostic icons in the gutter
      vim.diagnostic.config({
        signs = {
          text = {
            [vim.diagnostic.severity.ERROR] = " ",
            [vim.diagnostic.severity.WARN] = " ",
            [vim.diagnostic.severity.HINT] = "󰌵 ",
            [vim.diagnostic.severity.INFO] = " ",
          },
        },
      })
    end,
  },

  -- Autocompletion
  {
    "hrsh7th/nvim-cmp",
    event = "InsertEnter",
    dependencies = {
      "hrsh7th/cmp-nvim-lsp",     -- LSP completions
      "hrsh7th/cmp-buffer",       -- words from current buffer
      "hrsh7th/cmp-path",         -- file paths
      "L3MON4D3/LuaSnip",        -- snippet engine
      "saadparwaiz1/cmp_luasnip", -- snippet completions
      "rafamadriz/friendly-snippets", -- collection of useful snippets
    },
    config = function()
      local cmp = require("cmp")
      local luasnip = require("luasnip")

      -- Load VS Code-style snippets (from friendly-snippets)
      require("luasnip.loaders.from_vscode").lazy_load()

      cmp.setup({
        snippet = {
          expand = function(args)
            luasnip.lsp_expand(args.body)
          end,
        },
        mapping = cmp.mapping.preset.insert({
          ["<C-b>"] = cmp.mapping.scroll_docs(-4),
          ["<C-f>"] = cmp.mapping.scroll_docs(4),
          ["<C-Space>"] = cmp.mapping.complete(),
          ["<C-e>"] = cmp.mapping.abort(),
          ["<CR>"] = cmp.mapping.confirm({ select = true }),
          -- Tab to cycle through completions
          ["<Tab>"] = cmp.mapping(function(fallback)
            if cmp.visible() then
              cmp.select_next_item()
            elseif luasnip.expand_or_jumpable() then
              luasnip.expand_or_jump()
            else
              fallback()
            end
          end, { "i", "s" }),
          ["<S-Tab>"] = cmp.mapping(function(fallback)
            if cmp.visible() then
              cmp.select_prev_item()
            elseif luasnip.jumpable(-1) then
              luasnip.jump(-1)
            else
              fallback()
            end
          end, { "i", "s" }),
        }),
        sources = cmp.config.sources({
          { name = "nvim_lsp" },
          { name = "luasnip" },
          { name = "path" },
        }, {
          { name = "buffer" },
        }),
      })
    end,
  },
}
