#!/usr/bin/env bash
set -euo pipefail

DOTFILES_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
HOME_DIR="${HOME:?HOME is not set}"
BACKUP_DIR="${HOME_DIR}/.dotfiles-backups/$(date +"%Y%m%d-%H%M%S")"
DRY_RUN=0

usage() {
  cat <<'EOF'
Usage: ./install.sh [--dry-run]

Symlink managed dotfiles from this repo into your home directory.
Existing files are moved to ~/.dotfiles-backups/<timestamp>/ before linking.
Tmux plugins are installed automatically when git and tmux are available.
Figlet is installed automatically when a supported package manager is available.
Neovim 0.12+ is installed automatically when possible.
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
install_tmux_plugins

if [[ -d "${BACKUP_DIR}" ]]; then
  printf 'backup directory: %s\n' "${BACKUP_DIR}"
fi

printf 'done\n'
