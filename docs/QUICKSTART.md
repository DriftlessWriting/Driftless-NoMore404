# Quickstart: get a local model running on Linux

This guide assumes no AI helper and only basic familiarity with copying commands
into a terminal. It applies to a Linux desktop session with a working systemd
user manager. If a step fails, jump to
[When something is wrong](#when-something-is-wrong).

## What this package gives you

A small set of commands — `no-more-404 start`, `stop`, `doctor`, and
friends — that:

- start your local model server only when you ask, so it is not resident or
  using memory the rest of the time;
- keep exactly one model loaded at a time, safely replace it when you choose a
  different local alias, and ask the server to release it from memory after one
  idle minute;
- restart the server automatically if it crashes;
- automatically follow a user-started Hermes Desktop session when you approve
  that setup choice—without editing or launching Hermes; and
- give Hermes a stable, local-only endpoint: `http://127.0.0.1:55984/v1`.

The running endpoint stays on your machine and listens only on loopback (your
own machine). NoMore404 adds no telemetry, account, or API key. Installation
contacts GitHub for the tagged source. An optional pinned llama.cpp runtime
comes directly from ggml-org's GitHub release, while the model and its source
remain the user's choice.

Hermes Desktop now has its own [**Local Models** setup](https://github.com/NousResearch/hermes-agent/blob/main/website/docs/user-guide/local-models.md),
including managed llama.cpp and model downloads. If that is available on your
system and you want Hermes to manage those choices, use it. NoMore404 is the
independent Linux option for someone who has already chosen a GGUF and wants
the lifecycle and endpoint managed by systemd without model recommendations.
Do not configure both systems to manage the same llama.cpp process or
local-model session.

## Before installing

The installer needs `curl`, `ss`, `flock`, and ordinary base utilities. They
are commonly already present. If any are missing, use only the command for
your distribution.

Ubuntu, Debian, Linux Mint, or Pop!_OS:

```bash
sudo apt update && sudo apt install --yes bash coreutils curl diffutils iproute2 tar util-linux libgomp1 libssl3 zlib1g libbrotli1 libzstd1
```

Fedora:

```bash
sudo dnf install --assumeyes bash coreutils curl diffutils iproute tar util-linux libgomp openssl-libs zlib brotli libzstd libstdc++
```

Arch Linux, CachyOS, EndeavourOS, or Manjaro:

```bash
sudo pacman --sync --needed bash coreutils curl diffutils iproute2 tar util-linux gcc-libs openssl zlib brotli zstd
```

These commands install ordinary operating-system utilities and the shared
runtime libraries used by the optional official llama.cpp binary. NoMore404
itself runs as your normal user and never asks for `sudo`. If you supply a
different `llama-server`, its own dependencies may differ.

## Install NoMore404

Copy and paste this entire command:

```bash
bash -o pipefail -c 'curl --proto =https --tlsv1.2 --fail --silent --show-error --location https://raw.githubusercontent.com/DriftlessWriting/Driftless-NoMore404/v1.2.1/install.sh | bash'
```

It downloads the tagged source temporarily, installs the user-owned commands
and systemd units, and then removes the temporary source. It does not start or
enable a service. If the final message says that `~/.local/bin` is not in your
`PATH`, use the full command path it prints until you open a new terminal or
add that directory to your shell configuration.

## What you must provide once

You provide **at least one GGUF model file that you have chosen**. Each one
needs a working tool-calling Jinja chat template and a context of at least
64,000 tokens for current Hermes releases. Check the publisher's documentation
and licence, and keep the files somewhere like `$HOME/models/`.

NoMore404 does not recommend, favour, or download a model. If a selected GGUF is
too large for the machine, setup gives a conservative approximate GGUF file
size to try instead, without naming a model family or repository. File size is
used because parameter count alone is misleading across quantisations and
architectures.

NoMore404 also needs llama.cpp, but a first-time user does not need to compile
it manually. Setup follows this order:

1. Use a compatible `llama-server` already available on `PATH`.
2. Accept another executable path supplied by the user.
3. If neither exists, offer a pinned official llama.cpp CPU/Vulkan runtime for
   x86-64 or ARM64 Linux. The download is accepted only after its SHA-256 digest
   matches [`vendor/llama.cpp.lock`](../vendor/llama.cpp.lock), and the upstream
   licence is retained beside the executables. This runtime includes
   `llama-fit-params`, the companion used for the no-load memory projection.

An advanced user may still install or build a different backend by following
llama.cpp's [official installation](https://github.com/ggml-org/llama.cpp/blob/master/docs/install.md)
and [build](https://github.com/ggml-org/llama.cpp/blob/master/docs/build.md)
instructions, then enter that `llama-server` path during setup.

## Fit and configure your chosen model

Run the guided initial setup:

```bash
~/.local/bin/no-more-404 setup
```

If `llama-server` is found automatically, press Enter to accept it. If none is
found, press Enter to install the verified pinned runtime. Then enter the path
to your chosen GGUF and either accept the neutral `local-main` label or type
your own picker label.

Before loading model weights, setup asks the compatible `llama-fit-params`
companion to read the chosen GGUF metadata and project whether it fits. The
projection uses the same automatic placement, a 1 GiB memory margin, and
Hermes's 64K context floor as the real load. If it does not fit, setup stops
before starting `llama-server`, leaves configuration unchanged, and suggests an
approximate smaller GGUF file size without naming a model.

An independently supplied llama.cpp build may not include that companion. In
that case setup compares the complete GGUF set with currently available
physical RAM, reserves substantial headroom, and does not count swap. A small
file proceeds to the real test; an obviously oversized file is blocked unless
the user explicitly approves the risk. This fallback is intentionally
conservative because accelerator and unified-memory layouts differ.

After that preflight, setup temporarily loads only the chosen GGUF on a free
loopback port. llama.cpp starts from the model's own context and fits it to
currently available hardware. Its fitter is not allowed to reduce below
Hermes's 64K floor, and NoMore404 also rejects a model whose own context starts
below that floor. It reads back the actual fitted value, performs a one-token
local chat check, stops the temporary server so its RAM and VRAM are released,
and then writes both configuration files privately. Close unrelated GPU-heavy
applications first if you want sizing to reflect the machine's normal available
capacity. A successful projection reduces risk but cannot guarantee that memory
will still be free when the later load occurs.

The suggested alias, `local-main`, is only a label; it does not choose or imply
a particular model. If Hermes is installed, setup separately asks whether to
add that alias and measured context under **NoMore404 Local**. It never switches
Hermes's current or default model. Setup then asks whether NoMore404 should
automatically follow Hermes Desktop. Press Enter or answer `yes` for the normal
Desktop experience. A lightweight user service will wait without loading a
model, start the runtime when you open Hermes, and stop its owned runtime when
Hermes closes. It never starts or changes Hermes.

## Add more models to the picker

You can stop after one model. To add another later, first close Hermes Desktop
or stop a manually started NoMore404 runtime, then run:

```bash
no-more-404 add-model
```

Enter the additional GGUF path and the name you want to see in Hermes. Names
may contain ordinary spaces, so labels such as `Writing Model` are supported.
NoMore404 repeats the memory projection, hardware fitting, 64K-floor check, and
local chat test for that GGUF. It changes nothing if the test fails. If Hermes
is installed, press Enter at the final question to add or refresh every
configured alias under **NoMore404 Local**.

Repeat this command for any other user-chosen models. NoMore404 still keeps
only one model resident at a time; adding models to the picker does not preload
them or increase idle VRAM use.

If you prefer to configure it manually, edit these two files:

```text
~/.config/no-more-404/runtime.env
~/.config/no-more-404/models.ini
```

In `runtime.env`, set the two paths to the things from the previous section:

```ini
LLAMA_SERVER_BIN="/absolute/path/to/llama.cpp/build/bin/llama-server"
MODELS_PRESET="/absolute/path/to/.config/no-more-404/models.ini"
```

Use the real absolute paths printed by commands such as
`realpath "$HOME/src/llama.cpp/build/bin/llama-server"`. Do not paste a
literal `$HOME` into either configuration file: systemd environment files and
llama.cpp model presets do not perform shell variable expansion.

In `models.ini`, set your model file (keep `load-on-startup = false`):

```ini
[*]
ctx-size = 131072  # illustrative only; guided setup measures your value
fit = on
fit-target = 1024
fit-ctx = 64000

[local-main]
model = /absolute/path/to/your-model.gguf
load-on-startup = false
```

Section names like `local-main` are the model names Hermes will request. Do not
copy the illustrative context blindly: setting it too high can exhaust memory,
while setting every machine to 64K unnecessarily limits hardware that can run
more. Guided setup is the normal path.

## Check it, then use it

```bash
no-more-404 doctor     # there should be no FAIL lines
```

If `doctor` shows a `FAIL`, do not start — fix the line it names and re-run. It
also rejects a model whose effective `ctx-size` is below Hermes's 64K minimum.

If automatic Desktop following was approved, just open Hermes Desktop normally.
NoMore404 detects it, waits for the local endpoint to become healthy, and stops
the owned runtime when Hermes closes. If you use Hermes Agent without Desktop,
or chose not to enable following, start the endpoint explicitly:

```bash
no-more-404 start
```

## Install Hermes Agent if needed

NoMore404 does not install or update Hermes. On Linux, the official Hermes
Agent installation command is:

```bash
bash -o pipefail -c 'curl --fail --silent --show-error --location https://hermes-agent.nousresearch.com/install.sh | bash'
```

Then reload the shell as directed by that installer and confirm that
`hermes --help` runs. This command and its contents are maintained by Nous
Research, not by Driftless-NoMore404; review the
[official Hermes Agent Quickstart](https://github.com/NousResearch/hermes-agent/blob/main/website/docs/getting-started/quickstart.md)
for current options and troubleshooting.

Nous Research's current [Hermes Desktop guide](https://github.com/NousResearch/hermes-agent/blob/main/website/docs/user-guide/desktop.md)
documents Desktop on Linux as well as macOS and Windows. NoMore404 still does
not install, modify, schedule, or independently launch Hermes Desktop. Its
automatic follower simply notices a native Hermes Desktop process started by
the user. Hermes Desktop's own **Settings → Providers → Local Models** flow is
a separate runtime manager; choose it or NoMore404 for a session, not both.

## Connect Hermes to NoMore404

If you accepted setup's model-picker prompt, your alias is already registered.
If you skipped it, or later add aliases to `models.ini`, run:

```bash
no-more-404 register-hermes
```

This uses Hermes's own configuration command to add or update only the
`NoMore404 Local` provider. It does not change Hermes's current or default
model. In Hermes Desktop, choose **Refresh models**, then select any alias.
The first message sent with the new selection is the switch request. If the
old local model is busy, llama.cpp waits for that work to finish rather than
killing it; it then unloads the old model, loads the selected model into the
single slot, and continues the queued request. You do not run a separate
switch command.

The endpoint is local only; print it with `no-more-404 endpoint`. Older Hermes
versions without `hermes config set` can use `hermes model` and **Custom
endpoint**. For a manual current-format setup, add this provider to
`config.yaml` without replacing the top-level `model` block:

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

Match `context_length` to the effective `ctx-size` in your preset and use the
same section name you gave in `models.ini`. No API key is needed for the
enforced loopback endpoint. Prefer `hermes model` if your installed Hermes
version expects a different configuration layout.

If you skipped automatic Desktop following during setup, enable it now:

```bash
no-more-404 integrate-hermes-desktop
```

No launcher editing is required. The follower starts only NoMore404's runtime
after you start Hermes and stops only a runtime it owns. Disable it with
`no-more-404 remove-hermes-desktop-integration`. Custom renamed Desktop builds
and the exact lifecycle rules are covered in
[Hermes Desktop integration](HERMES_DESKTOP.md).

## Day to day

```bash
no-more-404 status     # is it running?
no-more-404 logs       # what is it doing?
no-more-404 stop       # stop a manually started runtime
```

The model stays in memory for one minute of inactivity, then the server
releases it. The next request loads it again on demand. Choosing another
NoMore404 alias from Hermes's model picker uses the same on-demand path and
does not require restarting Hermes or NoMore404.

While Hermes is open and automatic following owns the runtime, it will restore
an intentionally stopped target to honour the selected follow behavior. To keep
the runtime off while Hermes stays open, first run
`no-more-404 remove-hermes-desktop-integration`.

## When something is wrong

Run:

```bash
no-more-404 doctor
```

The output is the designed support path: it names the exact check that failed
(missing path, unsupported flag, wrong bind address, placeholder left in a
configuration file, or port in use). If you ask another person for help, share
only the relevant sanitised lines—remove usernames, private paths, model names,
and anything else identifying your machine. The server auto-restarts on crash.
A bounded timer also replaces a live router after consecutive failed health
checks; `no-more-404 restart` remains the manual recovery command when a
request is stuck but `/health` still answers.

Automatic Desktop startup failures are written to `no-more-404 logs`. When the
optional `notify-send` command is available, the follower also shows one local
desktop notice rather than repeatedly interrupting the user.
