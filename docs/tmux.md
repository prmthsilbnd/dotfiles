# Tmux

The tmux config lives at `.config/tmux/tmux.conf.tmpl`. Chezmoi materializes it at
`~/.config/tmux/tmux.conf`; `dot_tmux.conf` places a one-line `~/.tmux.conf` that
sources it, for compatibility with older tmux startup behavior (and, on Windows,
because psmux only looks at `~/.tmux.conf`, not the XDG path).

## Status Line

The status bar is a single top line:

- left: session name, separator, window list
- right: CPU, MEM, battery when available, separator, identity

CPU and MEM are rendered by:

- `.config/tmux/scripts/status-metric`

Battery is rendered by:

- `.config/tmux/scripts/status-battery`

The battery script reads Linux power-supply data, macOS `pmset`, or `acpi` when available. It prints nothing on hosts without battery information. The status line highlights it red below 20%.

Identity is rendered by:

- `.config/tmux/scripts/status-identity`

The CPU/MEM script uses `hendrikmi/tmux-cpu-mem-monitor` when the plugin is installed. If the plugin or Python dependency is missing, it prints a stable fallback such as `CPU --`.

## Plugins

Plugins are declared in `.config/tmux/tmux.conf` and installed through TPM:

- `tmux-plugins/tpm`
- `tmux-plugins/tmux-sensible`
- `hendrikmi/tmux-cpu-mem-monitor`

`install.sh` installs TPM when `git` is available, runs TPM's plugin installer when `tmux` is available, and sets up a Python virtual environment for the CPU/MEM plugin when `python3` is available.

## psmux (Windows)

On Windows, [psmux](https://github.com/psmux/psmux) stands in for tmux. It installs `psmux`, `pmux` and `tmux` executables, reads `~/.tmux.conf` (after `~/.psmux.conf` and `~/.psmuxrc`, which should not exist), and parses tmux config syntax. `tmux.conf.tmpl` branches on `.chezmoi.os` where psmux differs:

- Shell and terminal: panes start `pwsh`. `default-terminal` is `xterm-256color` rather than `screen-256color`, because the screen and tmux terminfo entries break Neovim splits under ConPTY (psmux issue #806).
- No TPM. psmux has its own plugin manager (ppm) and does not need tmux-sensible, so the Windows branch declares no plugins and sets the tmux-sensible options and bindings that matter directly: `display-time`, `focus-events`, `aggressive-resize`, `status-keys`, `prefix C-p`/`C-n`, and `prefix R` to reload. `.chezmoiignore.tmpl` skips `run_onchange_after_10-tmux-setup.sh` on Windows.
- No `detach-on-destroy`. psmux rejects it; every psmux session is its own server.
- Status line: `scripts/status-windows.ps1` replaces the three bash status scripts (`.chezmoiignore.tmpl` installs only the set for the current OS). It produces the same CPU, MEM, BAT and identity segments with the same colours and thresholds, from `GetSystemTimes`, `GlobalMemoryStatusEx` and `GetSystemPowerStatus`. An elevated (administrator) shell counts as root and shows the host alone in `colour220`.

How the Windows status line is wired, and why:

- psmux runs `#(...)` through PowerShell. A fresh `pwsh` per refresh costs about 0.6 s, plus about 1.5 s to compile the Win32 calls, every `status-interval`. So the script is a long-lived loop. The config starts it with `run -b`, and a named mutex keeps one copy per user, so other sessions and config reloads start copies that exit at once.
- The loop writes the finished status text to `~/.cache/psmux-status-right.txt` (write then rename), and `status-right` reads it with `#(cmd /c type ...)`, because `cmd` is cheap to spawn. The path in the config must use backslashes for `type`.
- It does not push the text with `psmux set -g @option`, because psmux pre-starts a standby `__warm__` server that runs the config and is renamed when a session claims it. A pushed option can then land in another session.
- The loop exits when no `psmux`, `tmux` or `pmux` process is left. Starting a new session brings it back.

Colours are chezmoi template variables (`{{ $gray_light }}` and so on) rather than tmux `name="value"` variables, because psmux cannot parse the latter.

The psmux docs list its options and differences from tmux: [configuration](https://github.com/psmux/psmux/blob/master/docs/configuration.md) and [compatibility](https://github.com/psmux/psmux/blob/master/docs/compatibility.md).

## Validation

Parse the config without applying it:

```bash
tmux source-file -n .config/tmux/tmux.conf
```

Apply it to the current tmux server:

```bash
tmux source-file .config/tmux/tmux.conf
```

Check helper scripts:

```bash
bash -n .config/tmux/scripts/status-metric
bash -n .config/tmux/scripts/status-battery
bash -n .config/tmux/scripts/status-identity
```
