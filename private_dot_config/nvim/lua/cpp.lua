----------------------------------------------------------------
-- C++ Configuration
----------------------------------------------------------------

-- Helper: Detect dependencies from file content
local function detect_deps(content)
  local deps = {}
  for _, line in ipairs(content) do
    if line:match("#include.*Eigen/") then deps["eigen3"] = true end
    if line:match("#include.*fmt/") then deps["fmt"] = true end
    if line:match("#include.*boost/") then deps["boost"] = true end
  end
  return deps
end

-- Helper: Get pkg-config flags for dependencies
local function get_pkg_flags(deps)
  local flags = ""
  for dep, _ in pairs(deps) do
    local cflags = vim.fn.system("pkg-config --cflags " .. dep .. " 2>/dev/null"):gsub("\n", "")
    local libs = vim.fn.system("pkg-config --libs " .. dep .. " 2>/dev/null"):gsub("\n", "")
    if cflags ~= "" then flags = flags .. " " .. cflags end
    if libs ~= "" then flags = flags .. " " .. libs end
  end
  return flags
end

-- Run C++ code
local function run_cpp()
  local file = vim.fn.expand("%:t:r")  -- Current file basename without extension

  if vim.fn.filereadable("CMakeLists.txt") == 1 then
    vim.cmd("TermExec cmd='cmake -B build && cmake --build build && ./build/" .. file .. "'")
  elseif vim.fn.filereadable("Makefile") == 1 then
    vim.cmd("TermExec cmd='make && ./" .. file .. "'")
  else
    local content = vim.fn.readfile(vim.fn.expand("%"))
    local deps = detect_deps(content)
    local flags = get_pkg_flags(deps)
    vim.cmd("TermExec cmd='clang++ -std=c++17 -Wall" .. flags .. " % -o " .. file .. " && ./" .. file .. "'")
  end
end

-- Debug C++ code
local function debug_cpp()
  local file = vim.fn.expand("%:t:r")
  local content = vim.fn.readfile(vim.fn.expand("%"))
  local deps = detect_deps(content)
  local flags = get_pkg_flags(deps)
  vim.cmd("TermExec cmd='clang++ -g -std=c++17 -Wall" .. flags .. " % -o " .. file .. " && lldb ./" .. file .. "'")
end

-- C++ FileType autocmd
vim.api.nvim_create_autocmd("FileType", {
  pattern = "cpp",
  callback = function()
    local map = vim.keymap.set
    map('n', '<leader>rr', run_cpp, { buffer = true, desc = "Run C++" })
    map('n', '<leader>rd', debug_cpp, { buffer = true, desc = "Debug C++" })
  end,
})

-- :CppInit command - Auto-generate CMakeLists.txt
vim.api.nvim_create_user_command('CppInit', function(opts)
  local cwd = vim.fn.getcwd()
  local project_name = vim.fn.fnamemodify(cwd, ":t")

  -- Check if CMakeLists.txt exists
  if vim.fn.filereadable("CMakeLists.txt") == 1 and not opts.bang then
    print("CMakeLists.txt already exists. Use :CppInit! to overwrite.")
    return
  end

  -- Find all .cpp files in current directory
  local cpp_files = vim.fn.glob("*.cpp", false, true)
  if #cpp_files == 0 then
    print("No .cpp files found in current directory")
    return
  end

  -- Determine executable name: use current file if .cpp, else first .cpp file found
  local current_file = vim.fn.expand("%:t")
  local exe_name
  if current_file:match("%.cpp$") then
    exe_name = vim.fn.expand("%:t:r")
  else
    exe_name = vim.fn.fnamemodify(cpp_files[1], ":t:r")
  end

  -- Detect dependencies from all .cpp files
  local deps = {}
  for _, file in ipairs(cpp_files) do
    local content = vim.fn.readfile(file)
    for _, line in ipairs(content) do
      if line:match("#include.*Eigen/") then deps["Eigen3"] = true end
      if line:match("#include.*fmt/") then deps["fmt"] = true end
      if line:match("#include.*boost/") then deps["Boost"] = true end
    end
  end

  -- Generate CMakeLists.txt
  local cmake_content = {
    "cmake_minimum_required(VERSION 3.15)",
    "project(" .. project_name .. ")",
    "",
    "set(CMAKE_CXX_STANDARD 17)",
    "set(CMAKE_CXX_STANDARD_REQUIRED ON)",
    "set(CMAKE_EXPORT_COMPILE_COMMANDS ON)  # For clangd",
    "",
  }

  -- Add find_package for detected dependencies
  for dep, _ in pairs(deps) do
    table.insert(cmake_content, "find_package(" .. dep .. " REQUIRED)")
  end
  if next(deps) then table.insert(cmake_content, "") end

  -- Add executable
  table.insert(cmake_content, "# Add your source files here")
  table.insert(cmake_content, "add_executable(" .. exe_name)
  for _, file in ipairs(cpp_files) do
    table.insert(cmake_content, "  " .. file)
  end
  table.insert(cmake_content, ")")
  table.insert(cmake_content, "")

  -- Link libraries
  if next(deps) then
    table.insert(cmake_content, "target_link_libraries(" .. exe_name)
    for dep, _ in pairs(deps) do
      if dep == "Eigen3" then
        table.insert(cmake_content, "  Eigen3::Eigen")
      elseif dep == "fmt" then
        table.insert(cmake_content, "  fmt::fmt")
      elseif dep == "Boost" then
        table.insert(cmake_content, "  Boost::boost")
      end
    end
    table.insert(cmake_content, ")")
  end

  -- Write CMakeLists.txt
  vim.fn.writefile(cmake_content, "CMakeLists.txt")
  print("✓ Created CMakeLists.txt")
  print("✓ Run: cmake -B build && cmake --build build")
  print("✓ Or just use <leader>rr to compile and run!")
end, { bang = true })
