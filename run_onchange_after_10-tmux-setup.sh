#!/usr/bin/env bash
set -u

HOME_DIR="${HOME:?HOME is not set}"

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

warn() {
  printf 'dotfiles tmux setup: %s\n' "$*" >&2
}

tmux_plugin_root() {
  local env_line plugin_root xdg_tmux_dir

  if command_exists tmux; then
    if env_line="$(tmux start-server \; show-environment -g TMUX_PLUGIN_MANAGER_PATH 2>/dev/null)"; then
      plugin_root="${env_line#TMUX_PLUGIN_MANAGER_PATH=}"
      plugin_root="${plugin_root/#\~/${HOME_DIR}}"
      plugin_root="${plugin_root/#\$HOME/${HOME_DIR}}"
      printf '%s\n' "${plugin_root%/}"
      return 0
    fi
  fi

  xdg_tmux_dir="${XDG_CONFIG_HOME:-${HOME_DIR}/.config}/tmux"
  if [[ -f "${xdg_tmux_dir}/tmux.conf" ]]; then
    printf '%s\n' "${xdg_tmux_dir}/plugins"
  else
    printf '%s\n' "${HOME_DIR}/.tmux/plugins"
  fi
}

install_or_update_tpm() {
  local tpm_dir="${HOME_DIR}/.tmux/plugins/tpm"

  if ! command_exists git; then
    warn 'git is required to install or update TPM'
    return 0
  fi

  if [[ -d "${tpm_dir}/.git" ]]; then
    git -C "${tpm_dir}" pull --ff-only >/dev/null 2>&1 || warn "TPM update skipped for ${tpm_dir}"
    return 0
  fi

  if [[ -e "${tpm_dir}" ]]; then
    warn "${tpm_dir} exists but is not a git checkout"
    return 0
  fi

  mkdir -p "$(dirname "${tpm_dir}")" || {
    warn "could not create $(dirname "${tpm_dir}")"
    return 0
  }

  git clone https://github.com/tmux-plugins/tpm "${tpm_dir}" || warn "TPM install failed for ${tpm_dir}"
}

install_tmux_plugins() {
  local tpm_dir="${HOME_DIR}/.tmux/plugins/tpm"

  if ! command_exists tmux; then
    warn 'tmux is required to install plugins'
    return 0
  fi

  if [[ ! -x "${tpm_dir}/bin/install_plugins" ]]; then
    warn "TPM installer not found at ${tpm_dir}/bin/install_plugins"
    return 0
  fi

  tmux start-server \; source-file "${HOME_DIR}/.config/tmux/tmux.conf" >/dev/null 2>&1 || warn 'tmux config source failed before plugin install'
  "${tpm_dir}/bin/install_plugins" >/dev/null 2>&1 || warn 'tmux plugin install skipped or failed'
  tmux source-file "${HOME_DIR}/.config/tmux/tmux.conf" >/dev/null 2>&1 || warn 'tmux config source failed after plugin install'
}

install_tmux_cpu_mem_deps() {
  local plugin_root="$1"
  local plugin_dir=""
  local candidate
  local venv_dir

  for candidate in \
    "${plugin_root}/tmux-cpu-mem-monitor" \
    "${XDG_CONFIG_HOME:-${HOME_DIR}/.config}/tmux/plugins/tmux-cpu-mem-monitor" \
    "${HOME_DIR}/.tmux/plugins/tmux-cpu-mem-monitor"; do
    if [[ -f "${candidate}/requirements.txt" ]]; then
      plugin_dir="${candidate}"
      break
    fi
  done

  [[ -n "${plugin_dir}" ]] || return 0

  if ! command_exists python3; then
    warn 'python3 is required for tmux-cpu-mem-monitor dependencies'
    return 0
  fi

  venv_dir="${plugin_dir}/venv"
  if [[ -x "${venv_dir}/bin/python" ]] && "${venv_dir}/bin/python" -c 'import psutil' >/dev/null 2>&1; then
    return 0
  fi

  python3 -m venv "${venv_dir}" || {
    warn 'python3 venv setup failed for tmux-cpu-mem-monitor'
    return 0
  }

  "${venv_dir}/bin/python" -m pip install -r "${plugin_dir}/requirements.txt" >/dev/null 2>&1 || warn 'Python dependency install failed for tmux-cpu-mem-monitor'
}

if [[ "${DOTFILES_SKIP_TMUX_SETUP:-0}" == "1" ]]; then
  exit 0
fi

install_or_update_tpm
install_tmux_plugins
install_tmux_cpu_mem_deps "$(tmux_plugin_root)"
