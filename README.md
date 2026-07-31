# Dotfiles

Personal dotfiles managed with [chezmoi](https://www.chezmoi.io/) from the
source repo at `~/dotfiles`.

This repo manages home-directory configuration only. System packages, services,
and `/etc` changes are documented but are not applied automatically.

## Quick Start

On a machine with this repo already cloned, run:

```bash
./bootstrap.sh
```

Review the diff, then apply:

```bash
./bootstrap.sh --apply
```

On machines that still have the old symlink-based install, use `--force` after
reviewing the diff:

```bash
./bootstrap.sh --force
```

`bootstrap.sh` installs the upstream chezmoi binary into `~/.local/bin` if
chezmoi is missing, installs upstream Neovim into `~/.local/opt` if `nvim` is
missing or older than 0.12, writes `~/.config/chezmoi/chezmoi.toml`, and runs
`chezmoi diff`.

If bootstrap installs Neovim but the current shell still opens an older system
`nvim`, start a new shell or run:

```bash
export PATH="$HOME/.local/bin:$PATH"
rehash 2>/dev/null || true
hash -r 2>/dev/null || true
```

To skip tmux plugin setup during apply:

```bash
./bootstrap.sh --force --skip-tmux-setup
```

To skip the Neovim version check/install:

```bash
./bootstrap.sh --skip-nvim
```

Update later:

```bash
chezmoi update
```

When working directly inside this repo, these forms avoid relying on global
chezmoi state:

```bash
chezmoi --source "$PWD" diff
chezmoi --source "$PWD" apply
```

## Managed Paths

Chezmoi source paths in this repo map to these home paths:

- `dot_zshrc` -> `~/.zshrc`
- `dot_XCompose` -> `~/.XCompose`
- `private_dot_local/bin/executable_dotfiles-fastfetch` -> `~/.local/bin/dotfiles-fastfetch`
- `private_dot_config/alacritty` -> `~/.config/alacritty`
- `private_dot_config/kitty` -> `~/.config/kitty`
- `private_dot_config/fastfetch` -> `~/.config/fastfetch`
- `private_dot_config/fontconfig` -> `~/.config/fontconfig`
- `private_dot_config/matugen` -> `~/.config/matugen`
- `private_dot_config/niri` -> `~/.config/niri`
- `private_dot_config/nvim` -> `~/.config/nvim`
- `private_dot_config/tmux` -> `~/.config/tmux`

The `private_` prefix preserves `0700` permissions on `~/.config` and
`~/.local`.

Repo-only files such as this README, `bootstrap.sh`, `docs/`, and `.gitignore`
are excluded from the target home directory by `.chezmoiignore`.

## Components

- Zsh: prompt, aliases, editor defaults, plugin loading, and fastfetch startup.
- Fastfetch: wrapper that composes the OS logo with a slanted hostname banner.
  See [docs/fastfetch.md](docs/fastfetch.md).
- Tmux: top status line, CPU/MEM scripts, TPM plugin setup, prefix-based pane
  movement. See [docs/tmux.md](docs/tmux.md).
- Neovim: Lua config, plugins, language helpers, `AvengeMedia/base46` theme engine, and DMS matugen integration with headless fallback.
- Matugen: Neovim color & lualine templates for Dank Material Shell (DMS) dynamic accent tinting.
- Kitty: main terminal emulator settings and local theme.
- Alacritty: secondary terminal settings and local theme.
- Niri: compositor config and Dank Material Shell modules/profiles.
- Fontconfig: Korean font fallback.
- XCompose: compose key entries, with local extension support.

## Local Files

Keep machine-specific and private data out of git:

- `~/.zshrc.local` for local shell overrides.
- `~/.zprofile` or `~/.zprofile.local` for machine-specific login environment.
- `~/.XCompose.local` for private compose entries.

These files are intentionally unmanaged by chezmoi in this repo and should
remain local-only.

## User Setup Scripts

`run_onchange_after_10-tmux-setup.sh` runs after `chezmoi apply` when the script
changes and handles user-level tmux setup:

- Install or update TPM under `~/.tmux/plugins/tpm`.
- Run the TPM plugin installer.
- Create or refresh the tmux CPU/MEM plugin Python virtual environment when the
  plugin is present.

Set `DOTFILES_SKIP_TMUX_SETUP=1` to skip this script for a single apply.

Package installation and service setup are not automated. HomePod/Bonjour audio
setup notes live in [docs/homepod.md](docs/homepod.md).

## Dependencies

Required for dotfile application:

- `chezmoi`

Optional integrations:

- `zsh` for the main shell config.
- `fastfetch` for startup system info.
- `figlet` for the fastfetch hostname banner. The wrapper falls back to plain
  text when `figlet` is missing.
- `nvim` 0.12+ for the Neovim config and native package management. On Linux
  x86_64 and arm64, `bootstrap.sh` installs the upstream tarball under
  `~/.local/opt` when the available `nvim` is too old.
- `tmux` and `git` for TPM plugin installation.
- `python3` and Python venv support for the tmux CPU/MEM plugin dependency
  setup.

Optional Neovim developer tools are installed outside chezmoi:

- Node-based LSPs through `npm`: Pyright, TypeScript, and VS Code HTML/CSS/JSON
  language servers.
- LaTeX editing tools: `texlab`, `latexmk`, LuaLaTeX, and common TeX Live
  package collections.
- Treesitter CLI and the configured Treesitter parsers.
- `tinymist` for Typst.
- `lua-language-server`.

## Maintenance Checks

Run these before committing broad config changes:

```bash
git diff --check
sh -n bootstrap.sh
bash -n run_onchange_after_10-tmux-setup.sh
zsh -n dot_zshrc
zsh -n private_dot_local/bin/executable_dotfiles-fastfetch
bash -n private_dot_config/tmux/scripts/executable_status-metric
bash -n private_dot_config/tmux/scripts/executable_status-battery
bash -n private_dot_config/tmux/scripts/executable_status-identity
tmux source-file -n private_dot_config/tmux/tmux.conf
chezmoi --source "$PWD" diff
chezmoi --source "$PWD" apply --dry-run
```

Fastfetch cache check:

```bash
~/.local/bin/dotfiles-fastfetch --refresh-cache
```

## Adding Another Dotfile

1. Add the file or directory using chezmoi source naming.
2. Update `.gitignore` so the new source path is explicitly unignored.
3. Run `chezmoi --source "$PWD" diff`.
4. Document the component here if it affects setup or maintenance.

Common source names:

- `~/.example` -> `dot_example`
- `~/.config/example/config.toml` -> `private_dot_config/example/config.toml`
- `~/.local/bin/example` -> `private_dot_local/bin/example`
