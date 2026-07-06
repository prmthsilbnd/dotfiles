local M = {}
local preview_url = "http://localhost:4173"
local markers = { "wrangler.toml", ".git", "package.json" }

local function project_root()
  local file_path = vim.fn.expand("%:p")
  local start = file_path ~= "" and vim.fs.dirname(file_path) or vim.loop.cwd()
  local found = vim.fs.find(markers, { upward = true, path = start })[1]
  return found and vim.fs.dirname(found) or vim.loop.cwd()
end

local function build_preview_command()
  if vim.fn.executable("wrangler") == 1 then
    return "wrangler pages dev . --port=4173"
  end

  if vim.fn.executable("npx") == 1 then
    return "npx --yes wrangler pages dev . --port=4173"
  end

  return nil
end

local function current_route()
  if vim.bo.filetype ~= "html" then
    return "/"
  end

  local absolute = vim.fn.expand("%:p")
  local root = project_root()
  if absolute == "" or absolute:sub(1, #root) ~= root then
    return "/"
  end

  local relative = absolute:sub(#root + 2)
  if relative == "" or relative:sub(-5) ~= ".html" then
    return "/"
  end

  if relative == "index.html" then
    return "/"
  end

  local base = relative:gsub("\\", "/"):gsub("%.html$", "")
  return "/" .. base
end

function M.start_static_server()
  local cmd = build_preview_command()
  if not cmd then
    vim.notify("Install Wrangler or npx to run preview", vim.log.levels.ERROR)
    return
  end

  vim.cmd(("TermExec cmd=%q dir=%q go_back=0 direction=horizontal"):format(cmd, project_root()))
  vim.notify("Wrangler preview on " .. preview_url, vim.log.levels.INFO)
end

function M.open_in_browser()
  if vim.fn.executable("xdg-open") == 0 then
    vim.notify("xdg-open is not installed", vim.log.levels.ERROR)
    return
  end

  vim.fn.jobstart({ "xdg-open", preview_url .. current_route() }, { detach = true })
end

return M
