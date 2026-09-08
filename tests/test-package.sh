#!/usr/bin/env bash

set -Eeuo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
cd "$repo_root"

scripts=(
  install.sh
  bin/no-more-404
  bin/no-more-404-health
  bin/no-more-404-hermes-session
  bin/no-more-404-router
  scripts/*.sh
  tests/*.sh
)
for script in "${scripts[@]}"; do
  bash -n "$script"
done
printf 'bash syntax checks passed\n'

if command -v shellcheck >/dev/null 2>&1; then
  # warning-level: signal handlers and other trap-invoked paths are visible
  # only to the shell runtime, so info-level "unreachable" notes are false
  # positives there; real problems (warnings and errors) still fail the suite.
  shellcheck --severity=warning "${scripts[@]}"
  printf 'ShellCheck passed\n'
else
  printf 'ShellCheck not installed; skipping local lint\n'
fi

if rg --hidden -n '/home/[[:alnum:]_.-]+/|/Users/[[:alnum:]_.-]+/|\.hermes/' . \
  --glob '!tests/test-package.sh' \
  --glob '!.git/**'; then
  printf 'private source path leaked into package\n' >&2
  exit 1
fi

if find . -path ./.git -prune -o -type f -size +1M -print -quit | grep -q .; then
  printf 'package contains a file larger than 1 MiB\n' >&2
  exit 1
fi

if find . -path ./.git -prune -o -type f \( \
  -name '*.gguf' -o -name '*.safetensors' -o -name '*.pt' -o -name '*.pth' \
  -o -name '*.db' -o -name '*.sqlite' -o -name '*.sqlite3' \) -print -quit | grep -q .; then
  printf 'package contains a forbidden model or database artifact\n' >&2
  exit 1
fi

"$repo_root/tests/test-router-wrapper.sh"
"$repo_root/tests/test-cli.sh"
"$repo_root/tests/test-health.sh"
"$repo_root/tests/test-doctor.sh"
"$repo_root/tests/test-setup.sh"
"$repo_root/tests/test-runtime-install.sh"
"$repo_root/tests/test-hermes-registration.sh"
"$repo_root/tests/test-hermes-session.sh"
"$repo_root/tests/test-install.sh"
"$repo_root/tests/test-bootstrap-install.sh"

grep -Fxq 'Restart=on-failure' systemd/user/no-more-404-router.service
grep -Fxq 'StartLimitIntervalSec=300' systemd/user/no-more-404-router.service
grep -Fxq 'StartLimitBurst=5' systemd/user/no-more-404-router.service
grep -Fxq 'RestartPreventExitStatus=64 66 78' systemd/user/no-more-404-router.service
grep -Fxq 'PartOf=no-more-404.target' systemd/user/no-more-404-watch.timer
grep -Fxq 'OnActiveSec=2min' systemd/user/no-more-404-watch.timer
grep -Fxq 'OnUnitActiveSec=2min' systemd/user/no-more-404-watch.timer
grep -Fq 'gitleaks dir --no-banner --redact .' scripts/pre-public-audit.sh
grep -Fq 'gitleaks git --no-banner --redact .' scripts/pre-public-audit.sh
grep -Fq 'rg --hidden --no-ignore' scripts/pre-public-audit.sh
grep -Fq 'name: CI and security checks' .github/workflows/ci.yml
grep -Fq 'no-more-404 setup' docs/QUICKSTART.md
grep -Fq 'no-more-404 install-runtime' docs/OPERATIONS.md
grep -Fxq 'release=b10859' vendor/llama.cpp.lock
grep -Fxq 'required_runtime_executable=llama-server' vendor/llama.cpp.lock
grep -Fxq 'required_setup_preflight=llama-fit-params' vendor/llama.cpp.lock
grep -Fq 'fit-ctx = 64000' config/models.ini.example
if grep -Fq 'n-gpu-layers = all' config/models.ini.example; then
  printf 'example preset must leave GPU placement to llama.cpp auto-fit\n' >&2
  exit 1
fi
grep -Fq 'fetch-depth: 0' .github/workflows/ci.yml
grep -Fq 'persist-credentials: false' .github/workflows/ci.yml
grep -Fq 'command -v systemd-analyze' .github/workflows/ci.yml
grep -Fq 'dir /repo --no-banner --redact --exit-code 1' .github/workflows/ci.yml
grep -Fq 'git /repo --no-banner --redact --exit-code 1' .github/workflows/ci.yml
printf 'bounded restart policy checks passed\n'

if command -v systemd-analyze >/dev/null 2>&1; then
  verify_dir="$(mktemp -d)"
  trap 'rm -rf -- "$verify_dir"' EXIT
  sed 's#ExecStart=%h/.local/libexec/no-more-404/no-more-404-router#ExecStart=/bin/true#' \
    systemd/user/no-more-404-router.service >"$verify_dir/no-more-404-router.service"
  sed 's#ExecStart=%h/.local/libexec/no-more-404/no-more-404-health#ExecStart=/bin/true#' \
    systemd/user/no-more-404-watch.service >"$verify_dir/no-more-404-watch.service"
  cp systemd/user/no-more-404.target "$verify_dir/no-more-404.target"
  cp systemd/user/no-more-404-watch.timer "$verify_dir/no-more-404-watch.timer"
  systemd-analyze verify \
    "$verify_dir/no-more-404-router.service" \
    "$verify_dir/no-more-404-watch.service" \
    "$verify_dir/no-more-404.target" \
    "$verify_dir/no-more-404-watch.timer"
  printf 'systemd unit verification passed\n'
fi

printf 'package tests passed\n'
