# Optional Hermes Desktop session integration

Driftless-NoMore404 does not schedule, enable, or independently start Hermes.
The optional `no-more-404-hermes-session` adapter is for an existing Hermes
Desktop launcher: when the user starts Hermes through that launcher, the
adapter starts the local-model runtime alongside it and stops a runtime it
owns when Hermes exits. While both remain open, llama.cpp still releases model
VRAM after the configured idle interval.

The main installer places the adapter at:

```text
~/.local/libexec/no-more-404/no-more-404-hermes-session
```

It does not alter any desktop entry or enable login autostart.

Current Hermes Desktop builds also provide an official **Local Models** manager.
Use that built-in flow when you want Hermes to manage llama.cpp and model
downloads. Use this adapter only when you deliberately choose NoMore404's
independent Linux/systemd lifecycle for your own GGUF. Do not configure both
managers to own the same llama.cpp process or compete for the same model load.
NoMore404 does not disable, modify, or inspect Hermes's built-in manager.

## Why the Electron sandbox check exists

A locally rebuilt Hermes Desktop can contain a `chrome-sandbox` file owned by
the desktop user. Chromium correctly refuses to trust that file as a set-user-ID
sandbox helper. The adapter accepts an explicitly configured helper only when
all of these checks pass:

- it is an absolute path to a regular file;
- it is not a symbolic link;
- it is owned by `root:root`; and
- its mode is exactly `4755`.

Use a helper supplied by the operating-system package matching Hermes's
Electron major version. Do not make an arbitrary downloaded or user-owned file
set-user-ID root. If no trusted matching helper exists, stop and repair the
Electron installation through the operating system rather than weakening the
check or using `--no-sandbox`.

## Create a user-specific thin launcher

Keep machine paths outside Git. A local launcher can export them and then call
the package-owned adapter:

```bash
#!/usr/bin/env bash
set -Eeuo pipefail

export HERMES_DESKTOP_BIN="/absolute/path/to/Hermes"
export HERMES_DESKTOP_WORKDIR="/absolute/path/to/Hermes/desktop/directory"
export HERMES_ELECTRON_SANDBOX="/usr/lib/electronNN/chrome-sandbox"
export HERMES_DESKTOP_CWD="$HOME"

# The local-model runtime follows this Hermes session. Existing installations
# may use another explicitly named target, such as hermes-runtime.target.
export NO_MORE_404_TARGET_UNIT=no-more-404.target
export NO_MORE_404_REQUIRE_RUNTIME=true

# Optional upstream Hermes launch behavior is inherited unchanged. Uncomment
# only a setting that is appropriate for this machine.
# export HERMES_DESKTOP_DISABLE_GPU=false
# export HERMES_DESKTOP_PASSWORD_STORE=kwallet6

exec "$HOME/.local/libexec/no-more-404/no-more-404-hermes-session" "$@"
```

Replace `electronNN` with the matching packaged Electron major version and
verify the helper before changing the desktop entry:

```bash
stat -Lc '%U:%G %a %n' /usr/lib/electronNN/chrome-sandbox
```

The result must show `root:root 4755`. The adapter repeats the check every time
Hermes is launched and writes a specific error to standard error. It also
writes to the system journal when the standard `logger` command is available.

Point the existing user-controlled Hermes desktop entry at the thin launcher.
Starting that desktop entry is the triggering action; Driftless-NoMore404 does
not create a second login-start mechanism. Arguments supplied to the adapter
are passed to Hermes unchanged.

## Failure and ownership behavior

- If the runtime target is inactive, the adapter starts it and owns that start.
- If the target was already active, the adapter preserves it when Hermes exits.
- The adapter shares the CLI's private lifecycle lock. It holds the lock while
  it owns the runtime, so a concurrent persistent start cannot race its cleanup.
- If another owning lifecycle session holds the lock, required-runtime mode
  refuses to launch Hermes. Optional-runtime mode launches Hermes without
  claiming local-model lifecycle ownership.
- If a required target cannot start, Hermes is not launched.
- Setting `NO_MORE_404_REQUIRE_RUNTIME=false` explicitly permits Hermes to
  continue without the local-model helpers after a target-start failure.
- Signals are forwarded to Hermes, and a runtime owned by the adapter is
  stopped during cleanup.
- An invalid Electron helper fails before either the runtime or Hermes starts.

This adapter couples process lifetimes; it does not modify Hermes source,
configuration, binaries, or the Electron helper.
