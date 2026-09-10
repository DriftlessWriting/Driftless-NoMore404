# Pre-public safety checklist

## Release rule

Before the first public release, keep the repository private until this
checklist passes for the exact commit proposed for release.

Every required box must be checked with evidence. Any unchecked item is a
**NO-GO**. There are no exceptions for a credential finding, a non-loopback
listener, unbounded restart behaviour, destructive installation, or an
unreversible uninstall.

Record the candidate before starting:

```text
Candidate commit:
Reviewer:
Review date:
Test distribution and systemd version:
Decision: NO-GO
Evidence location:
```

## 1. Freeze and inspect the package boundary

- [ ] The candidate is a clean, dedicated checkout. It was not created by
      initialising Git inside a live Hermes installation, user configuration
      directory, model directory, or data directory.
- [ ] `git status --short` is empty, and the recorded candidate commit matches
      `git rev-parse HEAD`.
- [ ] `git ls-files` has been reviewed as an allowlist. Every tracked file is
      source, a generic example, a test, or project documentation.
- [ ] No generated unit, populated configuration, backup, log, journal,
      database, session export, cache, model artifact, binary, or build output
      is tracked.
- [ ] No tracked file exceeds the package's one-megabyte audit limit.
- [ ] Repository name, organisation, commit author name, and commit email have
      been consciously approved for public attribution.
- [ ] Images and recordings, if any, have been visually reviewed and stripped
      of metadata and machine-identifying details.

Evidence commands:

```bash
git status --short
git rev-parse HEAD
git ls-files
git log --all --format='%h %an <%ae>'
```

## 2. Secrets and privacy

- [ ] `./scripts/pre-public-audit.sh` passes with Gitleaks installed. A warning
      that Gitleaks is missing is not acceptable for a public release.
- [ ] A Gitleaks directory scan passes, covering files that may not yet be in
      Git.
- [ ] A Gitleaks history scan passes across every branch and tag.
- [ ] A second scanner passes in offline/no-verification mode so candidate
      values are not sent to credential issuers during the audit.
- [ ] A human has reviewed the complete staged diff and history for secrets and
      personal context that pattern matching can miss.
- [ ] There are no populated environment files, credentials, cookies, private
      keys, personal paths, usernames, hostnames, private addresses, model
      names, model paths, prompts, responses, or research details.
- [ ] Examples contain unmistakably fictional placeholders and no value copied
      from a live machine.
- [ ] CI logs and artifacts have been checked for data printed during prior
      runs.

Suggested local scans:

```bash
./scripts/pre-public-audit.sh --require-private
gitleaks dir --no-banner --redact .
gitleaks git --no-banner --redact .
detect-secrets scan --all-files --no-verify
git log --all -p -- .
```

Do not paste scanner findings into an issue or CI log. Review them locally. If
a real credential is found, stop, revoke or rotate it, remove it from all Git
history, and repeat every scan before pushing again.

## 3. Configuration and model boundary

- [ ] Only `*.example` configuration is tracked; installed, populated
      configuration remains outside the checkout with mode `0600`.
- [ ] Every example path is a placeholder and the package refuses to run while
      placeholders remain.
- [ ] No model weights, model cache, private preset, or model-derived metadata
      is tracked or distributed.
- [ ] No model is configured to preload at service start.
- [ ] Exactly one model can be resident, a busy worker is allowed to finish
      before a picker-requested replacement, and the documented idle policy
      releases it without requiring a machine restart.
- [ ] The package does not name, rank, download, or favour any model; every
      picker alias comes only from the user's own preset. Memory-fit failure may
      recommend only a conservative approximate GGUF file-size ceiling.
- [ ] Every registered alias has an effective context of at least 64,000 tokens,
      matching the current Hermes minimum. Guided setup begins from the model's
      context, rejects a fitted result below that floor, and registers the
      actual value reported by llama.cpp.
- [ ] Hermes picker registration is an explicit choice, changes only
      `providers.no-more-404` through Hermes's CLI, stores no API key, and does
      not set or change any global or provider-level preferred model.
- [ ] Registration refuses an existing `providers.no-more-404` entry that points
      to a different endpoint, and this refusal is tested without modifying it.
- [ ] The pinned llama.cpp release and revision are deliberate, reproducible,
      and tested. Every optional runtime asset and SHA-256 digest matches the
      official release, and no source, binary, or model is bundled by the lock
      file.
- [ ] Runtime download is explicit, checksum-verified, retains the upstream
      licence, requires both `llama-server` and `llama-fit-params`, rejects
      unsafe archive paths and links, and is covered by success, reuse,
      incomplete-runtime, and checksum-failure tests.
- [ ] Public documentation accurately distinguishes Hermes Desktop's managed
      Local Models flow from NoMore404 and warns against simultaneous ownership
      of the same server or model load.
- [ ] Model and upstream software licences have been reviewed for every
      artifact mentioned in public documentation.

## 4. Loopback and local-threat tests

- [ ] The example configuration uses an explicit loopback address.
- [ ] Wildcard, LAN, and other non-loopback bind values are rejected before
      llama.cpp starts.
- [ ] If the literal `localhost` option remains supported, it resolves only to
      loopback addresses on every supported platform.
- [ ] With the real service running, `ss -ltnp` confirms the configured port is
      bound only to the intended loopback interface.
- [ ] A health request to the loopback endpoint succeeds.
- [ ] The same request through the machine's LAN address fails.
- [ ] No container, proxy, port-forward, tunnel, or companion service
      republishes the endpoint.
- [ ] Documentation says clearly that loopback is not authentication and does
      not protect against hostile same-user processes or browser-origin
      attacks.
- [ ] Metrics, slot inspection, administrative endpoints, and any web UI are
      disabled by default unless each exposure is necessary and documented.
- [ ] Logs from startup, health checks, failure, and shutdown contain no prompt,
      response, credential, complete environment, or private model path.

Useful runtime evidence:

```bash
no-more-404 doctor
no-more-404 start
no-more-404 endpoint
ss -ltnp
journalctl --user --unit no-more-404-router.service --since today
```

Perform negative network tests with a disposable test model and sanitise all
captured output before retaining it as review evidence.

## 5. Restart and lifecycle safety

- [ ] `Restart=on-failure` is effective; normal and manual stops stay stopped.
- [ ] systemd start-rate limiting is enabled with a finite interval and burst.
- [ ] Configuration and missing-input exit codes are excluded from restart.
- [ ] A deliberately invalid configuration reaches `failed` without a restart
      storm, repeated model loading, or repeated container creation.
- [ ] Start and stop timeouts are finite, and the complete model worker process
      group is terminated on stop.
- [ ] The target is not enabled at login by installation or package metadata.
- [ ] `no-more-404 run -- COMMAND` stops a runtime it started and preserves
      a runtime that was already active.
- [ ] A concurrent `start` or `restart` is rejected while an owning `run`
      session is active, and an ordinary `start` succeeds after that session
      exits.
- [ ] A failed restart preflight (including a missing command, invalid endpoint
      or timeout, ownership contention, or an occupied inactive-target port)
      does not invoke `systemctl restart`.
- [ ] Port collision, missing binary, missing preset, unsupported llama.cpp,
      failed model load, and out-of-memory behaviour have bounded, legible
      failure paths.
- [ ] Automatic sizing is tested for a context above 64K, a model below the 64K
      floor, a no-load projection failure before server start, a later
      allocation failure, split-GGUF size accounting, and conservative fallback
      refusal and override. Every failed path leaves configuration untouched.

Inspect the effective policy rather than only the source file:

```bash
systemctl --user show no-more-404-router.service \
  -p Restart -p RestartUSec -p StartLimitIntervalUSec -p StartLimitBurst
systemctl --user is-enabled no-more-404.target
systemctl --user status no-more-404.target no-more-404-router.service
```

The target must not report as enabled. Run destructive failure simulations only
in a disposable user account or virtual machine.

## 6. systemd and process hardening

- [ ] `./tests/run.sh` passes with both ShellCheck and `systemd-analyze`
      installed; a skipped lint or verification step is not a release pass.
- [ ] `systemd-analyze --user security no-more-404-router.service` has been
      reviewed by a human. Every intentionally unavailable hardening control is
      documented rather than accepted solely to improve a score.
- [ ] The service runs as the current unprivileged user and never requires
      `sudo`, set-user-ID changes, or broad device access.
- [ ] The effective file-creation mask is private, temporary storage is
      isolated, and privilege escalation is disabled.
- [ ] Read and write access is limited as far as compatibility allows; the
      service is not presented as a sandbox for hostile binaries or models.
- [ ] Command-line arguments and environment values do not carry secrets.
- [ ] The optional Hermes session adapter accepts only a trusted, matching
      Electron sandbox helper owned by `root:root` with mode `4755`.
- [ ] The adapter refuses unsafe sandbox paths before starting either Hermes or
      the local-model runtime and never uses `--no-sandbox` as a fallback.
- [ ] The automatic Hermes follower inspects only same-user process metadata,
      never launches or modifies Hermes, and ignores Electron helper processes.
- [ ] The follower acquires the lifecycle lock, refuses a preoccupied port,
      waits for router health, and stops only a target it started.
- [ ] Automatic following is enabled only after the user's explicit setup
      choice or `integrate-hermes-desktop` command and has a tested disable path.

## 7. Install, upgrade, and uninstall round trip

Run this section in a clean disposable account or virtual machine with a user
systemd manager.

- [ ] `./scripts/install.sh --dry-run` reports only package-owned user paths and
      changes nothing.
- [ ] `./scripts/install.sh` does not start or enable a service; the public
      bootstrap enters setup only for untouched first-run configuration.
- [ ] Installation creates private configuration/state directories and mode
      `0600` configuration files.
- [ ] Installation refuses to overwrite changed managed files without the
      explicit upgrade option.
- [ ] Upgrade backs up changed managed files before replacement.
- [ ] Re-running install and upgrade is deterministic and does not duplicate
      state.
- [ ] The install manifest contains only the ten package-managed executable
      and unit files, with their hashes.
- [ ] `./scripts/uninstall.sh --dry-run` changes nothing.
- [ ] Uninstall disables the automatic Desktop follower, stops the package
      target, removes only unchanged manifest-owned files, and preserves
      locally modified files.
- [ ] Configuration, model presets, models, caches, state, and backups survive
      uninstall by default.
- [ ] Uninstall preserves the externally owned Hermes provider entry and the
      documentation gives its explicit `hermes config unset` removal command.
- [ ] Uninstall preserves an optionally downloaded llama.cpp runtime, and the
      documentation makes its separate ownership and removal boundary clear.
- [ ] Missing or corrupt manifests cause a safe refusal rather than guessed
      deletion.
- [ ] The final systemd daemon reload succeeds and no package service remains
      running or enabled.
- [ ] A before/after filesystem and unit-state comparison shows no unapproved
      change.

No release process may use broad recursive deletion, system-wide package
removal, Docker pruning, or deletion based only on a shared resource name.

## 8. Repository and release controls

- [ ] The remote is confirmed private for the entire audit and remains private
      until the final decision is recorded.
- [ ] Repository secret scanning and push protection are enabled if the GitHub
      account provides them; local scanning remains mandatory either way.
- [ ] The reviewed workflow template has been activated under
      `.github/workflows/`; an inactive example file is not CI evidence.
- [ ] CI has minimum token permissions, third-party actions are pinned to full
      commit hashes, and untrusted pull-request code cannot access secrets.
- [ ] CI does not upload configuration, logs, scan findings, or runtime state as
      artifacts.
- [ ] Branch protection requires the package tests and secret scan to pass.
- [ ] `SECURITY.md` offers a private reporting route and explicitly tells
      reporters not to put vulnerability details in a public issue.
- [ ] Public documentation states current limitations, loopback risks,
      supported platforms, upstream dependencies, and non-affiliation where
      applicable.
- [ ] The release contains a licence, changelog, immutable tag, and checksums for
      any project-owned downloadable artifacts.
- [ ] The documented one-command bootstrap works anonymously from the exact
      release tag, installs no unreviewed files, requests no elevated
      privileges, reconnects prompts safely to the terminal, and enables only
      the explicitly approved Desktop follower after the model test passes.

Visibility check before the release decision:

```bash
git remote -v
gh repo view --json visibility --jq .visibility
```

The visibility result must remain `PRIVATE` until all sections pass.

## 9. Final go/no-go record

- [ ] All required items above are checked for the recorded commit.
- [ ] Test and scan evidence is retained privately and contains no sensitive
      data.
- [ ] All findings are closed or the candidate is explicitly marked no-go.
- [ ] A second human has reviewed the tracked-file allowlist, network evidence,
      and install/uninstall evidence.
- [ ] The repository owner has approved the visibility change.

```text
Decision: GO / NO-GO
Candidate commit:
Primary reviewer:
Second reviewer:
Decision date:
Open findings:
Evidence location:
Repository owner approval:
```

Change `Decision` to `GO` only after every required check passes. If any file or
commit changes afterward, create a new candidate record and repeat the affected
checks; rerun secrets, privacy, and tracked-file scans in all cases.
