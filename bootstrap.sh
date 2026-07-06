#!/usr/bin/env sh
set -eu

usage() {
  cat <<'EOF'
Usage: ./bootstrap.sh [--apply] [--force] [--skip-nvim] [--skip-tmux-setup]

Install chezmoi and Neovim into user-local paths when needed, configure
chezmoi to use this repo as its source directory, and preview the pending
dotfile changes.

Options:
  --apply            Apply after showing the diff.
  --force            Pass --force to chezmoi apply. Implies --apply.
  --skip-nvim        Skip the Neovim version check/install.
  --skip-tmux-setup  Skip the tmux after-script for this apply.
  -h, --help         Show this help.
EOF
}

apply=0
force=0
skip_nvim=0
skip_tmux_setup=0
local_bin_note=0

while [ "$#" -gt 0 ]; do
  case "$1" in
    --apply)
      apply=1
      ;;
    --force)
      apply=1
      force=1
      ;;
    --skip-nvim|--skip-neovim)
      skip_nvim=1
      ;;
    --skip-tmux-setup)
      skip_tmux_setup=1
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      printf 'bootstrap: unknown option: %s\n\n' "$1" >&2
      usage >&2
      exit 1
      ;;
  esac
  shift
done

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

version_at_least() {
  current=${1#v}
  required=${2#v}
  current=${current%%[-+~]*}
  required=${required%%[-+~]*}

  old_ifs=$IFS
  IFS=.
  set -- $current
  current_major=${1:-0}
  current_minor=${2:-0}
  current_patch=${3:-0}
  set -- $required
  required_major=${1:-0}
  required_minor=${2:-0}
  required_patch=${3:-0}
  IFS=$old_ifs

  if [ "$current_major" -ne "$required_major" ]; then
    [ "$current_major" -gt "$required_major" ]
    return
  fi
  if [ "$current_minor" -ne "$required_minor" ]; then
    [ "$current_minor" -gt "$required_minor" ]
    return
  fi
  [ "$current_patch" -ge "$required_patch" ]
}

download_file() {
  url=$1
  output_path=$2

  if command_exists curl; then
    curl -fL "$url" -o "$output_path"
    return
  fi

  if command_exists wget; then
    wget -O "$output_path" "$url"
    return
  fi

  return 1
}

script_dir() {
  command_path=$0
  case "$command_path" in
    */*) ;;
    *)
      if found_path=$(command -v -- "$command_path" 2>/dev/null); then
        command_path=$found_path
      fi
      ;;
  esac

  dir=$(dirname -- "$command_path")
  if cd -- "$dir" 2>/dev/null; then
    pwd -P
  else
    return 1
  fi
}

repo=${DOTFILES_REPO:-}
if [ -z "$repo" ]; then
  repo=$(script_dir) || {
    printf 'bootstrap: could not determine repo directory\n' >&2
    exit 1
  }
fi

if [ ! -d "$repo/.git" ]; then
  printf 'bootstrap: expected a git checkout at %s\n' "$repo" >&2
  printf 'bootstrap: clone the repo first, or set DOTFILES_REPO=/path/to/repo\n' >&2
  exit 1
fi

bin_dir=${DOTFILES_BIN_DIR:-"$HOME/.local/bin"}
chezmoi_config_dir=${XDG_CONFIG_HOME:-"$HOME/.config"}/chezmoi
chezmoi_config=$chezmoi_config_dir/chezmoi.toml

mkdir -p -- "$bin_dir" "$chezmoi_config_dir"

case ":$PATH:" in
  *":$bin_dir:"*) ;;
  *) PATH=$bin_dir:$PATH ;;
esac
export PATH

if ! command_exists chezmoi; then
  if command_exists curl; then
    sh -c "$(curl -fsLS https://get.chezmoi.io)" -- -b "$bin_dir"
  elif command_exists wget; then
    sh -c "$(wget -qO- https://get.chezmoi.io)" -- -b "$bin_dir"
  else
    printf 'bootstrap: curl or wget is required to install chezmoi\n' >&2
    exit 1
  fi
fi

nvim_version() {
  if ! command_exists nvim; then
    return 1
  fi

  nvim --version | sed -n '1s/^NVIM v\([0-9][0-9.]*\).*/\1/p'
}

neovim_asset_name() {
  os_name=$(uname -s 2>/dev/null || printf unknown)
  machine=$(uname -m 2>/dev/null || printf unknown)

  case "$os_name:$machine" in
    Linux:x86_64|Linux:amd64)
      printf 'nvim-linux-x86_64'
      ;;
    Linux:aarch64|Linux:arm64)
      printf 'nvim-linux-arm64'
      ;;
    *)
      return 1
      ;;
  esac
}

ensure_neovim() {
  min_version=${DOTFILES_NVIM_MIN_VERSION:-0.12.0}
  installed_version=$(nvim_version || true)

  if [ -n "$installed_version" ] && version_at_least "$installed_version" "$min_version"; then
    printf 'bootstrap: nvim %s is already installed\n' "$installed_version"
    return 0
  fi

  asset=$(neovim_asset_name || true)
  if [ -z "$asset" ]; then
    printf 'bootstrap: Neovim install skipped: unsupported OS or architecture\n' >&2
    printf 'bootstrap: install nvim %s+ manually, or pass --skip-nvim\n' "$min_version" >&2
    return 0
  fi

  if ! command_exists tar; then
    printf 'bootstrap: Neovim install skipped: tar is required\n' >&2
    return 1
  fi

  opt_dir=${DOTFILES_OPT_DIR:-"$HOME/.local/opt"}
  target_dir=$opt_dir/$asset
  archive_url=https://github.com/neovim/neovim/releases/latest/download/$asset.tar.gz
  temp_dir=$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-neovim.XXXXXX")
  archive_path=$temp_dir/$asset.tar.gz

  cleanup_neovim_temp() {
    rm -rf -- "$temp_dir"
  }

  trap cleanup_neovim_temp EXIT HUP INT TERM

  printf 'bootstrap: installing upstream Neovim to %s\n' "$target_dir"
  download_file "$archive_url" "$archive_path"
  tar -xzf "$archive_path" -C "$temp_dir"

  mkdir -p -- "$opt_dir"
  rm -rf -- "$target_dir"
  mv -- "$temp_dir/$asset" "$target_dir"

  if [ -e "$bin_dir/nvim" ] || [ -L "$bin_dir/nvim" ]; then
    if [ -L "$bin_dir/nvim" ] || [ "${DOTFILES_OVERWRITE_LOCAL_NVIM:-0}" = "1" ]; then
      rm -f -- "$bin_dir/nvim"
    else
      printf 'bootstrap: not replacing non-symlink %s\n' "$bin_dir/nvim" >&2
      printf 'bootstrap: set DOTFILES_OVERWRITE_LOCAL_NVIM=1 to replace it\n' >&2
      return 0
    fi
  fi

  ln -s "$target_dir/bin/nvim" "$bin_dir/nvim"
  installed_version=$("$bin_dir/nvim" --version | sed -n '1s/^NVIM v\([0-9][0-9.]*\).*/\1/p')
  printf 'bootstrap: installed nvim %s\n' "${installed_version:-unknown}"
  local_bin_note=1

  cleanup_neovim_temp
  trap - EXIT HUP INT TERM
}

if [ "$skip_nvim" -eq 0 ]; then
  ensure_neovim
fi

printf 'sourceDir = "%s"\n' "$repo" > "$chezmoi_config"
printf 'bootstrap: wrote %s\n' "$chezmoi_config"
printf 'bootstrap: chezmoi source: %s\n' "$repo"

chezmoi diff

if [ "$apply" -eq 1 ]; then
  if [ "$skip_tmux_setup" -eq 1 ]; then
    export DOTFILES_SKIP_TMUX_SETUP=1
  fi

  if [ "$force" -eq 1 ]; then
    chezmoi apply --force
  else
    chezmoi apply
  fi
else
  cat <<'EOF'

Review the diff above, then apply with:
  ./bootstrap.sh --apply

For old symlink-based installs that prompt on replacements, use:
  ./bootstrap.sh --force
EOF
fi

if [ "$local_bin_note" -eq 1 ]; then
  cat <<EOF

Installed user-local tools under:
  $bin_dir

This script cannot update the PATH of your already-running shell. Open a new
shell, or run this now:
  export PATH="$bin_dir:\$PATH"
  hash -r 2>/dev/null || true
  rehash 2>/dev/null || true

Then verify:
  command -v nvim
  nvim --version
EOF
fi
