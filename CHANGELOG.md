# Changelog

## 1.0.0 - 2026-09-08

- Extracted the local-model lifecycle into an independent, machine-neutral
  package.
- Added on-demand llama.cpp router startup with a one-model default limit,
  idle model sleep, automatic wake-on-request configuration, loopback-only
  networking, and clean systemd control-group teardown.
- Added rootless install, conservative uninstall, doctor, session commands,
  package tests, and a pre-public privacy and security audit.

- Added an optional, generic Hermes Desktop session adapter. It participates in
  the shared lifecycle-ownership lock, starts the local-model runtime only when
  the user launches Hermes through their existing launcher, stops a runtime it
  owns when Hermes exits, and never creates a login or independent Hermes
  autostart path.
- Added strict validation for an explicitly configured Electron sandbox helper
  and documented the safe machine-local launcher boundary. Hermes arguments
  and environment are passed through without package-specific feature shims.
- Made the health watchdog follow the runtime target and corrected its default
  consecutive-failure threshold to two, including an explicit first-fire
  timer interval.
- Made an active target with an inactive router fail visibly without defeating
  the bounded non-restart policy for configuration and missing-input errors.
- Included watchdog failures in the user-facing `no-more-404 logs` stream.
- Made failed cleanup stops visible while preserving the wrapped command's exit
  status, and made uninstall refuse to remove files after a failed runtime
  stop.
- Expanded `doctor` checks for runtime policy, model paths, login enablement,
  and watchdog lifecycle state.
- Hardened install and uninstall validation and added round-trip, corruption,
  doctor, watchdog, and Hermes-session tests.
- Extended the pre-public audit to scan both the current working directory and
  complete Git history with Gitleaks.
- Activated public-facing CI checks for pushes, version tags, pull requests,
  and manual runs.
- Disabled llama.cpp's optional slots-inspection endpoint by default, made the
  wrapper pass the upstream opt-out flag explicitly, and made compatibility
  preflight cover every launch flag selected by the current configuration.
- Corrected documentation for HTTP recovery limits, loopback inputs, and
  systemd path expansion.
- Added a no-`sudo`, no-autostart tagged-release bootstrap for one-command
  installation, dependency guidance for common Linux families, and a
  Quickstart written for people without an AI helper.
- Added a guarded initial `setup` wizard and reduced the example preset to one
  model so a first-time user can configure a chosen GGUF without editing files
  or discovering a second placeholder later.
- Made setup auto-discover an existing compatible `llama-server` or explicitly
  install a checksum-pinned official llama.cpp CPU/Vulkan runtime for x86-64
  and ARM64 Linux, retaining the upstream licence and preserving the runtime on
  uninstall.
- Made portable-runtime loader failures visible, added distro-specific shared-
  library guidance, and bounded downloads while ignoring per-user curl options.
- Replaced the fixed context and forced full-GPU-offload defaults with
  llama.cpp hardware fitting. Setup begins at the selected GGUF's own context,
  preserves Hermes's 64K floor, reserves accelerator-memory headroom, verifies
  the reported context and one local chat token, and saves configuration only
  after the temporary model process has stopped.
- Added a model-neutral failure message that estimates a conservative smaller
  GGUF file size when llama.cpp reports a memory-fit failure. It never names,
  ranks, downloads, or selects a replacement model.
- Added opt-in Hermes picker registration for exactly the aliases in the user's
  model preset. It creates only the named `NoMore404 Local` provider through
  Hermes's own CLI, sets no preferred model, and never changes the
  current/default model selection.
- Made `doctor` reject effective contexts and automatic-fit floors below 64,000
  because current Hermes requires at least that many tokens, and warn when an
  explicit GPU-layer override disables automatic placement.
- Rejected unsafe aliases before any Hermes write, made partial registration
  failures explain the safe recovery path, and prevented whitespace around a
  `runtime.env` assignment from silently substituting a default value.
- Added a bounded, no-tensor-allocation memory projection with the pinned
  runtime's `llama-fit-params` companion before setup starts `llama-server`.
  Custom builds without the companion use a conservative physical-RAM check;
  obviously oversized GGUFs are blocked unless the user explicitly approves
  the temporary load.
- Counted standard split-GGUF shards together for size guidance and retained
  model-neutral advice: only an approximate smaller file-size ceiling is shown.
- Updated the integration guidance for official Linux Hermes Desktop and its
  built-in Local Models manager, including the one-runtime-manager-per-session
  ownership boundary.

The support and security limitations in the README and security policy apply
to this release.
