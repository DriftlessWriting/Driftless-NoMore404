# Security policy

## Current status

The current supported release line is `1.x`. Driftless-NoMore404 has not had a
complete independent security audit and is not designed for multi-user hosting
or exposure to a local network or the internet.

Security fixes are provided on a best-effort basis for the current `1.x`
series. There is no response-time guarantee.

## Reporting a vulnerability

Do not open a public issue, discussion, pull request, or gist for a suspected
vulnerability. Do not commit a proof of concept, token, private model path, or
unsanitised log to any branch, including a private branch.

Use the repository's **Security** tab and select **Report a vulnerability**.
That private report is visible only to the reporter and repository maintainers.

If the private form is unexpectedly unavailable, retain the report locally.
You may open a content-free issue asking the maintainers to restore the private
reporting route, but do not mention the suspected component, impact,
reproduction steps, or any evidence in that issue.

Include, where relevant:

- the affected commit and operating-system/systemd versions;
- the security impact and the least-destructive reproduction steps;
- whether the issue is reachable only by the local user or across a network;
- sanitised service status and logs; and
- any suggested mitigation.

Remove usernames, home-directory layouts, hostnames, model names and paths,
prompts, responses, access tokens, and other personal data. Never send live
credentials. If a credential may have been exposed, revoke or rotate it before
continuing the report.

Maintainers will keep reports private while they reproduce and fix the issue.
Credit and disclosure timing will be agreed with the reporter. Reporting an
issue does not grant permission to disclose it before that agreement.

## Security model

Driftless-NoMore404 installs a user-level systemd target and an on-demand local
model router. The installer deliberately does not start or enable the runtime.
The project supplies wrappers, example configuration, and service definitions;
it does not contain Hermes Desktop, llama.cpp binaries, model weights, prompts,
or user data. With explicit user action, setup can download a fixed official
llama.cpp release asset directly from GitHub into the user's data directory.

The supported network boundary is loopback only:

- the default bind address is the numeric IPv4 loopback address;
- the wrapper accepts only the explicit numeric loopback addresses
  `127.0.0.1` and `::1`; and
- no firewall rule is treated as a substitute for an explicit loopback bind.

Loopback is an exposure reduction, not authentication. Software running as the
same user, malicious browser content able to reach local services, and a
compromised user session may still contact the endpoint. This package must not be
used where mutually untrusted local users or processes require isolation. Any
future non-loopback mode requires a separate security design, authentication,
transport protection, and review; changing the bind check is not sufficient.

The systemd service runs with the invoking user's authority. Its hardening
options reduce accidental access but do not form a sandbox against hostile
models, a hostile llama.cpp binary, or code already running as that user.
Users are responsible for obtaining trusted binaries and models and checking
their provenance and licences.

The convenience bootstrap at the repository root downloads the fixed release
tag over HTTPS into a private temporary directory and invokes the same
user-level installer shipped in that tag. It never requests elevated
privileges. Piping any network response into a shell still depends on the
integrity of the GitHub account, release tag, TLS connection, and local
machine, so the README also provides an inspect-before-running path.

The optional llama.cpp runtime installer uses fixed official GitHub release
URLs and hard-coded SHA-256 digests recorded in `vendor/llama.cpp.lock`. It
extracts only an archive with the expected top-level directory, rejects links
that resolve outside its private staging directory, requires the upstream
licence and safe executable copies of both `llama-server` and
`llama-fit-params`, and refuses to overwrite an existing malformed runtime
directory. A matching checksum establishes identity with the reviewed release
asset, not a general guarantee that the upstream binaries or their dependencies
are harmless. Runtime downloads ignore per-user curl configuration and use
bounded connection and transfer times. Loader failures are shown locally with
distro-appropriate dependency guidance. The runtime is not silently updated.
Users may instead supply their own trusted compatible build.

Guided setup runs the compatible `llama-fit-params` companion before starting
the temporary server. That utility reads GGUF metadata and projects the selected
fit without allocating model tensors. A failed or timed-out projection stops
before `llama-server` starts and leaves configuration unchanged. If a custom
build lacks a compatible companion, setup uses a coarse physical-RAM ceiling,
does not count swap, and requires explicit confirmation before an obviously
oversized load. Neither method reserves memory or guarantees a later load;
concurrent workloads and backend defects can still cause allocation failure.

The optional Hermes Desktop session adapter accepts an Electron
`chrome-sandbox` helper only when it is an explicitly configured absolute,
non-symlink path to a regular file owned by `root:root` with mode `4755`. Never
make a downloaded or user-owned helper set-user-ID root to satisfy this check;
use the matching operating-system Electron package or stop and repair that
installation. The adapter does not modify the helper and does not fall back to
`--no-sandbox`.

The optional `register-hermes` operation is an explicit configuration change,
not an autostart action. It invokes Hermes's own `config set` command to add or
update only `providers.no-more-404`, records no API key, refuses to take over
that name when it already points to a different endpoint, and verifies that
Hermes's top-level current/default model settings did not change. It sets no
provider-level preferred model and does not write Hermes configuration files
directly. Uninstall preserves this externally owned entry; users can remove it with
`hermes config unset providers.no-more-404`.

## Sensitive data rules

The repository must never contain:

- credentials, API keys, cookies, private keys, or populated runtime
  environment files;
- model weights, private model presets, caches, or model metadata copied from a
  live machine;
- prompts, responses, sessions, memories, research evidence, or user vaults;
- logs, journals, crash dumps, databases, telemetry exports, or screenshots
  containing machine details; or
- personal absolute paths, usernames, email addresses, hostnames, device IDs,
  private network addresses, or generated service state.

Actual configuration belongs outside the checkout with mode `0600`. Model and
cache directories remain user-managed and must not be added to Git. Example
files must contain placeholders only.

Service logs are not a secret store. Commands and health checks must not print
credentials, prompts, responses, complete environment blocks, or model paths.
Guided setup uses only a fixed synthetic one-token prompt. Its response and
llama.cpp probe and projection logs are private temporary files removed before
setup exits; failed setup may show only the final local llama.cpp diagnostic
lines to the user's own terminal.

Repository visibility is not a data-protection control. Account compromise,
CI logs, artifacts, forks, clones, and cached copies can expose committed
history. A secret that reaches a commit must be revoked or rotated; deleting it
in a later commit is not sufficient.

## Before any public release

Every item in [the pre-public checklist](docs/PRE_PUBLIC_CHECKLIST.md) must pass
for the exact commit proposed for release. An unchecked item means the release
is a no-go.
