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
- Status line: identity only (`USER | HOST`, filled in by chezmoi when it renders the config), with no CPU, MEM or battery segments, and the status scripts are not installed. Each `#(...)` refresh spawns a process, which costs tens of milliseconds of CPU on Windows (more with endpoint security software), and psmux has no built-in metric variables. Every way of keeping those segments meant either that recurring cost or a resident helper process, so they were left out.

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
