-- Configure diagnostics appearance
vim.diagnostic.config({
  virtual_text = true,
  signs = true,
  underline = true,
  update_in_insert = false,
  severity_sort = true,
  float = {
    border = "rounded",
    source = "always",
  },
})

-- 1. Handle the "on_attach" logic globally via Autocommands
vim.api.nvim_create_autocmd('LspAttach', {
  callback = function(args)
    local bufnr = args.buf
    local client = vim.lsp.get_client_by_id(args.data.client_id)

    -- Enable built-in native completion (Neovim 0.12+)
    if client and client:supports_method('textDocument/completion') then
      vim.lsp.completion.enable(true, client.id, bufnr, {
        autotrigger = true,
        convert = function(item)
          return { abbr = item.label:gsub("%b()", "") }
        end,
      })
    end

    -- Global LSP keybindings (work for all LSP-enabled buffers)
    local map = function(mode, lhs, rhs, desc)
      vim.keymap.set(mode, lhs, rhs, { buffer = bufnr, desc = desc })
    end

    map('n', 'K', vim.lsp.buf.hover, 'Hover documentation')
    map('n', 'gd', vim.lsp.buf.definition, 'Go to definition')
    map('n', 'gD', vim.lsp.buf.declaration, 'Go to declaration')
    map('n', 'gi', vim.lsp.buf.implementation, 'Go to implementation')
    map('n', 'gr', vim.lsp.buf.references, 'Show references')
    map('n', 'gs', vim.lsp.buf.signature_help, 'Signature help')
    map('n', '<leader>rn', vim.lsp.buf.rename, 'Rename symbol')
    map('n', '<leader>ca', vim.lsp.buf.code_action, 'Code action')
    map('n', '<leader>fm', function() vim.lsp.buf.format({ async = true }) end, 'Format buffer')

    -- Diagnostics
    map('n', '[d', vim.diagnostic.goto_prev, 'Previous diagnostic')
    map('n', ']d', vim.diagnostic.goto_next, 'Next diagnostic')
    map('n', '<leader>d', vim.diagnostic.open_float, 'Show diagnostic')
    map('n', '<leader>dl', vim.diagnostic.setloclist, 'Diagnostics to loclist')
  end,
})

-- Enable LSP servers (native Neovim 0.12+ approach)
local servers = {
  clangd = {
    cmd = {"clangd", "--background-index"},
    settings = {
      fallbackFlags = {"-std=c++17"},
    }
  },
  pyright = {},
  ts_ls = {
    filetypes = {
      "javascript",
      "javascriptreact",
      "typescript",
      "typescriptreact",
    },
    root_markers = { "package.json", "tsconfig.json", "jsconfig.json", ".git" },
    init_options = {
      hostInfo = "neovim",
    },
  },
  html = {
    filetypes = { "html" },
    root_markers = { "package.json", "tsconfig.json", "jsconfig.json", ".git" },
  },
  cssls = {
    filetypes = { "css", "scss", "less" },
    root_markers = { "package.json", "tsconfig.json", "jsconfig.json", ".git" },
  },
  jsonls = {
    root_markers = { "package.json", "tsconfig.json", "jsconfig.json", ".git" },
  },
  texlab = {
    cmd = { "texlab" },
    filetypes = { "tex", "plaintex", "bib" },
    root_markers = { ".latexmkrc", "latexmkrc", "Tectonic.toml", ".git" },
    settings = {
      texlab = {
        build = {
          executable = "latexmk",
          args = { "-lualatex", "-interaction=nonstopmode", "-synctex=1", "%f" },
          onSave = false,
        },
      },
    },
  },
  lua_ls = {
    settings = {
      Lua = {
        diagnostics = { globals = { 'vim' } }
      }
    }
  },
  tinymist = {
    settings = {
      exportPdf = "onType",
      outputPath = "$root/target/$dir/$name",
    }
  },
}

-- Batch enable the servers using native Neovim 0.12 approach
for server, config in pairs(servers) do
  vim.lsp.config(server, config)
end
vim.lsp.enable(vim.tbl_keys(servers))

-- Typst-specific keybindings (only active for .typ files)
vim.api.nvim_create_autocmd('FileType', {
  pattern = 'typst',
  callback = function()
    vim.keymap.set('n', '<leader>tp', '<cmd>TypstPreview<cr>', { buffer = true, desc = "Typst: Toggle preview" })
    vim.keymap.set('n', '<leader>tb', '<cmd>!typst compile %<cr>', { buffer = true, desc = "Typst: Build to PDF" })
  end,
})
