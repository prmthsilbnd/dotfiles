#!/usr/bin/env sh
set -eu

usage() {
  cat <<'EOF'
Usage: ./bootstrap.sh [--apply] [--force] [--skip-tmux-setup]

Install chezmoi into ~/.local/bin when needed, configure chezmoi to use this
repo as its source directory, and preview the pending dotfile changes.

Options:
  --apply            Apply after showing the diff.
  --force            Pass --force to chezmoi apply. Implies --apply.
  --skip-tmux-setup  Skip the tmux after-script for this apply.
  -h, --help         Show this help.
EOF
}

apply=0
force=0
skip_tmux_setup=0

while [ "$#" -gt 0 ]; do
  case "$1" in
    --apply)
      apply=1
      ;;
    --force)
      apply=1
      force=1
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
