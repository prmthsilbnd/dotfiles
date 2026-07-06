----------------------------------------------------------------
-- Leader key
----------------------------------------------------------------
vim.g.mapleader = " "
vim.g.maplocalleader = " "

----------------------------------------------------------------
-- Core Settings
----------------------------------------------------------------
local opt = vim.opt
opt.number = true
opt.relativenumber = true
opt.splitbelow = true
opt.splitright = true
opt.termguicolors = true
opt.shiftwidth = 2
opt.tabstop = 2
opt.expandtab = true
opt.mouse = "a"
opt.clipboard = ""
opt.completeopt = { "menuone", "noselect", "popup" }

----------------------------------------------------------------
-- Auto-detect project root and set working directory
----------------------------------------------------------------
vim.api.nvim_create_autocmd("VimEnter", {
  callback = function()
    local markers = { ".git", "CMakeLists.txt", "Makefile", "package.json" }
    local current = vim.fn.expand("%:p:h")
    while current ~= "/" do
      for _, marker in ipairs(markers) do
        if vim.fn.isdirectory(current .. "/" .. marker) == 1 or
           vim.fn.filereadable(current .. "/" .. marker) == 1 then
          vim.cmd.cd(current)
          return
        end
      end
      current = vim.fn.fnamemodify(current, ":h")
    end
  end,
})

----------------------------------------------------------------
-- Load modules
----------------------------------------------------------------
require("plugins")
require("lsp")
require("cpp")
require("latex")

----------------------------------------------------------------
-- Keymaps
----------------------------------------------------------------
local map = vim.keymap.set

-- File explorer
map("n", "<leader>e", function() require("oil").open_float() end, { desc = "File explorer" })
map("n", "<leader>n", "<cmd>Neotree toggle<cr>", { desc = "Toggle Neotree" })

-- Telescope
map("n", "<leader>ff", "<cmd>Telescope find_files<cr>", { desc = "Find files" })
map("n", "<leader>fg", "<cmd>Telescope live_grep<cr>", { desc = "Live grep" })
map("n", "<leader>fb", "<cmd>Telescope buffers<cr>", { desc = "Buffers" })
map("n", "<leader>fh", "<cmd>Telescope help_tags<cr>", { desc = "Help tags" })

-- Terminal
map("n", "<leader>t", "<cmd>ToggleTerm<cr>", { desc = "Toggle terminal" })
-- In terminal mode, avoid leader mappings so <Space> types normally.
map("t", "<C-\\><C-t>", "<C-\\><C-n><cmd>ToggleTerm<cr>", { desc = "Toggle terminal (from terminal mode)" })

-- File operations
map("n", "<leader>w", "<cmd>w<cr>", { desc = "Save" })
map("n", "<leader>q", "<cmd>q<cr>", { desc = "Quit" })

-- Window navigation
map({"n", "t"}, "<C-h>", "<C-w>h", { desc = "Move left" })
map({"n", "t"}, "<C-j>", "<C-w>j", { desc = "Move down" })
map({"n", "t"}, "<C-k>", "<C-w>k", { desc = "Move up" })
map({"n", "t"}, "<C-l>", "<C-w>l", { desc = "Move right" })

-- Directional pane resizing with <C-w><C-hjkl>
map("n", "<C-w><C-h>", "<C-w><", { desc = "Decrease window width" })
map("n", "<C-w><C-j>", "<C-w>+", { desc = "Increase window height" })
map("n", "<C-w><C-k>", "<C-w>-", { desc = "Decrease window height" })
map("n", "<C-w><C-l>", "<C-w>>", { desc = "Increase window width" })

-- Move visual blocks up/down
map("v", "J", ":m '>+1<CR>gv=gv", { desc = "Move line down" })
map("v", "K", ":m '<-2<CR>gv=gv", { desc = "Move line up" })

-- Center cursor when jumping
map("n", "<C-e>", "<C-e>j", { desc = "Scroll down and move cursor" })
map("n", "<C-y>", "<C-y>k", { desc = "Scroll up and move cursor" })
map("n", "<C-d>", "<C-d>zz")
map("n", "<C-u>", "<C-u>zz")
map("n", "n", "nzzzv")
map("n", "N", "Nzzzv")

-- Paste without losing register
map("x", "<leader>p", [["_dP]])

-- System clipboard
map({"n", "v"}, "<leader>y", '"+y', { desc = "Yank to clipboard" })

-- Comment toggle (VSCode-style)
map("n", "<C-/>", "gcc", { remap = true, desc = "Toggle comment line" })
map("v", "<C-/>", "gc", { remap = true, desc = "Toggle comment selection" })

-- Terminal mode escape
vim.api.nvim_create_autocmd("TermOpen", {
  callback = function()
    vim.keymap.set('t', '<Esc>', [[<C-\><C-n>]], { buffer = true })
  end,
})

-- Markdown reading mode
vim.api.nvim_create_autocmd("FileType", {
  pattern = "markdown",
  callback = function()
    vim.keymap.set('n', '<leader>mr', '<cmd>RenderMarkdown toggle<cr>', { buffer = true, desc = "Toggle markdown render" })
  end,
})

-- Python run/debug keybinds
vim.api.nvim_create_autocmd("FileType", {
  pattern = "python",
  callback = function()
    local map = vim.keymap.set
    map('n', '<leader>rr', '<cmd>TermExec cmd="python3 %"<cr>', { buffer = true, desc = "Run Python" })
    map('n', '<leader>rd', '<cmd>TermExec cmd="python3 -m pdb %"<cr>', { buffer = true, desc = "Debug Python" })
  end,
})

-- HTML run/debug-style keybinds
vim.api.nvim_create_autocmd("FileType", {
  pattern = "html",
  callback = function()
    local map = vim.keymap.set
    map('n', '<leader>rr', function() require("web_preview").start_static_server() end, { buffer = true, desc = "Web: Start Wrangler preview" })
    map('n', '<leader>rd', function() require("web_preview").open_in_browser() end, { buffer = true, desc = "Web: Open current route" })
  end,
})
