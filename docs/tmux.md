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

On Windows, [psmux](https://github.com/psmux/psmux) stands in for tmux (it even
ships a `tmux.exe` shim of its own) and reads the same `tmux.conf` syntax, but its
CLI and runtime have gaps real tmux plugins assume are there. The config and
`private_dot_local/bin/executable_tmux` work around them:

- **No shebang execution.** psmux's `run-shell` and the `#(...)` status-line
  shell-out both invoke commands through PowerShell, which does not honor a
  script's `#!/usr/bin/env bash` line the way a POSIX shell does. Every script
  invocation in `tmux.conf.tmpl` -- the status-line scripts and the TPM bootstrap
  line -- is written as `bash <script>` rather than a bare path, on every OS
  (harmless on Linux/macOS, required on Windows).
- **`run`/`run-shell` lines inside a sourced config file don't execute at all.**
  psmux runs a `run-shell`/`run` command fine when it's issued directly as a
  top-level CLI command, but silently drops one that appears as a line inside a
  file loaded via `source-file` (which is how `tmux.conf`'s own
  `run 'bash ~/.tmux/plugins/tpm/tpm'` line is meant to fire, on session start
  and on config reload). That line is therefore inert on psmux -- TPM never
  gets triggered to source installed plugins by the config alone.
  `run_onchange_after_10-tmux-setup.sh` works around this by invoking
  `bash "${tpm_dir}/tpm"` directly as its own step after installing plugins,
  which is unaffected by the limitation since it's a plain subprocess call, not
  a config-file `run-shell` line. This runs on every OS; it's a harmless,
  idempotent no-op on hosts where the config line already did the job.
- **No tmux config-variable substitution.** Real tmux config files support
  `name="value"` lines and later `${name}` expansion; psmux does not implement
  this and leaves `${name}` unexpanded. `tmux.conf.tmpl` inlines the color hex
  values directly instead of defining them once and referencing them.
- **Missing `\;` command chaining and singular option aliases.** TPM's helper
  scripts call `tmux start-server \; show-environment -g ...` and
  `tmux show-option ...` (singular). psmux only implements `show-options`
  (plural) and doesn't support chaining multiple commands with `\;` in one
  invocation, so those calls fail outright with `unknown command`.
  `private_dot_local/bin/executable_tmux` is a wrapper installed at
  `~/.local/bin/tmux` (ahead of psmux's own `tmux` shim in `PATH`) that splits
  `\;`-chained commands into separate invocations, rewrites singular option
  commands to their plural form, and normalizes `show-environment -g NAME`
  output (psmux always appends a stray `PSMUX_TARGET_SESSION=...` line, and
  returns success with no output for an unset variable instead of failing).
  Windows-only: gated out of `chezmoi apply` on other hosts by
  `.chezmoiignore.tmpl`.
- **`default-shell`** is set conditionally in `tmux.conf.tmpl` (via
  `.chezmoi.os`) to Git Bash's path on Windows, since `/bin/zsh` doesn't exist
  there.

The Python-backed CPU/MEM plugin (`hendrikmi/tmux-cpu-mem-monitor`) still needs a
real `python3` on `PATH` to set up its virtualenv; without one its `.tmux` setup
script exits non-zero (harmless -- it's the last plugin TPM sources) and
`status-metric` falls back to `CPU --`/`MEM --`, per the Status Line section
above.

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
