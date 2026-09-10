# Hermes Desktop integration

Driftless-NoMore404 never schedules, modifies, or independently launches
Hermes Desktop. Its recommended automatic integration watches for a Hermes
Desktop process that the user started normally. The local-model runtime then
starts alongside that session and stops after Hermes closes. llama.cpp can
still unload an idle model while both Hermes and the lightweight router remain
open.

Every configured NoMore404 alias can appear under **NoMore404 Local** in
Hermes's model picker. Selecting another alias does not require restarting
either application. Hermes carries that selection in its next model request;
llama.cpp waits if the current model is busy, then unloads it and loads the
selected model into NoMore404's single resident slot. Use
`no-more-404 add-model` to fit another GGUF and offer its alias to the picker.

Hermes Desktop also provides its own **Local Models** manager. Use that manager
or NoMore404 for a given local-model session, not both. NoMore404 does not
disable, modify, or inspect Hermes's built-in manager.

## Automatic following (recommended)

Guided setup asks:

```text
Automatically start NoMore404 when Hermes Desktop opens and stop it when Hermes closes? [Y/n]:
```

Press Enter or answer `yes`. No desktop-file editing is required. If this step
was skipped, enable it later with:

```bash
no-more-404 integrate-hermes-desktop
```

This enables `no-more-404-hermes-follower.service` in the current user's
systemd session. The follower is a small control-plane process; it does not
load a model, reserve VRAM, or start Hermes. It waits until the user launches
the native Linux Hermes Electron application, then:

1. acquires NoMore404's private lifecycle lock;
2. refuses to compete with an existing listener on the configured port;
3. starts `no-more-404.target`;
4. waits for the router health endpoint;
5. keeps ownership while Hermes remains open; and
6. stops the target it owns after the last main Hermes process disappears.

If the target was already running before Hermes opened, the follower does not
claim or stop it. A brief two-check close debounce avoids reacting to a single
missed process observation. Electron renderer, zygote, GPU, and utility helper
processes carry a `--type=` role and do not keep the runtime alive on their own.

The follower examines only process metadata belonging to the current Linux
user: the process name, first command argument, and Electron role argument. It
does not read Hermes configuration, conversations, prompts, or workspace
files. It recognises the ordinary native executable names `Hermes` and
`hermes`, so Hermes updates can replace the application without requiring a
new NoMore404 launcher.

Check the integration with:

```bash
no-more-404 doctor
no-more-404 status
```

`status` includes the follower, router, and target. `logs` follows follower,
router, and health-watchdog messages:

```bash
no-more-404 logs
```

When automatic startup fails, the follower records a clear journal error and
retries while Hermes remains open. If the optional `notify-send` command is
available, it also sends one local desktop notice for that Hermes session. It
does not close Hermes, transmit telemetry, or send a remote notification.

Disable automatic following at any time with:

```bash
no-more-404 remove-hermes-desktop-integration
```

This stops and disables only the follower. If it owns the NoMore404 target, its
normal shutdown also stops that target. It does not edit or remove any Hermes
file. Running `integrate-hermes-desktop` again is safe and re-enables it.

## Detection limit

Automatic following deliberately recognises only the ordinary native Hermes
Electron process. A custom build whose executable has been renamed will not be
guessed from a broad process search. This avoids starting a model runtime for
an unrelated application.

For such a build, either retain the executable name `Hermes`/`hermes` or use the
advanced foreground adapter below. Disable automatic following before choosing
the adapter so one lifecycle mechanism has clear ownership.

## Advanced foreground adapter

The package still installs:

```text
~/.local/libexec/no-more-404/no-more-404-hermes-session
```

This adapter is for an explicitly user-controlled launcher. The launcher
invokes the adapter, which starts the configured runtime target before the
requested Hermes executable and stops a runtime it owns when that exact
foreground session ends. Unlike the recommended follower, this path requires
machine-specific executable, working-directory, and Electron sandbox paths.

### Electron sandbox requirement

A locally rebuilt Hermes Desktop can contain a `chrome-sandbox` file owned by
the desktop user. Chromium correctly refuses to trust that file as a
set-user-ID sandbox helper. The adapter accepts an explicitly configured helper
only when all of these checks pass:

- it is an absolute path to a regular file;
- it is not a symbolic link;
- it is owned by `root:root`; and
- its mode is exactly `4755`.

Use a helper supplied by the operating-system package matching Hermes's
Electron major version. Do not make an arbitrary downloaded or user-owned file
set-user-ID root. If no trusted matching helper exists, use automatic following
so Hermes retains responsibility for its own sandbox setup, or repair Electron
through the operating system. Never weaken the adapter with `--no-sandbox`.

### Create a machine-specific launcher

Keep machine paths outside Git:

```bash
#!/usr/bin/env bash
set -Eeuo pipefail

export HERMES_DESKTOP_BIN="/absolute/path/to/Hermes"
export HERMES_DESKTOP_WORKDIR="/absolute/path/to/Hermes/desktop/directory"
export HERMES_ELECTRON_SANDBOX="/usr/lib/electronNN/chrome-sandbox"
export HERMES_DESKTOP_CWD="$HOME"
export NO_MORE_404_TARGET_UNIT=no-more-404.target
export NO_MORE_404_REQUIRE_RUNTIME=true

# Optional upstream Hermes launch behavior is inherited unchanged. Uncomment
# only a setting appropriate for this machine.
# export HERMES_DESKTOP_DISABLE_GPU=false
# export HERMES_DESKTOP_PASSWORD_STORE=kwallet6

exec "$HOME/.local/libexec/no-more-404/no-more-404-hermes-session" "$@"
```

Replace `electronNN` with the matching packaged Electron major version and
verify the helper before changing a user-owned desktop entry:

```bash
stat -Lc '%U:%G %a %n' /usr/lib/electronNN/chrome-sandbox
```

The result must show `root:root 4755`. The adapter repeats the check each time
and writes a specific error to standard error and, when available, the system
journal.

### Adapter ownership behavior

- If the runtime target is inactive, the adapter starts it and owns that start.
- If the target was already active, the adapter preserves it when Hermes exits.
- It holds the shared lifecycle lock while it owns the runtime.
- A concurrent owning lifecycle operation is refused in required-runtime mode.
- If a required target cannot start, Hermes is not run through the adapter.
- `NO_MORE_404_REQUIRE_RUNTIME=false` explicitly permits Hermes to continue
  without the local-model helpers after a target-start failure.
- Signals are forwarded to Hermes, and the owned target is stopped during
  cleanup.
- An invalid Electron helper fails before either runtime or Hermes starts.

The adapter couples process lifetimes; it does not modify Hermes source,
configuration, binaries, or the Electron helper.
