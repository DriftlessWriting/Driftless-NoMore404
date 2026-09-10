#!/usr/bin/env bash

set -Eeuo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
test_dir="$(mktemp -d)"
follower_pid=''
trap '[[ -z "$follower_pid" ]] || kill "$follower_pid" 2>/dev/null || true; rm -rf -- "$test_dir"' EXIT

fake_bin="$test_dir/bin"
fake_proc="$test_dir/proc"
runtime_dir="$test_dir/runtime"
target_state="$test_dir/target-active"
router_state="$test_dir/router-active"
systemctl_log="$test_dir/systemctl.log"
follower_log="$test_dir/follower.log"
mkdir -p "$fake_bin" "$fake_proc" "$runtime_dir"
: >"$systemctl_log"

cat >"$fake_bin/systemctl" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
[[ "${1:-}" == --user ]] && shift
printf '%s\n' "$*" >>"$FAKE_SYSTEMCTL_LOG"
case "${1:-}" in
  show-environment) exit 0 ;;
  is-active)
    [[ "${2:-}" == --quiet ]] && shift
    case "${2:-}" in
      no-more-404.target) [[ -e "$FAKE_TARGET_STATE" ]] ;;
      no-more-404-router.service) [[ -e "$FAKE_ROUTER_STATE" ]] ;;
      *) exit 3 ;;
    esac
    ;;
  start)
    [[ "${FAKE_START_FAIL:-false}" == true ]] && exit 1
    [[ "${2:-}" == no-more-404.target ]]
    : >"$FAKE_TARGET_STATE"
    : >"$FAKE_ROUTER_STATE"
    ;;
  stop)
    [[ "${2:-}" == no-more-404.target ]]
    rm -f -- "$FAKE_TARGET_STATE" "$FAKE_ROUTER_STATE"
    ;;
  *)
    printf 'unexpected fake systemctl arguments: %s\n' "$*" >&2
    exit 2
    ;;
esac
EOF

cat >"$fake_bin/curl" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
[[ -e "$FAKE_ROUTER_STATE" ]]
EOF

cat >"$fake_bin/ss" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
[[ "${FAKE_FOREIGN_LISTENER:-false}" == true ]] &&
  printf '%s\n' 'LISTEN 0 128 127.0.0.1:15598 0.0.0.0:*'
exit 0
EOF

cat >"$fake_bin/notify-send" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF

chmod 0755 \
  "$fake_bin/systemctl" \
  "$fake_bin/curl" \
  "$fake_bin/ss" \
  "$fake_bin/notify-send"

export PATH="$fake_bin:/usr/bin:/bin"
export XDG_RUNTIME_DIR="$runtime_dir"
export BIND_HOST=127.0.0.1
export PORT=15598
export ROUTER_START_TIMEOUT_SECONDS=2
export NO_MORE_404_PROC_ROOT="$fake_proc"
export NO_MORE_404_HERMES_POLL_SECONDS=0.05
export NO_MORE_404_HERMES_ABSENT_CHECKS_REQUIRED=2
export NO_MORE_404_HERMES_START_RETRY_SECONDS=0.1
export FAKE_TARGET_STATE="$target_state"
export FAKE_ROUTER_STATE="$router_state"
export FAKE_SYSTEMCTL_LOG="$systemctl_log"
follower="$repo_root/bin/no-more-404-hermes-follower"

wait_for_file() {
  local path="$1"
  local attempt
  for ((attempt = 0; attempt < 100; attempt++)); do
    [[ -e "$path" ]] && return 0
    sleep 0.02
  done
  return 1
}

wait_for_absence() {
  local path="$1"
  local attempt
  for ((attempt = 0; attempt < 100; attempt++)); do
    [[ ! -e "$path" ]] && return 0
    sleep 0.02
  done
  return 1
}

create_hermes_process() {
  local pid="$1"
  local role="${2:-main}"
  mkdir -p "$fake_proc/$pid"
  printf 'Hermes\n' >"$fake_proc/$pid/comm"
  if [[ "$role" == main ]]; then
    printf '/opt/hermes/Hermes\0--example\0' >"$fake_proc/$pid/cmdline"
  else
    printf '/opt/hermes/Hermes\0--type=zygote\0' >"$fake_proc/$pid/cmdline"
  fi
}

start_follower() {
  "$follower" >"$follower_log" 2>&1 &
  follower_pid=$!
}

stop_follower() {
  [[ -n "$follower_pid" ]] || return 0
  kill -TERM "$follower_pid"
  wait "$follower_pid"
  follower_pid=''
}

# An Electron helper process alone must not start the runtime.
create_hermes_process 101 helper
start_follower
sleep 0.2
[[ ! -e "$target_state" ]]
rm -rf -- "$fake_proc/101"

# A user-started main Hermes process starts the runtime, holds the lifecycle
# lock, and releases the target shortly after the Desktop process disappears.
create_hermes_process 102 main
wait_for_file "$target_state"
grep -Fxq 'start no-more-404.target' "$systemctl_log"
if flock --nonblock "$runtime_dir/no-more-404-session.lock" true; then
  printf 'Hermes follower did not retain the lifecycle ownership lock\n' >&2
  exit 1
fi
rm -rf -- "$fake_proc/102"
wait_for_absence "$target_state"
grep -Fxq 'stop no-more-404.target' "$systemctl_log"
flock --nonblock "$runtime_dir/no-more-404-session.lock" true
stop_follower

# A target that was already active belongs to someone else and survives the
# complete Hermes session.
: >"$target_state"
: >"$router_state"
: >"$systemctl_log"
create_hermes_process 103 main
start_follower
sleep 0.2
rm -rf -- "$fake_proc/103"
sleep 0.2
[[ -e "$target_state" ]]
if grep -Eq '^(start|stop)( |$)' "$systemctl_log"; then
  printf 'Hermes follower changed a runtime it did not own\n' >&2
  exit 1
fi
stop_follower
rm -f -- "$target_state" "$router_state"

# Lock contention never lets the follower claim another lifecycle operation.
: >"$systemctl_log"
exec {held_lock_fd}>"$runtime_dir/no-more-404-session.lock"
flock --nonblock "$held_lock_fd"
create_hermes_process 104 main
start_follower
sleep 0.25
[[ ! -e "$target_state" ]]
flock --unlock "$held_lock_fd"
exec {held_lock_fd}>&-
wait_for_file "$target_state"
rm -rf -- "$fake_proc/104"
wait_for_absence "$target_state"
stop_follower

# Invalid runtime settings fail as configuration errors before any target is
# started, preventing a restart loop that could disturb Hermes.
: >"$systemctl_log"
set +e
PORT=80 "$follower" >/dev/null 2>&1
invalid_status=$?
set -e
[[ "$invalid_status" == 78 ]]
if grep -Eq '^start( |$)' "$systemctl_log"; then
  printf 'Hermes follower started a target before configuration validation\n' >&2
  exit 1
fi

printf 'Hermes automatic follower tests passed\n'
