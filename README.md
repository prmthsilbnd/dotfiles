# Dotfiles

Personal dotfiles managed from a single repo under `~/dotfiles`.

The installer symlinks tracked files into `$HOME`, backs up existing targets, and installs a few optional runtime dependencies when the local machine supports them.

## Quick Start

Preview the install:

```bash
./install.sh --dry-run
```

Apply it:

```bash
./install.sh
```

Skip Neovim developer tool installation:

```bash
./install.sh --skip-nvim-tools
```

Run only the Neovim developer tool bootstrap:

```bash
./install.sh --only-nvim-tools
```

Existing files are moved to:

```text
~/.dotfiles-backups/<timestamp>/
```

## Managed Paths

`install.sh` links these paths into `$HOME`:

- `.zshrc`
- `.XCompose`
- `.local/bin/dotfiles-fastfetch`
- `.config/alacritty`
- `.config/fastfetch`
- `.config/fontconfig`
- `.config/niri`
- `.config/nvim`
- `.config/tmux/tmux.conf`
- `.config/tmux/scripts`

It also links `~/.tmux.conf` to `~/.config/tmux/tmux.conf` for compatibility with older tmux setups.

## Components

- Zsh: prompt, aliases, editor defaults, plugin loading, and fastfetch startup.
- Fastfetch: wrapper that composes the OS logo with a slanted hostname banner. See [docs/fastfetch.md](docs/fastfetch.md).
- Tmux: top status line, CPU/MEM scripts, TPM plugin setup, prefix-based pane movement. See [docs/tmux.md](docs/tmux.md).
- Neovim: Lua config, plugins, language helpers, and pack lockfile.
- Alacritty: terminal settings and local theme.
- Niri: compositor config and Dank Material Shell modules/profiles.
- Fontconfig: Korean font fallback.
- XCompose: compose key entries, with local extension support.

## Local Files

Keep machine-specific and private data out of git:

- `~/.zshrc.local` for local shell overrides.
- `~/.zprofile` or `~/.zprofile.local` for machine-specific login environment.
- `~/.XCompose.local` for private compose entries.

The installer creates `~/.XCompose.local` when it is missing. `~/.zprofile` is intentionally not managed.

## Dependencies

Required basics:

- `bash`
- `ln`, `mv`, `mkdir`, `readlink`

Optional integrations:

- `zsh` for the main shell config.
- `fastfetch` for startup system info.
- `figlet` for the fastfetch hostname banner.
- `nvim` 0.12+ for the Neovim config and native package management.
- `tmux` and `git` for TPM plugin installation.
- `python3` and `python3-venv` for the tmux CPU/MEM plugin dependency setup.

`install.sh` attempts to install `figlet` through `apt-get`, `pacman`, or `brew` when available.
It also ensures Neovim 0.12+ is available. If the system package manager cannot provide a new enough Neovim, Linux x86_64 and arm64 hosts use the official Neovim tarball under `/opt/nvim-linux-<arch>` with `/usr/local/bin/nvim` pointing to it. Existing distro packages such as `/usr/bin/nvim` are left installed.

It also attempts a best-effort Neovim developer tool bootstrap unless `--skip-nvim-tools` is passed:

- System packages through `apt-get`, `pacman`, `dnf`, `brew`, or `winget` where available.
- Node-based LSPs through `npm`: Pyright, TypeScript, and VS Code HTML/CSS/JSON language servers.
- LaTeX editing tools: `texlab`, `latexmk`, LuaLaTeX, and common TeX Live package collections.
- Treesitter CLI through the system package manager or npm.
- Configured Treesitter parsers through headless Neovim when `nvim` and this config are available.
- `tinymist` from the official prebuilt GitHub release installer.
- `lua-language-server` from OS packages where available, with a Linux/macOS prebuilt GitHub release fallback.

## Maintenance Checks

Run these before committing broad config changes:

```bash
git diff --check
bash -n install.sh
zsh -n .zshrc
zsh -n .local/bin/dotfiles-fastfetch
bash -n .config/tmux/scripts/status-metric
bash -n .config/tmux/scripts/status-battery
bash -n .config/tmux/scripts/status-identity
tmux source-file -n .config/tmux/tmux.conf
./install.sh --dry-run
```

Fastfetch cache check:

```bash
~/.local/bin/dotfiles-fastfetch --refresh-cache
```

## Adding Another Dotfile

1. Add the file or directory to this repo using the same path it should have under `$HOME`.
2. Add the path to `managed_paths` in `install.sh`.
3. Update `.gitignore` so the path is explicitly unignored.
4. Document the new component in this README if it affects setup or maintenance.
5. Run `./install.sh --dry-run`.
