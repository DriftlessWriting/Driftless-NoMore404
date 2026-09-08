# Operations

## Install without starting anything

```bash
./scripts/install.sh --dry-run
./scripts/install.sh
```

The installer writes package-managed commands and systemd user units, then
creates private example configuration files only when they do not already
exist. It does not enable or start the runtime. A tagged release can also be
installed through the repository-root bootstrap documented in the README; it
downloads into a private temporary directory and invokes this same installer.

For untouched example configuration, run:

```bash
no-more-404 setup
```

The guided setup auto-discovers `llama-server`, accepts another path, or offers
an explicit checksum-verified download of the pinned official runtime. The
pinned runtime includes `llama-fit-params`; setup first uses it to project fit
without allocating model tensors. A custom runtime without that companion gets
a conservative physical-RAM check, and an obviously oversized GGUF requires an
explicit override before any temporary load. Setup then loads the user's chosen
model, lets llama.cpp fit context and device placement with a 64K floor, runs
one local chat token, and stops the process. It updates the two private files
only after that test passes. If Hermes is installed, setup also offers to add
the model alias and measured context to Hermes Desktop's picker; that separate
step is optional and does not switch Hermes's current or default model. For
manual or multi-model setup, edit:

```text
~/.config/no-more-404/runtime.env
~/.config/no-more-404/models.ini
```

Set `LLAMA_SERVER_BIN` and `MODELS_PRESET` to absolute paths. Replace every
example model path. The router refuses remote bind addresses, unresolved
placeholders, and models configured to preload. `doctor` also requires
automatic fitting with a floor of at least 64K. The setup command refuses to
overwrite configuration that no longer contains the initial placeholders.

The pinned runtime can also be installed separately before setup:

```bash
no-more-404 install-runtime
```

It is stored under the user's XDG data directory with the upstream licence.
Uninstall preserves it; removing a separately downloaded runtime is a distinct,
explicit user decision.

## Validate

```bash
no-more-404 doctor
```

The doctor checks the systemd user manager, unit installation, private config
mode, llama-server feature and auto-fit flags, model preset, Hermes's 64K
minimum context and fit floor, loopback binding, port, and—if already
active—the health endpoint. It does not load a model.

## Operate

```bash
no-more-404 start
no-more-404 status
no-more-404 logs
no-more-404 stop
```

To couple the runtime to a foreground desktop process:

```bash
no-more-404 run -- /path/to/foreground-client
```

The wrapper starts the runtime, waits for the router to become healthy, and
runs the supplied command. It stops the target afterward only when it was the
component that started it. The command must remain in the foreground. The
package serialises owning `run` and Hermes-adapter sessions with a user-runtime
lock; concurrent-session reference counting is outside the current design.
`start`, `restart`, and a second owning session reject while the lock is held.
This prevents `start` from appearing to establish a persistent runtime that an
earlier owning session would later stop. After that session exits, ordinary
starts work normally.

Add or refresh the configured local-model aliases under the named
`NoMore404 Local` provider with:

```bash
no-more-404 register-hermes
```

This explicit command uses Hermes's own configuration CLI and changes only
`providers.no-more-404`; it does not change `model.default` or
`model.provider`. Then choose **Refresh models** in Hermes Desktop and select
the desired alias. Print the provider's local endpoint with:

```bash
no-more-404 endpoint
```

For Hermes Desktop, the optional session adapter can be called by an existing
desktop entry so this target starts with the user-invoked Hermes process and
stops when Hermes exits. It does not create or enable autostart. See
[Hermes Desktop session integration](HERMES_DESKTOP.md).

Hermes Desktop also has its own managed **Local Models** flow. Treat that and
NoMore404 as alternative runtime owners: do not point both at the same
llama.cpp process or let both load the same local model for one session.

## Failure policy

The outer router restarts on failure. Five failures within five minutes trip
systemd's start-rate limit (circuit breaker). Configuration, missing-file, and
usage exit codes do not restart. A clean `stop` never restarts the process.

While the runtime is active, the `no-more-404-watch.timer` runs the bounded
health watchdog every two minutes. It probes the router's `/health` endpoint
and, after `HEALTH_FAILURES_REQUIRED` consecutive failed checks (default 2,
minimum 2), restarts the runtime target. A deliberately stopped target remains
untouched. If the target is active but its router is inactive, the watchdog
reports failure for inspection without overriding configuration and
missing-input statuses that must not enter a restart loop. It closes the case
where a live router stops answering its health endpoint. It does not detect one
stuck generation while `/health` remains responsive. Restart performs its
dependency, endpoint, timeout, ownership-lock, and port checks before asking
systemd to disrupt the target. `no-more-404 logs` follows both router and
watchdog messages. Failure reporting remains local; this package does not send
desktop or remote notifications.

## Uninstall

```bash
./scripts/uninstall.sh --dry-run
./scripts/uninstall.sh
```

Uninstall removes only package-managed files whose hashes still match the
install manifest. Locally modified installed files are preserved. User config,
models, optional downloaded llama.cpp runtime, caches, state, and backups are
always preserved. The separately owned Hermes provider entry is also
preserved; remove it explicitly, if wanted, with
`hermes config unset providers.no-more-404`. If systemd cannot stop the runtime
first, uninstall reports the failure and removes nothing.
