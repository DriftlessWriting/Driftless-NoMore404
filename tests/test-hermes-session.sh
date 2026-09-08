#!/usr/bin/env bash

set -Eeuo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
test_dir="$(mktemp -d)"
trap 'rm -rf -- "$test_dir"' EXIT

fake_bin="$test_dir/bin"
workdir="$test_dir/workdir"
sandbox="$test_dir/chrome-sandbox"
runtime_dir="$test_dir/runtime"
target_state="$test_dir/target-active"
systemctl_log="$test_dir/systemctl.log"
app_log="$test_dir/app.log"
mkdir -p "$fake_bin" "$workdir" "$runtime_dir"
: >"$sandbox"

cat >"$fake_bin/stat" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
if [[ "${1:-}" == -Lc && "${2:-}" == %u:%g:%a && "${4:-}" == "$FAKE_SANDBOX_PATH" ]]; then
  printf '%s\n' "${FAKE_SANDBOX_STAT:-0:0:4755}"
  exit 0
fi
exec /usr/bin/stat "$@"
EOF

cat >"$fake_bin/systemctl" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
[[ "${1:-}" == --user ]] && shift
printf '%s\n' "$*" >>"$FAKE_SYSTEMCTL_LOG"
case "${1:-}" in
  show-environment) exit 0 ;;
  is-active) [[ -e "$FAKE_TARGET_STATE" ]] ;;
  start)
    [[ "${FAKE_START_FAIL:-false}" == true ]] && exit 1
    : >"$FAKE_TARGET_STATE"
    ;;
  stop) rm -f -- "$FAKE_TARGET_STATE" ;;
  *) exit 2 ;;
esac
EOF

cat >"$fake_bin/logger" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF

fake_app="$fake_bin/Hermes"
cat >"$fake_app" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
{
  printf 'sandbox=%s\n' "${CHROME_DEVEL_SANDBOX:-}"
  printf 'cwd=%s\n' "$PWD"
  printf 'desktop_cwd=%s\n' "${HERMES_DESKTOP_CWD:-}"
  printf 'disable_gpu=%s\n' "${HERMES_DESKTOP_DISABLE_GPU:-}"
  printf 'password_store=%s\n' "${HERMES_DESKTOP_PASSWORD_STORE:-}"
  printf 'arg=%s\n' "$@"
} >"$FAKE_APP_LOG"
if [[ -n "${FAKE_APP_READY_FILE:-}" ]]; then
  : >"$FAKE_APP_READY_FILE"
  while [[ ! -e "$FAKE_APP_RELEASE_FILE" ]]; do
    sleep 0.05
  done
fi
exit "${FAKE_APP_STATUS:-0}"
EOF

chmod 0755 "$fake_bin/stat" "$fake_bin/systemctl" "$fake_bin/logger" "$fake_app"
ln -s /usr/bin/bash "$fake_bin/bash"

export PATH="$fake_bin:/usr/bin:/bin"
export FAKE_SANDBOX_PATH="$sandbox"
export FAKE_TARGET_STATE="$target_state"
export FAKE_SYSTEMCTL_LOG="$systemctl_log"
export FAKE_APP_LOG="$app_log"
export XDG_RUNTIME_DIR="$runtime_dir"
export HERMES_DESKTOP_BIN="$fake_app"
export HERMES_DESKTOP_WORKDIR="$workdir"
export HERMES_ELECTRON_SANDBOX="$sandbox"
export HERMES_DESKTOP_CWD="$test_dir/home"
export HERMES_DESKTOP_DISABLE_GPU=true
export HERMES_DESKTOP_PASSWORD_STORE=kwallet6
session="$repo_root/bin/no-more-404-hermes-session"

# A user-invoked Hermes session starts an inactive runtime, passes the hardened
# Electron environment and requested launch flags, then stops the owned target.
: >"$systemctl_log"
"$session" --example >/dev/null 2>&1
grep -Fxq 'start no-more-404.target' "$systemctl_log"
grep -Fxq 'stop no-more-404.target' "$systemctl_log"
[[ ! -e "$target_state" ]]
grep -Fxq "sandbox=$sandbox" "$app_log"
grep -Fxq "cwd=$workdir" "$app_log"
grep -Fxq "desktop_cwd=$test_dir/home" "$app_log"
grep -Fxq 'disable_gpu=true' "$app_log"
grep -Fxq 'password_store=kwallet6' "$app_log"
grep -Fxq 'arg=--example' "$app_log"

# A runtime that was already active is preserved when Hermes exits.
: >"$target_state"
: >"$systemctl_log"
"$session" >/dev/null 2>&1
if grep -Eq '^(start|stop)( |$)' "$systemctl_log"; then
  printf 'session changed a runtime it did not own\n' >&2
  exit 1
fi
[[ -e "$target_state" ]]
rm -f -- "$target_state"

# A session that starts the runtime holds the shared ownership lock until
# Hermes exits, preventing a concurrent persistent start from racing cleanup.
ready_file="$test_dir/app-ready"
release_file="$test_dir/app-release"
: >"$systemctl_log"
FAKE_APP_READY_FILE="$ready_file" FAKE_APP_RELEASE_FILE="$release_file" \
  "$session" >/dev/null 2>&1 &
session_pid=$!
for _ in {1..100}; do
  [[ -e "$ready_file" ]] && break
  sleep 0.05
done
[[ -e "$ready_file" ]]
if flock --nonblock "$runtime_dir/no-more-404-session.lock" true; then
  printf 'session did not retain the lifecycle ownership lock\n' >&2
  exit 1
fi
: >"$release_file"
wait "$session_pid"
[[ ! -e "$target_state" ]]

# Existing owning lifecycle work blocks a required Hermes launch before either
# the runtime or Hermes starts.
: >"$systemctl_log"
: >"$app_log"
exec {held_lock_fd}>"$runtime_dir/no-more-404-session.lock"
flock --nonblock "$held_lock_fd"
set +e
"$session" >/dev/null 2>&1
contention_status=$?
set -e
flock --unlock "$held_lock_fd"
exec {held_lock_fd}>&-
[[ "$contention_status" != 0 ]]
if grep -Eq '^start( |$)' "$systemctl_log"; then
  printf 'contended session started the runtime\n' >&2
  exit 1
fi
[[ ! -s "$app_log" ]]

# Hermes failures propagate to the caller while still cleaning up the target.
: >"$systemctl_log"
set +e
FAKE_APP_STATUS=42 "$session" >/dev/null 2>&1
failure_status=$?
set -e
[[ "$failure_status" == 42 ]]
grep -Fxq 'stop no-more-404.target' "$systemctl_log"
[[ ! -e "$target_state" ]]

# An unsafe Electron helper fails closed before the runtime or Hermes starts.
: >"$systemctl_log"
: >"$app_log"
set +e
FAKE_SANDBOX_STAT=1000:1000:755 "$session" >/dev/null 2>&1
sandbox_status=$?
set -e
[[ "$sandbox_status" != 0 ]]
if grep -Eq '^start( |$)' "$systemctl_log"; then
  printf 'session started the runtime before validating the sandbox\n' >&2
  exit 1
fi
[[ ! -s "$app_log" ]]

# The operator can explicitly allow cloud-only Hermes startup if its optional
# helper target fails; required-runtime mode remains fail closed.
: >"$app_log"
FAKE_START_FAIL=true NO_MORE_404_REQUIRE_RUNTIME=false "$session" >/dev/null 2>&1
[[ -s "$app_log" ]]
: >"$app_log"
set +e
FAKE_START_FAIL=true NO_MORE_404_REQUIRE_RUNTIME=true "$session" >/dev/null 2>&1
required_status=$?
set -e
[[ "$required_status" != 0 ]]
[[ ! -s "$app_log" ]]

printf 'Hermes session adapter tests passed\n'
