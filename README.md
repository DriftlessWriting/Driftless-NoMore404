# Driftless-NoMore404 for Linux

> **Platform:** Linux desktops with a working systemd user manager. Native
> Windows and macOS are not supported by this release.

Driftless-NoMore404 is an independent, unofficial Linux lifecycle companion for
[Hermes Agent](https://github.com/NousResearch/hermes-agent) and
[llama.cpp](https://github.com/ggml-org/llama.cpp). It starts
an on-demand local-model router, waits for its health endpoint, limits model
residency so idle models can release GPU memory (VRAM), and gives Hermes a
stable local-only endpoint that speaks the same API as OpenAI.

**New here?** Start with the [Quickstart](docs/QUICKSTART.md). It is written
for first-time installers and does not assume access to an AI helper.

This repository is not a fork of Hermes Agent or llama.cpp. It does not vendor,
patch, or redistribute either upstream codebase, their binaries, model weights,
or brand assets. It is not affiliated with, sponsored by, endorsed by, or
supported by Nous Research or ggml-org.

## Where it fits

Current Hermes Desktop builds include an official **Local Models** flow that can
manage llama.cpp and model downloads inside Hermes. That is usually the easiest
choice for someone who wants Hermes to choose and manage the whole local-model
stack. See the official [Hermes Desktop guide](https://github.com/NousResearch/hermes-agent/blob/main/website/docs/user-guide/desktop.md)
and [Local Models guide](https://github.com/NousResearch/hermes-agent/blob/main/website/docs/user-guide/local-models.md).

NoMore404 is a separate option for a Linux user who has chosen a GGUF and wants
a model-neutral, systemd-managed endpoint with explicit lifecycle ownership,
idle unloading, health recovery, and optional Hermes picker registration. It
does not replace or extend Hermes's built-in manager. Use one manager for a
given local endpoint and session; do not ask Hermes Local Models and NoMore404
to own the same llama.cpp process or compete for the same model load.

## Install in one command

On a supported Linux desktop, this installs the `1.0.0` package for the current
user without `sudo` and without starting or enabling anything:

```bash
bash -o pipefail -c 'curl --proto =https --tlsv1.2 --fail --silent --show-error --location https://raw.githubusercontent.com/DriftlessWriting/Driftless-NoMore404/v1.0.0/install.sh | bash'
```

The bootstrap downloads the tagged source into a private temporary directory,
runs the same auditable installer included in this repository, and removes the
temporary copy afterward. The bootstrap itself does not start services or
install Hermes, GPU drivers, or model files. During the separate guided setup,
NoMore404 can use an existing compatible `llama-server` or, with the user's
explicit choice, download a pinned official llama.cpp Linux runtime and verify
its SHA-256 digest. The [Quickstart](docs/QUICKSTART.md) walks through this
without assuming prior Linux or local-model experience.

Running code directly from the internet is a trust decision. To inspect the
small bootstrap before running it:

```bash
curl --proto '=https' --tlsv1.2 --fail --silent --show-error --location \
  --output no-more-404-install.sh \
  https://raw.githubusercontent.com/DriftlessWriting/Driftless-NoMore404/v1.0.0/install.sh
less no-more-404-install.sh
bash no-more-404-install.sh
```

## What it does

- Installs a small Bash CLI and four systemd user units.
- Auto-discovers a compatible `llama-server`, accepts a user-supplied one, or
  explicitly installs a pinned and checksum-verified official Linux runtime.
- Lets the user choose the GGUF, then asks llama.cpp to fit that model to the
  available hardware. It accepts no context below Hermes's 64K minimum, uses
  the model's larger context when it fits, and leaves GPU-layer placement
  automatic.
- Before starting the temporary server, uses llama.cpp's companion
  `llama-fit-params` tool when available to project whether the GGUF and 64K
  floor fit without allocating model tensors. A custom build without that tool
  gets a conservative physical-RAM check and blocks an obviously oversized
  load unless the user explicitly overrides the warning.
- Runs a temporary one-token local chat test before saving first-run
  configuration, then unloads the tested model.
- Rejects non-loopback bind addresses.
- Starts with no model preloaded, allows at most one resident model by default,
  and asks llama.cpp to unload it after an idle interval.
- Waits for llama.cpp's `/health` endpoint on explicit `start`, `restart`, and
  `run` operations.
- Uses systemd `Restart=on-failure` to recover when the server process exits
  unexpectedly.
- Runs a bounded health watchdog: while the runtime is active, a timer probes
  the `/health` endpoint and restarts the runtime after consecutive failed
  checks, so a router that hangs while still running is detected and replaced.
- Stops the service control group so model workers do not knowingly outlive the
  managed runtime.
- Includes an optional Hermes Desktop session adapter. When an existing
  user-controlled Hermes launcher invokes it, the runtime starts alongside
  Hermes and stops when that session ends; the adapter also applies a strict
  Electron sandbox-helper check.
- Provides guided initial `setup` plus `register-hermes`, `doctor`, `status`,
  `logs`, and `endpoint` commands. With explicit approval, setup can add the
  configured local-model aliases to Hermes Desktop's model picker.

## What it does not do

- It does not install, update, modify, or launch Hermes Agent automatically.
- It does not enable or schedule Hermes Desktop, edit a desktop entry, or add a
  second login-autostart mechanism. The optional session adapter runs only
  when an existing Hermes launcher explicitly invokes it.
- It does not silently download or update llama.cpp. `setup` and
  `install-runtime` can explicitly download the pinned official Linux runtime;
  an existing compatible build remains fully supported.
- It does not download a model.
- It does not silently change Hermes configuration or switch Hermes's current
  or default model. The optional `register-hermes` command uses Hermes's own
  configuration CLI to add or update only the named `NoMore404 Local` provider.
- It does not enable itself at login. Installation leaves the units disabled
  and stopped.
- It is not a full watchdog. The health timer only acts while the runtime is
  active, probes the router's `/health` endpoint, and restarts the target after
  a bounded number of consecutive failures. It does not judge whether a loaded
  model is producing correct answers, and it never starts a runtime the
  operator has stopped.
- It does not assess model quality, tool-call correctness, or whether a model's
  license permits a particular use.
- It does not recommend, rank, download, or favour any model. The user chooses
  the model and quantisation. NoMore404 sizes the selected model's runtime
  configuration; if it cannot fit, it may suggest a conservative maximum GGUF
  file size without naming a replacement model.

For the complete component and failure boundaries, see
[Architecture](docs/ARCHITECTURE.md).

## Requirements

This package targets a Linux user session with a working systemd user manager.
Native Windows and macOS are not supported by this package. WSL requires a
working systemd user session and remains an environment-specific setup.

The package is distribution-independent within that boundary; it does not
depend on CachyOS or an Arch package manager. The `1.0.0` package checks pass
on the following environments:

| Environment | Validation |
| --- | --- |
| CachyOS | Native development host and complete package test suite |
| Ubuntu 24.04 LTS | Complete package test suite in a clean container |
| Debian 12 | Complete package test suite in a clean container |
| Fedora 44 | Complete package test suite in a clean container |

Other mainstream distributions with systemd user sessions and the required
commands are expected to work, but are not represented as tested until they
join this matrix. Non-systemd installations such as Alpine/OpenRC, Void/runit,
and non-systemd Artix or Devuan are outside the current package contract.
Container validation covers the scripts, install/uninstall behavior, policy
checks, and systemd unit structure; real model loading and VRAM behavior also
depend on the user's llama.cpp build, GPU drivers, model, and hardware.

You must provide:

- Bash, systemd, curl, tar, `ss` from iproute2, `flock` from util-linux, and the
  standard Unix utilities used by the scripts;
- either an existing `llama-server` executable that supports the launch flags
  validated by `doctor`, or x86-64/ARM64 Linux capable of running the pinned
  official CPU/Vulkan runtime offered by setup. The Quickstart's distro commands
  include that binary's ordinary OpenMP, OpenSSL, zlib, Brotli, and Zstandard
  runtime libraries; if one is missing, setup shows the loader error and the
  matching dependency command instead of hiding the failure. The pinned runtime
  also supplies the compatible `llama-fit-params` safety preflight; custom
  builds without it remain usable through the documented conservative fallback;
- one or more locally available GGUF model files, with an effective context of
  at least 64,000 tokens for current Hermes releases (guided setup measures the
  usable value before saving it);
  and
- a separately installed [Hermes Agent](https://github.com/NousResearch/hermes-agent/blob/main/website/docs/getting-started/quickstart.md)
  or an existing Hermes Desktop build if you want to use the endpoint from
  Hermes.

The llama.cpp revision used for compatibility testing is recorded in
[`vendor/llama.cpp.lock`](vendor/llama.cpp.lock). That file is provenance
metadata only; the repository does not contain llama.cpp.

## Install from a downloaded source tree

Review the proposed changes first:

```bash
./scripts/install.sh --dry-run
```

Install the user-owned CLI and units:

```bash
./scripts/install.sh
```

The installer does not enable or start the runtime. It creates private example
configuration on first install and preserves existing configuration on later
runs.

For an upgrade that backs up changed package-managed files before replacing
them:

```bash
./scripts/install.sh --upgrade
```

## Choose a model and configure the runtime

For a first installation, run the guided setup. It finds `llama-server` when it
is already on `PATH`. If none is found, pressing Enter explicitly installs the
pinned official runtime for the current user. Setup then asks for the user's
GGUF and a picker name and, when Hermes is installed, one separate yes/no
question about adding that name to Hermes Desktop's picker:

```bash
~/.local/bin/no-more-404 setup
```

It temporarily loads the selected model, lets llama.cpp fit the largest context
that the current hardware can support without crossing the 64K floor, checks
the local chat endpoint, unloads the model, and only then writes private
configuration. No persistent service or Hermes process is started. If you
approve the picker step, it registers the alias and measured context under
`NoMore404 Local` without switching Hermes's current or default model.
Alternatively, edit these installed files manually:

```text
~/.config/no-more-404/runtime.env
~/.config/no-more-404/models.ini
```

In `runtime.env`, replace both placeholder paths with absolute paths:

```ini
LLAMA_SERVER_BIN="/absolute/path/to/llama-server"
MODELS_PRESET="/absolute/path/to/models.ini"
BIND_HOST=127.0.0.1
PORT=55984
```

In `models.ini`, replace the model path and keep startup loading disabled:

```ini
[*]
ctx-size = 131072  # example only: use the value measured on this machine
fit = on
fit-target = 1024
fit-ctx = 64000

[local-main]
model = /absolute/path/to/model.gguf
load-on-startup = false
```

The included shared preset enables Jinja chat templates for tool calling, but
the selected model and its template must also support the behavior Hermes
needs. NoMore404 makes no model recommendation. Guided setup is preferred over
copying the illustrative context above: it begins from the selected GGUF's own
context, lets llama.cpp fit it with a 1 GiB accelerator-memory margin and a 64K
floor, and saves the context llama.cpp actually reports. It deliberately does
not force `n-gpu-layers`, so placement can adapt to free hardware memory when
the model is loaded later.

Validate the configuration without intentionally loading a model:

```bash
no-more-404 doctor
```

`doctor` checks paths, required llama.cpp flags, automatic fitting and its 64K
floor, the loopback policy, preset placeholders, startup-preload policy, the
effective Hermes context, installed units, and—if already running—the health
endpoint.

## Connect Hermes

If you accepted the final setup prompt, the configured alias is already listed
under **NoMore404 Local**. Otherwise, register or refresh all aliases from the
installed `models.ini` with:

```bash
no-more-404 register-hermes
```

This command changes only `providers.no-more-404` through Hermes's own
configuration command. It never changes `model.default`, `model.provider`, or
the model used by a running Hermes session. In Hermes Desktop, choose **Refresh
models**, then select the alias you configured.

Print the local endpoint at any time with:

```bash
no-more-404 endpoint
```

The default is:

```text
http://127.0.0.1:55984/v1
```

Older Hermes versions that do not support `hermes config set` can still use
`hermes model` and **Custom endpoint**. Select a model name matching a section
in `models.ini`, such as `local-main`, and use the same context length. For a
manual current-format `config.yaml` setup, add this named provider without
replacing the existing top-level `model` selection:

```yaml
providers:
  no-more-404:
    name: NoMore404 Local
    api: http://127.0.0.1:55984/v1
    transport: chat_completions
    discover_models: false
    models:
      local-main:
        context_length: 131072  # example: copy setup's measured ctx-size
```

No API key is needed for the enforced loopback endpoint. Re-running
`register-hermes` adds or updates configured aliases but deliberately does not
delete older aliases, in case the user has edited that provider separately. It
does not set a preferred model within the provider.

Hermes documents this as its first-class custom-provider path and explicitly
supports llama.cpp servers in its
[custom-provider instructions](https://github.com/NousResearch/hermes-agent/blob/main/website/docs/integrations/providers.md#custom--self-hosted-llm-providers).

Driftless-NoMore404 writes this provider only after the explicit setup choice or
`register-hermes` command, and does so through Hermes's own CLI. Use
`hermes model` when an older installed Hermes expects a different layout.
Hermes installation and updates remain entirely with its upstream process.

To make the runtime follow an existing Hermes Desktop session—and to preserve
the hardened Electron sandbox check used by local desktop builds—see
[Optional Hermes Desktop session integration](docs/HERMES_DESKTOP.md).

## Use the runtime

```bash
no-more-404 start
no-more-404 status
no-more-404 logs
no-more-404 restart
no-more-404 stop
```

To keep the runtime available for the lifetime of a foreground command:

```bash
no-more-404 run -- /path/to/foreground-client
```

`run` stops the runtime afterward only if it started the runtime itself. If the
target was already active, it leaves it active. A model may still unload after
the configured idle interval while the lightweight llama.cpp router remains
running. A private lifecycle lock serialises owning Hermes sessions, `run`,
`start`, and `restart`. While an owning session is active, a concurrent
`start`, `restart`, or second owning session is rejected rather than reporting
durable ownership of a runtime that the first session may stop when its child
exits. After that session finishes, ordinary starts work normally.

### Current recovery behavior

When `llama-server` exits with an unexpected failure, systemd attempts to
restart it after five seconds, subject to a limit of five starts in five
minutes. Configuration, usage, and missing-input exits are deliberately not
restarted because retrying cannot repair those conditions.

While the runtime is active, a systemd timer runs a bounded health watchdog
every two minutes. Each probe hits the router's `/health` endpoint; a single
failure is recorded but does not act on its own. After two consecutive failed
checks (configurable with `HEALTH_FAILURES_REQUIRED`, minimum two), the
watchdog restarts the runtime target and resets its count. While the router is
inactive because the runtime was deliberately stopped, the watchdog does
nothing. If the target remains active while its router is inactive, the
watchdog reports a failed run for inspection but does not defeat the bounded
non-restart policy for invalid configuration or missing inputs.

The watchdog is therefore a recovery aid, not autonomous operation: it closes
the "alive but hung" gap, but it still cannot distinguish a wedged model
response from a healthy one, and a runtime you stop stays stopped.

```bash
no-more-404 restart
```

remains the manual escape hatch for any situation the bounded policy does not
cover.

Failure reporting is local: commands return nonzero with an error, `doctor`
reports broken state, and `logs` includes both router and watchdog journal
messages. The package does not send desktop, email, or remote notifications.

## Security posture

- The launcher accepts only the explicit loopback addresses `127.0.0.1` and
  `::1` as its configured bind host. The examples use `127.0.0.1`.
- The llama.cpp web UI and slots endpoint are disabled, and metrics are
  disabled by default.
- Runtime configuration, state, cache directories, and installer backups are
  created with private permissions where the scripts manage them.
- The service runs as the current user with a small set of systemd hardening
  options. It is **not** a complete sandbox and retains the filesystem and GPU
  access needed by the configured executable and models.
- The loopback endpoint has no additional authentication layer. Do not expose
  it through a proxy, tunnel, container port, or firewall rule without adding
  an appropriate security design.
- Treat model files and model inputs as untrusted. Review llama.cpp's
  [security guidance](https://github.com/ggml-org/llama.cpp/blob/master/SECURITY.md)
  before using third-party artifacts or sensitive data.

## Uninstall

Review the removal plan:

```bash
./scripts/uninstall.sh --dry-run
```

Then uninstall package-managed files:

```bash
./scripts/uninstall.sh
```

The uninstaller removes only files whose hashes still match its install
manifest. It preserves locally modified files and keeps configuration, models,
caches, state, and backups. It also preserves the separately owned Hermes
provider entry; remove that explicitly, if wanted, with
`hermes config unset providers.no-more-404`.

## Repository layout

```text
bin/                         CLI, router wrapper, watchdog, optional Hermes adapter
config/                      private-runtime and model-preset examples
docs/ARCHITECTURE.md         component, lifecycle, and failure boundaries
docs/HERMES_DESKTOP.md       optional session coupling and Electron sandbox check
docs/QUICKSTART.md           first-time setup path, written for new installers
install.sh                   tagged-release bootstrap used by the one-command install
scripts/                     cautious install, uninstall, and audit helpers
systemd/user/                on-demand target, router, and watchdog units
tests/                       syntax, policy, wrapper, and unit checks
vendor/llama.cpp.lock        tested-upstream provenance; no vendored code
THIRD_PARTY_NOTICES.md       upstream license and naming notices
```

Run the package checks with:

```bash
./tests/run.sh
```

The CI and security workflow is committed at
[`.github/workflows/ci.yml`](.github/workflows/ci.yml):
package tests with ShellCheck, plus Gitleaks working-tree and complete-history
scans, with pinned step versions and image digests. It runs on pushes to
`main`, version tags, every pull request, and on demand (`workflow_dispatch`).
Local package, lint, and secret scans remain mandatory between runs.

## Upstream relationship and notices

Hermes Agent is the agent/application layer. llama.cpp is the independently
installed inference engine. Driftless-NoMore404 owns only the lifecycle glue
between the local operating system and that documented HTTP integration point.
It does not require a Nous Hermes-branded model; compatible model choice remains
with the user.

See [Third-Party Notices](THIRD_PARTY_NOTICES.md) for upstream licenses,
attribution, model-license boundaries, and naming caveats.
