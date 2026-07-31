vim.pack.add({
  -- Theme
  { src = "shaunsingh/nord.nvim" },
  { src = "https://github.com/AvengeMedia/base46" },

  -- File navigation
  { src = "stevearc/oil.nvim" },
  { src = "nvim-lua/plenary.nvim" },
  { src = "nvim-telescope/telescope.nvim" },
  {
    src = 'https://github.com/nvim-neo-tree/neo-tree.nvim',
    version = vim.version.range('3')
  },

  -- Syntax and utilities
  { src = "https://github.com/tmux-plugins/vim-tmux" },
  { src = "https://github.com/NvChad/nvim-colorizer.lua" },

  -- dependencies
  "https://github.com/MunifTanjim/nui.nvim",
  "https://github.com/nvim-tree/nvim-web-devicons",
  -- Terminal
  { src = "akinsho/toggleterm.nvim" },

  -- Syntax highlighting
  { src = "nvim-treesitter/nvim-treesitter",                             build = ":TSUpdate" },

  -- LSP (native Neovim 0.12+)
  { src = "neovim/nvim-lspconfig" },

  -- Document editing
  { src = "lervag/vimtex" },
  { src = "chomosuke/typst-preview.nvim" },
  { src = "https://github.com/MeanderingProgrammer/render-markdown.nvim" },
})

----------------------------------------------------------------
-- Theme configuration (AvengeMedia/base46 + DMS / fallback)
----------------------------------------------------------------
local ok_base46, base46 = pcall(require, "base46")
if ok_base46 then
  base46.setup({
    set_background = true,
    term_colors = true,
    transparency = false,
    integrations = {
      defaults = true,
      lsp = true,
      treesitter = true,
      telescope = true,
      nvimtree = true,
      whichkey = true,
    },
  })
  -- Try loading DMS generated theme first (if DMS/Matugen generated colors/dms.lua)
  -- Fallback to builtin base46-nord or nord if dms is not present (e.g. headless servers)
  local ok_dms = pcall(vim.cmd.colorscheme, "dms")
  if not ok_dms then
    local ok_base46_nord = pcall(vim.cmd.colorscheme, "base46-nord")
    if not ok_base46_nord then
      pcall(vim.cmd.colorscheme, "nord")
    end
  end
else
  pcall(vim.cmd.colorscheme, "nord")
end

-- Make floating windows transparent
vim.api.nvim_set_hl(0, 'NormalFloat', { bg = 'none' })
vim.api.nvim_set_hl(0, 'FloatBorder', { bg = 'none' })

----------------------------------------------------------------
-- Oil (file explorer)
----------------------------------------------------------------
local oil = require("oil")
local oil_actions = require("oil.actions")

local function oil_select_with_pdf_opener()
  local entry = oil.get_cursor_entry()
  local dir = oil.get_current_dir()

  if not entry or not dir then
    return
  end

  if entry.type == "directory" or not entry.name:lower():match("%.pdf$") then
    oil_actions.select.callback()
    return
  end

  if vim.w.is_oil_win then
    oil_actions.close.callback()
  end

  local path = vim.fn.fnamemodify(dir .. entry.name, ":p")
  local jid = vim.fn.jobstart({ "zathura", path }, { detach = true })

  if jid <= 0 then
    vim.notify("Failed to open PDF in zathura: " .. path, vim.log.levels.ERROR)
  end
end

oil.setup({
  view_options = { show_hidden = true },
  float = {
    padding = 2,
    max_width = 90,
    max_height = 30,
    border = "rounded",
  },
  keymaps = {
    ["<CR>"] = {
      callback = oil_select_with_pdf_opener,
      desc = "Open PDFs in zathura, otherwise select",
      mode = "n",
    },
    ["<C-c>"] = "actions.close",
    ["<C-h>"] = false,
    ["<C-l>"] = false,
  },
})

----------------------------------------------------------------
-- Telescope (fuzzy finder)
----------------------------------------------------------------
require("telescope").setup({
  defaults = {
    sorting_strategy = "ascending",
    layout_config = { prompt_position = "top" },
  },
  pickers = {
    find_files = {
      find_command = { "rg", "--files", "--hidden", "--glob", "!**/.git/*" }
    },
  },
})

----------------------------------------------------------------
-- Treesitter (syntax highlighting)
----------------------------------------------------------------
local ok, treesitter = pcall(require, "nvim-treesitter")
if ok then
  local parser_install_dir = vim.fs.joinpath(vim.fn.stdpath("data"), "site")
  local treesitter_languages = {
    "bash",
    "c",
    "cpp",
    "css",
    "html",
    "javascript",
    "json",
    "latex",
    "lua",
    "python",
    "tsx",
    "typst",
    "typescript",
  }
  local treesitter_filetypes = {
    "bash",
    "c",
    "cpp",
    "css",
    "html",
    "javascript",
    "javascriptreact",
    "json",
    "lua",
    "python",
    "sh",
    "tex",
    "typst",
    "typescript",
    "typescriptreact",
  }

  treesitter.setup({ install_dir = parser_install_dir })

  vim.treesitter.language.register("bash", "sh")
  vim.treesitter.language.register("javascript", "javascriptreact")
  vim.treesitter.language.register("latex", "tex")
  vim.treesitter.language.register("tsx", "typescriptreact")

  vim.api.nvim_create_user_command("TSInstallConfigured", function(opts)
    local task = treesitter.install(treesitter_languages, { summary = true })
    if opts.bang then
      task:wait(300000)
    end
  end, { bang = true, desc = "Install configured Treesitter parsers" })

  vim.api.nvim_create_user_command("TSUpdateConfigured", function(opts)
    local task = treesitter.update(treesitter_languages, { summary = true })
    if opts.bang then
      task:wait(300000)
    end
  end, { bang = true, desc = "Update configured Treesitter parsers" })

  vim.api.nvim_create_autocmd("FileType", {
    pattern = treesitter_filetypes,
    callback = function()
      if pcall(vim.treesitter.start) then
        vim.bo.indentexpr = "v:lua.require'nvim-treesitter'.indentexpr()"
      end
    end,
  })
end

----------------------------------------------------------------
-- ToggleTerm (terminal)
----------------------------------------------------------------
require("toggleterm").setup({
  size = 20,
  open_mapping = [[<c-\>]],
  direction = "horizontal",
  start_in_insert = true,
})

----------------------------------------------------------------
-- Neotree (file tree)
----------------------------------------------------------------
local ok_neotree, neotree = pcall(require, "neo-tree")
if ok_neotree then
  neotree.setup({
    close_if_last_window = true,
    window = {
      width = 30,
      mappings = {
        ["<C-c>"] = "close_window",
        ["h"] = "parent",
        ["l"] = "open",
      },
    },
    filesystem = {
      filtered_items = {
        hide_dotfiles = false,
        hide_gitignored = false,
      },
    },
  })
end

----------------------------------------------------------------
----------------------------------------------------------------
-- Colorizer (color code preview)
----------------------------------------------------------------
local ok_colorizer, colorizer = pcall(require, "colorizer")
if ok_colorizer then
  colorizer.setup({
    filetypes = { "*" },
    user_default_options = {
      RGB = true,      -- #RGB hex codes
      RRGGBB = true,   -- #RRGGBB hex codes
      names = true,    -- "Name" codes like Blue
      RRGGBBAA = true, -- #RRGGBBAA hex codes
      rgb_fn = true,   -- CSS rgb() and rgba() functions
      hsl_fn = true,   -- CSS hsl() and hsla() functions
      css = true,      -- Enable all CSS features
      css_fn = true,   -- Enable all CSS functions
    },
  })
end

----------------------------------------------------------------
-- Render Markdown (inline rendering)
----------------------------------------------------------------
local ok_render, render = pcall(require, "render-markdown")
if ok_render then
  render.setup({
    enabled = false, -- Start disabled, toggle with <leader>mr
  })
end
