----------------------------------------------------------------
-- LaTeX Configuration
----------------------------------------------------------------

-- Compile and view PDF
local function compile_latex()
  local file = vim.fn.expand("%:t:r")  -- Current file basename

  if vim.fn.filereadable(".latexmkrc") == 1 then
    -- Use latexmk with project settings
    vim.cmd("TermExec cmd='latexmk -interaction=nonstopmode " .. file .. ".tex'")
  else
    -- Basic lualatex compilation
    vim.cmd("TermExec cmd='lualatex -interaction=nonstopmode " .. file .. ".tex'")
  end
end

-- View PDF
local function view_pdf()
  local file = vim.fn.expand("%:t:r")

  -- Check for PDF in common locations
  local pdf_locations = {
    "out_dir/" .. file .. ".pdf",  -- latexmk output directory
    file .. ".pdf",                 -- current directory
  }

  for _, pdf_path in ipairs(pdf_locations) do
    if vim.fn.filereadable(pdf_path) == 1 then
      vim.cmd("TermExec cmd='xdg-open " .. pdf_path .. "'")
      return
    end
  end

  print("PDF not found. Compile first with <leader>ll")
end

-- Clean auxiliary files
local function clean_latex()
  if vim.fn.filereadable(".latexmkrc") == 1 then
    vim.cmd("TermExec cmd='latexmk -c'")
  else
    vim.cmd("TermExec cmd='rm -f *.aux *.log *.out *.toc *.bbl *.blg *.fdb_latexmk *.fls *.synctex.gz'")
  end
  print("✓ Cleaned auxiliary files")
end

-- Full clean (including PDF)
local function clean_latex_full()
  if vim.fn.filereadable(".latexmkrc") == 1 then
    vim.cmd("TermExec cmd='latexmk -C'")
  else
    vim.cmd("TermExec cmd='rm -f *.aux *.log *.out *.toc *.bbl *.blg *.fdb_latexmk *.fls *.synctex.gz *.pdf'")
  end
  print("✓ Full clean completed")
end

-- Continuous compilation mode
local function compile_continuous()
  local file = vim.fn.expand("%:t:r")

  if vim.fn.filereadable(".latexmkrc") == 1 then
    vim.cmd("TermExec cmd='latexmk -pvc -interaction=nonstopmode " .. file .. ".tex'")
  else
    print("Continuous mode requires latexmk with .latexmkrc")
  end
end

-- LaTeX FileType autocmd
vim.api.nvim_create_autocmd("FileType", {
  pattern = "tex",
  callback = function()
    local map = vim.keymap.set

    -- Compile and view
    map('n', '<leader>ll', compile_latex, { buffer = true, desc = "LaTeX: Compile" })
    map('n', '<leader>lv', view_pdf, { buffer = true, desc = "LaTeX: View PDF" })
    map('n', '<leader>lc', clean_latex, { buffer = true, desc = "LaTeX: Clean" })
    map('n', '<leader>lC', clean_latex_full, { buffer = true, desc = "LaTeX: Full clean" })
    map('n', '<leader>lp', compile_continuous, { buffer = true, desc = "LaTeX: Continuous preview" })

    -- VimTeX settings
    vim.g.vimtex_view_method = 'general'
    vim.g.vimtex_compiler_method = 'latexmk'
    vim.g.vimtex_quickfix_mode = 0  -- Don't auto-open quickfix
  end,
})
