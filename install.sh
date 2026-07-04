#!/usr/bin/env bash
set -euo pipefail

DOTFILES_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
HOME_DIR="${HOME:?HOME is not set}"
BACKUP_DIR="${HOME_DIR}/.dotfiles-backups/$(date +"%Y%m%d-%H%M%S")"
DRY_RUN=0
SKIP_NVIM_TOOLS=0
ONLY_NVIM_TOOLS=0

usage() {
  cat <<'EOF'
Usage: ./install.sh [--dry-run] [--skip-nvim-tools] [--only-nvim-tools]

Symlink managed dotfiles from this repo into your home directory.
Existing files are moved to ~/.dotfiles-backups/<timestamp>/ before linking.
Tmux plugins are installed automatically when git and tmux are available.
Figlet is installed automatically when a supported package manager is available.
Neovim 0.12+ is installed automatically when possible.
Neovim LSP and Treesitter tooling is installed best-effort unless skipped.
Use --only-nvim-tools to run just the Neovim/tool bootstrap.
EOF
}

run() {
  if [[ "${DRY_RUN}" -eq 1 ]]; then
    printf '[dry-run]'
    for arg in "$@"; do
      printf ' %q' "${arg}"
    done
    printf '\n'
  else
    "$@"
  fi
}

link_path() {
  local source_path="$1"
  local target_path="$2"

  if [[ ! -e "${source_path}" && ! -L "${source_path}" ]]; then
    printf 'Missing source: %s\n' "${source_path}" >&2
    return 1
  fi

  run mkdir -p "$(dirname "${target_path}")"

  if [[ -L "${target_path}" ]]; then
    local existing_target
    existing_target="$(readlink "${target_path}")"
    if [[ "${existing_target}" == "${source_path}" ]]; then
      printf 'already linked: %s -> %s\n' "${target_path}" "${source_path}"
      return 0
    fi
  fi

  if [[ -e "${target_path}" || -L "${target_path}" ]]; then
    local relative_target backup_target
    relative_target="${target_path#"${HOME_DIR}/"}"
    backup_target="${BACKUP_DIR}/${relative_target}"
    run mkdir -p "$(dirname "${backup_target}")"
    run mv "${target_path}" "${backup_target}"
    printf 'backup: %s -> %s\n' "${target_path}" "${backup_target}"
  fi

  run ln -s "${source_path}" "${target_path}"
  printf 'linked: %s -> %s\n' "${target_path}" "${source_path}"
}

ensure_file() {
  local file_path="$1"

  if [[ -e "${file_path}" || -L "${file_path}" ]]; then
    return 0
  fi

  run mkdir -p "$(dirname "${file_path}")"
  run touch "${file_path}"
  printf 'created: %s\n' "${file_path}"
}

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

version_at_least() {
  local current="$1"
  local required="$2"
  local current_major current_minor current_patch required_major required_minor required_patch

  current="${current#v}"
  required="${required#v}"
  current="${current%%[-+~]*}"
  required="${required%%[-+~]*}"

  IFS=. read -r current_major current_minor current_patch <<<"${current}"
  IFS=. read -r required_major required_minor required_patch <<<"${required}"

  current_major="${current_major:-0}"
  current_minor="${current_minor:-0}"
  current_patch="${current_patch:-0}"
  required_major="${required_major:-0}"
  required_minor="${required_minor:-0}"
  required_patch="${required_patch:-0}"

  if (( current_major != required_major )); then
    (( current_major > required_major ))
    return
  fi
  if (( current_minor != required_minor )); then
    (( current_minor > required_minor ))
    return
  fi
  (( current_patch >= required_patch ))
}

is_windows_posix() {
  case "$(uname -s 2>/dev/null || printf unknown)" in
    CYGWIN*|MINGW*|MSYS*)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

run_root() {
  if [[ "${EUID}" -eq 0 ]]; then
    run "$@"
  elif command_exists sudo; then
    run sudo "$@"
  else
    return 1
  fi
}

download_file() {
  local url="$1"
  local output_path="$2"

  if command_exists curl; then
    run curl -fL "${url}" -o "${output_path}"
    return
  fi

  if command_exists wget; then
    run wget -O "${output_path}" "${url}"
    return
  fi

  if [[ "${DRY_RUN}" -eq 1 ]]; then
    run curl -fL "${url}" -o "${output_path}"
    return
  fi

  return 1
}

fetch_url() {
  local url="$1"

  if command_exists curl; then
    curl -fsSL "${url}"
    return
  fi

  if command_exists wget; then
    wget -qO- "${url}"
    return
  fi

  return 1
}

installed_neovim_version() {
  if ! command_exists nvim; then
    return 1
  fi

  nvim --version | sed -n '1s/^NVIM v\([0-9][0-9.]*\).*/\1/p'
}

apt_neovim_candidate_version() {
  if ! command_exists apt-cache; then
    return 1
  fi

  apt-cache policy neovim 2>/dev/null | sed -n 's/^[[:space:]]*Candidate:[[:space:]]*\([^[:space:]]*\).*/\1/p'
}

install_neovim_with_package_manager() {
  local min_version="$1"
  local candidate_version

  if command_exists apt-get; then
    candidate_version="$(apt_neovim_candidate_version || true)"
    if [[ -n "${candidate_version}" && "${candidate_version}" != "(none)" ]] && version_at_least "${candidate_version}" "${min_version}"; then
      if run_root apt-get install -y neovim; then
        printf 'installed: neovim\n'
      else
        printf 'neovim install skipped: root or sudo is required\n' >&2
      fi
      return 0
    fi
    printf 'neovim apt candidate too old: %s\n' "${candidate_version:-none}" >&2
    return 1
  fi

  if command_exists pacman; then
    if run_root pacman -S --needed --noconfirm neovim; then
      printf 'installed: neovim\n'
      return 0
    fi
    printf 'neovim install skipped: root or sudo is required\n' >&2
    return 1
  fi

  if command_exists brew; then
    if brew list neovim >/dev/null 2>&1; then
      if run brew upgrade neovim; then
        printf 'updated: neovim\n'
        return 0
      fi
    elif run brew install neovim; then
      printf 'installed: neovim\n'
      return 0
    fi
    printf 'neovim install skipped: brew install failed\n' >&2
    return 1
  fi

  return 1
}

neovim_tarball_asset() {
  case "$(uname -m)" in
    x86_64|amd64)
      printf 'nvim-linux-x86_64'
      ;;
    aarch64|arm64)
      printf 'nvim-linux-arm64'
      ;;
    *)
      return 1
      ;;
  esac
}

latest_neovim_tarball_url() {
  local asset_base="$1"
  local metadata_url="https://api.github.com/repos/neovim/neovim/releases/latest"
  local metadata

  metadata="$(fetch_url "${metadata_url}")"
  printf '%s\n' "${metadata}" |
    sed -n "s/.*\"browser_download_url\": \"\(.*${asset_base}\.tar\.gz\)\".*/\1/p" |
    head -n 1
}

install_neovim_tarball() {
  local min_version="$1"
  local asset_base tarball_url tmp_dir archive_path extracted_path opt_path bin_path

  if ! asset_base="$(neovim_tarball_asset)"; then
    printf 'neovim tarball install skipped: unsupported architecture %s\n' "$(uname -m)" >&2
    return 0
  fi

  opt_path="/opt/${asset_base}"
  bin_path="/usr/local/bin/nvim"

  if [[ "${DRY_RUN}" -eq 1 ]]; then
    tarball_url="https://github.com/neovim/neovim/releases/latest/download/${asset_base}.tar.gz"
    archive_path="/tmp/${asset_base}.tar.gz"
    extracted_path="/tmp/${asset_base}"
    download_file "${tarball_url}" "${archive_path}"
    run tar -xzf "${archive_path}" -C /tmp
    run_root mkdir -p /opt /usr/local/bin
    run_root rm -rf "${opt_path}"
    run_root mv "${extracted_path}" "${opt_path}"
    run_root ln -sfn "${opt_path}/bin/nvim" "${bin_path}"
    printf 'would install neovim %s+ tarball: %s\n' "${min_version}" "${opt_path}"
    return 0
  fi

  if ! command_exists tar; then
    printf 'neovim tarball install skipped: tar is required\n' >&2
    return 0
  fi

  if ! command_exists curl && ! command_exists wget; then
    printf 'neovim tarball install skipped: curl or wget is required\n' >&2
    return 0
  fi

  if ! tarball_url="$(latest_neovim_tarball_url "${asset_base}")" || [[ -z "${tarball_url}" ]]; then
    printf 'neovim tarball install skipped: could not find latest %s tarball\n' "${asset_base}" >&2
    return 0
  fi

  tmp_dir="$(mktemp -d)"
  archive_path="${tmp_dir}/${asset_base}.tar.gz"
  extracted_path="${tmp_dir}/${asset_base}"

  if ! download_file "${tarball_url}" "${archive_path}"; then
    printf 'neovim tarball install skipped: download failed\n' >&2
    rm -rf "${tmp_dir}"
    return 0
  fi

  if ! tar -xzf "${archive_path}" -C "${tmp_dir}" || [[ ! -x "${extracted_path}/bin/nvim" ]]; then
    printf 'neovim tarball install skipped: archive did not contain %s/bin/nvim\n' "${asset_base}" >&2
    rm -rf "${tmp_dir}"
    return 0
  fi

  if ! run_root mkdir -p /opt /usr/local/bin ||
     ! run_root rm -rf "${opt_path}" ||
     ! run_root mv "${extracted_path}" "${opt_path}" ||
     ! run_root ln -sfn "${opt_path}/bin/nvim" "${bin_path}"; then
    printf 'neovim tarball install skipped: root or sudo is required\n' >&2
    rm -rf "${tmp_dir}"
    return 0
  fi

  rm -rf "${tmp_dir}"
  printf 'installed neovim tarball: %s\n' "${opt_path}"

  if [[ "$(command -v nvim 2>/dev/null || true)" != "${bin_path}" ]]; then
    printf 'neovim warning: PATH resolves nvim to %s, not %s\n' "$(command -v nvim 2>/dev/null || printf 'nothing')" "${bin_path}" >&2
  fi
}

install_neovim() {
  local min_version="0.12.0"
  local current_version

  current_version="$(installed_neovim_version || true)"
  if [[ -n "${current_version}" ]] && version_at_least "${current_version}" "${min_version}"; then
    printf 'already installed: neovim %s\n' "${current_version}"
    return 0
  fi

  if [[ -n "${current_version}" ]]; then
    printf 'neovim version too old: %s < %s\n' "${current_version}" "${min_version}" >&2
  else
    printf 'neovim not found\n' >&2
  fi

  if install_neovim_with_package_manager "${min_version}"; then
    current_version="$(installed_neovim_version || true)"
    if [[ -n "${current_version}" ]] && version_at_least "${current_version}" "${min_version}"; then
      return 0
    fi
  fi

  install_neovim_tarball "${min_version}"
}

install_figlet() {
  if command_exists figlet; then
    printf 'already installed: figlet\n'
    return 0
  fi

  if command_exists apt-get; then
    if run_root apt-get update && run_root apt-get install -y figlet; then
      printf 'installed: figlet\n'
    else
      printf 'figlet install skipped: root or sudo is required\n' >&2
    fi
    return 0
  fi

  if command_exists pacman; then
    if run_root pacman -S --needed --noconfirm figlet; then
      printf 'installed: figlet\n'
    else
      printf 'figlet install skipped: root or sudo is required\n' >&2
    fi
    return 0
  fi

  if command_exists brew; then
    if run brew install figlet; then
      printf 'installed: figlet\n'
    else
      printf 'figlet install skipped: brew install failed\n' >&2
    fi
    return 0
  fi

  printf 'figlet install skipped: apt-get, pacman, or brew is required\n' >&2
}

install_apt_package() {
  local package="$1"

  if dpkg-query -W -f='${Status}' "${package}" 2>/dev/null | grep -q "install ok installed"; then
    printf 'already installed: %s\n' "${package}"
    return 0
  fi

  if run_root apt-get install -y "${package}"; then
    printf 'installed: %s\n' "${package}"
  else
    printf 'package install skipped: %s\n' "${package}" >&2
  fi
}

install_pacman_package() {
  local package="$1"

  if pacman -Q "${package}" >/dev/null 2>&1; then
    printf 'already installed: %s\n' "${package}"
    return 0
  fi

  if run_root pacman -S --needed --noconfirm "${package}"; then
    printf 'installed: %s\n' "${package}"
  else
    printf 'package install skipped: %s\n' "${package}" >&2
  fi
}

install_dnf_package() {
  local package="$1"

  if rpm -q "${package}" >/dev/null 2>&1; then
    printf 'already installed: %s\n' "${package}"
    return 0
  fi

  if run_root dnf install -y "${package}"; then
    printf 'installed: %s\n' "${package}"
  else
    printf 'package install skipped: %s\n' "${package}" >&2
  fi
}

install_brew_package() {
  local package="$1"

  if brew list --versions "${package}" >/dev/null 2>&1; then
    printf 'already installed: %s\n' "${package}"
    return 0
  fi

  if run brew install "${package}"; then
    printf 'installed: %s\n' "${package}"
  else
    printf 'package install skipped: %s\n' "${package}" >&2
  fi
}

install_brew_cask() {
  local package="$1"

  if brew list --cask --versions "${package}" >/dev/null 2>&1; then
    printf 'already installed: %s\n' "${package}"
    return 0
  fi

  if run brew install --cask "${package}"; then
    printf 'installed: %s\n' "${package}"
  else
    printf 'package install skipped: %s\n' "${package}" >&2
  fi
}

install_winget_package() {
  local package_id="$1"

  if winget list --exact --id "${package_id}" >/dev/null 2>&1; then
    printf 'already installed: %s\n' "${package_id}"
    return 0
  fi

  if run winget install --exact --id "${package_id}" --accept-package-agreements --accept-source-agreements; then
    printf 'installed: %s\n' "${package_id}"
  else
    printf 'package install skipped: %s\n' "${package_id}" >&2
  fi
}

latex_style_exists() {
  command_exists kpsewhich && kpsewhich "$1" >/dev/null 2>&1
}

link_mactex_commands() {
  local mactex_bin="/Library/TeX/texbin"
  local command_name

  [[ -d "${mactex_bin}" ]] || return 0

  run mkdir -p "${HOME_DIR}/.local/bin"
  for command_name in kpsewhich latexmk lualatex pdflatex; do
    if [[ -x "${mactex_bin}/${command_name}" ]]; then
      run ln -sf "${mactex_bin}/${command_name}" "${HOME_DIR}/.local/bin/${command_name}"
      printf 'linked: %s -> %s\n' "${HOME_DIR}/.local/bin/${command_name}" "${mactex_bin}/${command_name}"
    fi
  done
}

install_latex_system_tools_apt() {
  command_exists texlab || install_apt_package texlab
  command_exists latexmk || install_apt_package latexmk
  command_exists lualatex || install_apt_package texlive-luatex
  latex_style_exists article.cls || install_apt_package texlive-latex-recommended
  latex_style_exists enumitem.sty || install_apt_package texlive-latex-extra
  latex_style_exists lmodern.sty || install_apt_package texlive-fonts-recommended
  command_exists xdg-open || install_apt_package xdg-utils
}

install_latex_system_tools_pacman() {
  command_exists texlab || install_pacman_package texlab
  command_exists latexmk || install_pacman_package texlive-binextra
  command_exists lualatex || install_pacman_package texlive-luatex
  latex_style_exists article.cls || install_pacman_package texlive-latexrecommended
  latex_style_exists enumitem.sty || install_pacman_package texlive-latexextra
  latex_style_exists lmodern.sty || install_pacman_package texlive-fontsrecommended
  command_exists xdg-open || install_pacman_package xdg-utils
}

install_latex_system_tools_dnf() {
  command_exists texlab || install_dnf_package texlab
  command_exists latexmk || install_dnf_package texlive-latexmk
  command_exists lualatex || install_dnf_package texlive-luatex
  latex_style_exists article.cls || install_dnf_package texlive-collection-latexrecommended
  latex_style_exists enumitem.sty || install_dnf_package texlive-collection-latexextra
  latex_style_exists lmodern.sty || install_dnf_package texlive-collection-fontsrecommended
  command_exists xdg-open || install_dnf_package xdg-utils
}

install_latex_system_tools_brew() {
  command_exists texlab || install_brew_package texlab
  if ! command_exists latexmk || ! command_exists lualatex; then
    install_brew_cask mactex-no-gui
    link_mactex_commands
  fi
}

install_latex_system_tools_winget() {
  command_exists texlab || install_winget_package latex-lsp.texlab
  if ! command_exists latexmk || ! command_exists lualatex; then
    install_winget_package MiKTeX.MiKTeX
  fi
}

install_nvim_system_tools_apt() {
  run_root apt-get update || printf 'apt update skipped: root or sudo is required\n' >&2

  command_exists node || install_apt_package nodejs
  command_exists npm || install_apt_package npm
  command_exists clangd || install_apt_package clangd
  command_exists tree-sitter || install_apt_package tree-sitter-cli
  install_latex_system_tools_apt
}

install_nvim_system_tools_pacman() {
  command_exists node || install_pacman_package nodejs
  command_exists npm || install_pacman_package npm
  command_exists clangd || install_pacman_package clang
  command_exists lua-language-server || install_pacman_package lua-language-server
  command_exists tree-sitter || install_pacman_package tree-sitter-cli
  install_latex_system_tools_pacman
}

install_nvim_system_tools_dnf() {
  command_exists node || install_dnf_package nodejs
  command_exists npm || install_dnf_package npm
  command_exists clangd || install_dnf_package clang-tools-extra
  command_exists lua-language-server || install_dnf_package lua-language-server
  command_exists tree-sitter || install_dnf_package tree-sitter-cli
  install_latex_system_tools_dnf
}

install_nvim_system_tools_brew() {
  command_exists node || install_brew_package node
  command_exists npm || install_brew_package node
  command_exists tree-sitter || install_brew_package tree-sitter
  command_exists lua-language-server || install_brew_package lua-language-server
  install_latex_system_tools_brew

  if ! command_exists clangd; then
    install_brew_package llvm
    local llvm_prefix
    if llvm_prefix="$(brew --prefix llvm 2>/dev/null)" && [[ -x "${llvm_prefix}/bin/clangd" ]]; then
      run mkdir -p "${HOME_DIR}/.local/bin"
      run ln -sf "${llvm_prefix}/bin/clangd" "${HOME_DIR}/.local/bin/clangd"
      printf 'linked: %s -> %s\n' "${HOME_DIR}/.local/bin/clangd" "${llvm_prefix}/bin/clangd"
    fi
  fi
}

install_nvim_system_tools_winget() {
  command_exists node || install_winget_package OpenJS.NodeJS.LTS
  command_exists npm || install_winget_package OpenJS.NodeJS.LTS
  command_exists clangd || install_winget_package LLVM.LLVM
  command_exists lua-language-server || install_winget_package LuaLS.lua-language-server
  install_latex_system_tools_winget
}

install_nvim_system_tools() {
  if command_exists apt-get; then
    install_nvim_system_tools_apt
    return 0
  fi

  if command_exists pacman; then
    install_nvim_system_tools_pacman
    return 0
  fi

  if command_exists dnf; then
    install_nvim_system_tools_dnf
    return 0
  fi

  if command_exists brew; then
    install_nvim_system_tools_brew
    return 0
  fi

  if is_windows_posix && command_exists winget; then
    install_nvim_system_tools_winget
    return 0
  fi

  printf 'Neovim system tool install skipped: apt-get, pacman, dnf, brew, or winget is required\n' >&2
}

install_npm_package() {
  local command_name="$1"
  local package_name="$2"

  if command_exists "${command_name}"; then
    printf 'already installed: %s\n' "${command_name}"
    return 0
  fi

  install_npm_global_package "${package_name}"
}

install_npm_global_package() {
  local package_name="$1"

  if ! command_exists npm; then
    printf 'npm package install skipped: npm is required for %s\n' "${package_name}" >&2
    return 0
  fi

  if run npm install -g "${package_name}"; then
    hash -r 2>/dev/null || true
    printf 'installed npm package: %s\n' "${package_name}"
  else
    printf 'npm package install skipped: %s\n' "${package_name}" >&2
  fi
}

tree_sitter_cli_version() {
  tree-sitter --version 2>/dev/null | awk '{print $2}'
}

tree_sitter_cli_is_current() {
  local version

  if ! command_exists tree-sitter; then
    return 1
  fi

  version="$(tree_sitter_cli_version)"
  [[ -n "${version}" ]] && version_at_least "${version}" "0.25.0"
}

install_nvim_npm_tools() {
  install_npm_package pyright-langserver pyright
  install_npm_package typescript-language-server typescript-language-server
  install_npm_package tsc typescript
  if command_exists vscode-css-language-server &&
     command_exists vscode-html-language-server &&
     command_exists vscode-json-language-server; then
    printf 'already installed: vscode-langservers-extracted\n'
  else
    install_npm_package vscode-html-language-server vscode-langservers-extracted
  fi

  if tree_sitter_cli_is_current; then
    printf 'already installed: tree-sitter %s\n' "$(tree_sitter_cli_version)"
  else
    install_npm_global_package tree-sitter-cli
  fi
}

lua_language_server_asset_suffix() {
  local os_name arch_name
  os_name="$(uname -s)"
  arch_name="$(uname -m)"

  case "${os_name}:${arch_name}" in
    Linux:x86_64|Linux:amd64)
      printf 'linux-x64.tar.gz'
      ;;
    Linux:aarch64|Linux:arm64)
      printf 'linux-arm64.tar.gz'
      ;;
    Darwin:x86_64|Darwin:amd64)
      printf 'darwin-x64.tar.gz'
      ;;
    Darwin:aarch64|Darwin:arm64)
      printf 'darwin-arm64.tar.gz'
      ;;
    *)
      return 1
      ;;
  esac
}

install_lua_language_server_binary() {
  if command_exists lua-language-server; then
    printf 'already installed: lua-language-server\n'
    return 0
  fi

  if is_windows_posix; then
    printf 'lua-language-server install skipped: use winget or install the Windows release manually\n' >&2
    return 0
  fi

  if ! command_exists curl || ! command_exists tar; then
    printf 'lua-language-server install skipped: curl and tar are required\n' >&2
    return 0
  fi

  local suffix version archive_url tmpdir archive install_dir current_dir
  if ! suffix="$(lua_language_server_asset_suffix)"; then
    printf 'lua-language-server install skipped: unsupported platform %s/%s\n' "$(uname -s)" "$(uname -m)" >&2
    return 0
  fi

  if [[ "${DRY_RUN}" -eq 1 ]]; then
    version="\$(curl GitHub latest release)"
    tmpdir="/tmp/dotfiles-lua-language-server"
  else
    version="$(curl -LsSf https://api.github.com/repos/LuaLS/lua-language-server/releases/latest |
      sed -n 's/.*"tag_name": "\(.*\)".*/\1/p' |
      head -n 1)"
    tmpdir="$(mktemp -d)"
  fi

  if [[ -z "${version}" ]]; then
    printf 'lua-language-server install skipped: failed to resolve latest release\n' >&2
    return 0
  fi

  archive_url="https://github.com/LuaLS/lua-language-server/releases/download/${version}/lua-language-server-${version}-${suffix}"
  archive="${tmpdir}/lua-language-server.tar.gz"
  install_dir="${HOME_DIR}/.local/share/lua-language-server"
  current_dir="${install_dir}.current"

  if [[ -d "${current_dir}" || -L "${current_dir}" ]]; then
    printf 'lua-language-server install skipped: %s already exists\n' "${current_dir}" >&2
    return 0
  fi

  if run curl -LsSf "${archive_url}" -o "${archive}" &&
     run mkdir -p "${install_dir}" "${HOME_DIR}/.local/bin" &&
     run tar -xzf "${archive}" -C "${install_dir}" &&
     run ln -sfn "${install_dir}" "${current_dir}" &&
     run ln -sf "${current_dir}/bin/lua-language-server" "${HOME_DIR}/.local/bin/lua-language-server"; then
    printf 'installed: lua-language-server %s\n' "${version}"
  else
    printf 'lua-language-server install skipped: prebuilt install failed\n' >&2
  fi
}

install_tinymist_binary() {
  if command_exists tinymist; then
    printf 'already installed: tinymist\n'
    return 0
  fi

  if ! command_exists curl; then
    printf 'tinymist install skipped: curl is required\n' >&2
    return 0
  fi

  local installer="/tmp/tinymist-installer.sh"
  local url="https://github.com/Myriad-Dreamin/tinymist/releases/download/v0.15.2/tinymist-installer.sh"

  if run curl --proto '=https' --tlsv1.2 -LsSf "${url}" -o "${installer}" &&
     run env TINYMIST_NO_MODIFY_PATH=1 sh "${installer}" --quiet; then
    printf 'installed: tinymist\n'
  else
    printf 'tinymist install skipped: prebuilt installer failed\n' >&2
  fi
}

texlab_asset_suffix() {
  local os_name arch_name
  os_name="$(uname -s)"
  arch_name="$(uname -m)"

  case "${os_name}:${arch_name}" in
    Linux:x86_64|Linux:amd64)
      printf 'x86_64-linux.tar.gz'
      ;;
    Linux:aarch64|Linux:arm64)
      printf 'aarch64-linux.tar.gz'
      ;;
    Darwin:x86_64|Darwin:amd64)
      printf 'x86_64-macos.tar.gz'
      ;;
    Darwin:aarch64|Darwin:arm64)
      printf 'aarch64-macos.tar.gz'
      ;;
    CYGWIN*:x86_64|MINGW*:x86_64|MSYS*:x86_64)
      printf 'x86_64-windows.zip'
      ;;
    CYGWIN*:aarch64|MINGW*:aarch64|MSYS*:aarch64|CYGWIN*:arm64|MINGW*:arm64|MSYS*:arm64)
      printf 'aarch64-windows.zip'
      ;;
    CYGWIN*:i686|MINGW*:i686|MSYS*:i686)
      printf 'i686-windows.zip'
      ;;
    *)
      return 1
      ;;
  esac
}

extract_texlab_archive() {
  local archive="$1"
  local install_dir="$2"

  if [[ "${archive}" == *.zip ]]; then
    if command_exists unzip; then
      run unzip -q "${archive}" -d "${install_dir}"
      return $?
    fi

    if command_exists powershell.exe; then
      run powershell.exe -NoProfile -Command "Expand-Archive -LiteralPath '${archive}' -DestinationPath '${install_dir}' -Force"
      return $?
    fi

    printf 'texlab install skipped: unzip or powershell.exe is required for Windows archives\n' >&2
    return 1
  fi

  run tar -xzf "${archive}" -C "${install_dir}"
}

install_texlab_binary() {
  if command_exists texlab; then
    printf 'already installed: texlab\n'
    return 0
  fi

  if ! command_exists curl; then
    printf 'texlab install skipped: curl is required\n' >&2
    return 0
  fi

  if ! command_exists tar && ! is_windows_posix; then
    printf 'texlab install skipped: tar is required\n' >&2
    return 0
  fi

  local suffix version archive_url tmpdir archive install_root install_dir binary_name binary_path
  if ! suffix="$(texlab_asset_suffix)"; then
    printf 'texlab install skipped: unsupported platform %s/%s\n' "$(uname -s)" "$(uname -m)" >&2
    return 0
  fi

  if [[ "${DRY_RUN}" -eq 1 ]]; then
    version="\$(curl GitHub latest release)"
    tmpdir="/tmp/dotfiles-texlab"
  else
    version="$(curl -LsSf https://api.github.com/repos/latex-lsp/texlab/releases/latest |
      sed -n 's/.*"tag_name": "\(.*\)".*/\1/p' |
      head -n 1)"
    tmpdir="$(mktemp -d)"
  fi

  if [[ -z "${version}" ]]; then
    printf 'texlab install skipped: failed to resolve latest release\n' >&2
    return 0
  fi

  archive_url="https://github.com/latex-lsp/texlab/releases/download/${version}/texlab-${suffix}"
  archive="${tmpdir}/texlab.${suffix##*.}"
  install_root="${HOME_DIR}/.local/share/texlab"
  install_dir="${install_root}/${version}"
  binary_name="texlab"

  if [[ "${suffix}" == *.zip ]]; then
    binary_name="texlab.exe"
  fi

  if run mkdir -p "${install_dir}" "${HOME_DIR}/.local/bin" &&
     run curl -LsSf "${archive_url}" -o "${archive}" &&
     extract_texlab_archive "${archive}" "${install_dir}"; then
    if [[ "${DRY_RUN}" -eq 1 ]]; then
      binary_path="${install_dir}/${binary_name}"
    else
      binary_path="$(find "${install_dir}" -type f -name "${binary_name}" | head -n 1)"
    fi

    if [[ -n "${binary_path}" ]]; then
      if [[ "${binary_name}" == *.exe ]]; then
        run cp "${binary_path}" "${HOME_DIR}/.local/bin/${binary_name}"
        printf 'installed: texlab %s\n' "${version}"
      else
        run chmod +x "${binary_path}"
        run ln -sf "${binary_path}" "${HOME_DIR}/.local/bin/texlab"
        printf 'installed: texlab %s\n' "${version}"
      fi
    else
      printf 'texlab install skipped: extracted binary not found\n' >&2
    fi
  else
    printf 'texlab install skipped: prebuilt install failed\n' >&2
  fi
}

report_nvim_tool_status() {
  local missing=()
  local command_name
  local required_commands=(
    clangd
    latexmk
    lua-language-server
    lualatex
    pyright-langserver
    texlab
    tinymist
    tree-sitter
    tsc
    typescript-language-server
    vscode-css-language-server
    vscode-html-language-server
    vscode-json-language-server
  )

  for command_name in "${required_commands[@]}"; do
    if ! command_exists "${command_name}"; then
      missing+=("${command_name}")
    fi
  done

  if command_exists tree-sitter && ! tree_sitter_cli_is_current; then
    missing+=("tree-sitter>=0.25.0")
  fi

  if [[ "${#missing[@]}" -eq 0 ]]; then
    printf 'Neovim tool check: all configured tools are installed\n'
  else
    printf 'Neovim tool check: missing: %s\n' "${missing[*]}" >&2
  fi
}

install_treesitter_parsers() {
  local nvim_config="${HOME_DIR}/.config/nvim/init.lua"

  if ! command_exists nvim; then
    printf 'Treesitter parser install skipped: nvim is required\n' >&2
    return 0
  fi

  if [[ ! -e "${nvim_config}" && ! -L "${nvim_config}" ]]; then
    printf 'Treesitter parser install skipped: %s is not linked yet\n' "${nvim_config}" >&2
    return 0
  fi

  if run nvim --headless "+TSInstallConfigured!" +qa; then
    printf 'installed/verified configured Treesitter parsers\n'
  else
    printf 'Treesitter parser install skipped: nvim parser install failed\n' >&2
  fi
}

install_nvim_tools() {
  printf 'checking Neovim LSP/Treesitter tools\n'
  install_nvim_system_tools
  install_nvim_npm_tools
  install_lua_language_server_binary
  install_tinymist_binary
  install_texlab_binary
  install_treesitter_parsers
  report_nvim_tool_status
}

tmux_plugin_root() {
  if [[ "${DRY_RUN}" -eq 0 ]] && command_exists tmux; then
    local env_line plugin_root
    if env_line="$(tmux start-server \; show-environment -g TMUX_PLUGIN_MANAGER_PATH 2>/dev/null)"; then
      plugin_root="${env_line#TMUX_PLUGIN_MANAGER_PATH=}"
      plugin_root="${plugin_root/#\~/${HOME_DIR}}"
      plugin_root="${plugin_root/#\$HOME/${HOME_DIR}}"
      printf '%s\n' "${plugin_root%/}"
      return 0
    fi
  fi

  local xdg_tmux_dir="${XDG_CONFIG_HOME:-${HOME_DIR}/.config}/tmux"
  if [[ -f "${xdg_tmux_dir}/tmux.conf" ]]; then
    printf '%s\n' "${xdg_tmux_dir}/plugins"
  else
    printf '%s\n' "${HOME_DIR}/.tmux/plugins"
  fi
}

install_tpm() {
  local tpm_dir="${HOME_DIR}/.tmux/plugins/tpm"

  if [[ -d "${tpm_dir}/.git" ]]; then
    printf 'already installed: %s\n' "${tpm_dir}"
    return 0
  fi

  if [[ -e "${tpm_dir}" ]]; then
    printf 'tmux plugin manager skipped: %s exists but is not a git checkout\n' "${tpm_dir}" >&2
    return 0
  fi

  if [[ "${DRY_RUN}" -eq 0 ]] && ! command_exists git; then
    printf 'tmux plugin manager skipped: git is required\n' >&2
    return 0
  fi

  run mkdir -p "$(dirname "${tpm_dir}")"
  run git clone https://github.com/tmux-plugins/tpm "${tpm_dir}"
  printf 'installed tmux plugin manager: %s\n' "${tpm_dir}"
}

install_tmux_cpu_mem_deps() {
  local plugin_root="$1"
  local plugin_dir="${plugin_root}/tmux-cpu-mem-monitor"
  local venv_dir="${plugin_dir}/venv"

  if [[ "${DRY_RUN}" -eq 1 ]]; then
    run python3 -m venv "${venv_dir}"
    run "${venv_dir}/bin/python" -m pip install -r "${plugin_dir}/requirements.txt"
    return 0
  fi

  if [[ ! -d "${plugin_dir}" ]]; then
    return 0
  fi

  if ! command_exists python3; then
    printf 'tmux cpu/mem plugin setup skipped: python3 is required\n' >&2
    return 0
  fi

  if [[ -x "${venv_dir}/bin/python" ]] && "${venv_dir}/bin/python" -c 'import psutil' >/dev/null 2>&1; then
    printf 'already installed: %s Python deps\n' "${plugin_dir}"
    return 0
  fi

  if ! run python3 -m venv "${venv_dir}"; then
    printf 'tmux cpu/mem plugin setup skipped: python3-venv is required\n' >&2
    return 0
  fi

  if ! run "${venv_dir}/bin/python" -m pip install -r "${plugin_dir}/requirements.txt"; then
    printf 'tmux cpu/mem plugin setup skipped: failed to install Python deps\n' >&2
    return 0
  fi

  printf 'installed tmux cpu/mem Python deps: %s\n' "${plugin_dir}"
}

install_tmux_plugins() {
  local tpm_dir="${HOME_DIR}/.tmux/plugins/tpm"

  install_tpm

  if [[ "${DRY_RUN}" -eq 0 ]] && ! command_exists tmux; then
    printf 'tmux plugins skipped: tmux is required\n' >&2
    return 0
  fi

  if [[ "${DRY_RUN}" -eq 0 ]] && [[ ! -x "${tpm_dir}/bin/install_plugins" ]]; then
    printf 'tmux plugins skipped: TPM installer not found at %s\n' "${tpm_dir}/bin/install_plugins" >&2
    return 0
  fi

  run tmux start-server \; source-file "${HOME_DIR}/.config/tmux/tmux.conf"
  run "${tpm_dir}/bin/install_plugins"
  install_tmux_cpu_mem_deps "$(tmux_plugin_root)"
  run tmux source-file "${HOME_DIR}/.config/tmux/tmux.conf"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)
      DRY_RUN=1
      ;;
    --skip-nvim-tools)
      SKIP_NVIM_TOOLS=1
      ;;
    --only-nvim-tools)
      ONLY_NVIM_TOOLS=1
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      printf 'Unknown option: %s\n\n' "$1" >&2
      usage >&2
      exit 1
      ;;
  esac
  shift
done

if [[ "${SKIP_NVIM_TOOLS}" -eq 1 && "${ONLY_NVIM_TOOLS}" -eq 1 ]]; then
  printf 'Cannot combine --skip-nvim-tools and --only-nvim-tools\n' >&2
  exit 1
fi

if [[ "${ONLY_NVIM_TOOLS}" -eq 1 ]]; then
  install_neovim
  install_nvim_tools
  printf 'done\n'
  exit 0
fi

managed_paths=(
  ".zshrc"
  ".XCompose"
  ".local/bin/dotfiles-fastfetch"
  ".config/alacritty"
  ".config/fastfetch"
  ".config/fontconfig"
  ".config/niri"
  ".config/nvim"
  ".config/tmux/tmux.conf"
  ".config/tmux/scripts"
)

for relative_path in "${managed_paths[@]}"; do
  link_path "${DOTFILES_DIR}/${relative_path}" "${HOME_DIR}/${relative_path}"
done

# Keep ~/.tmux.conf linked for compatibility with older tmux versions.
link_path "${HOME_DIR}/.config/tmux/tmux.conf" "${HOME_DIR}/.tmux.conf"

# Keep personal compose sequences in a local untracked file.
ensure_file "${HOME_DIR}/.XCompose.local"

install_figlet
install_neovim
if [[ "${SKIP_NVIM_TOOLS}" -eq 0 ]]; then
  install_nvim_tools
else
  printf 'Neovim tool install skipped by --skip-nvim-tools\n'
fi
install_tmux_plugins

if [[ -d "${BACKUP_DIR}" ]]; then
  printf 'backup directory: %s\n' "${BACKUP_DIR}"
fi

printf 'done\n'
