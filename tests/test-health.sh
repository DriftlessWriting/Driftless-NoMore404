#!/usr/bin/env bash

set -Eeuo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
test_dir="$(mktemp -d)"
trap 'rm -rf -- "$test_dir"' EXIT

fake_bin="$test_dir/bin"
config_home="$test_dir/config"
state_home="$test_dir/state"
watch_log="$test_dir/watch.log"
systemctl_log="$test_dir/systemctl.log"
counter_file="$state_home/no-more-404/health-failures"
target_state="$test_dir/target-active"
router_state="$test_dir/router-active"
mkdir -p "$fake_bin" "$config_home/no-more-404" "$state_home/no-more-404"

cat >"$config_home/no-more-404/runtime.env" <<'EOF'
BIND_HOST=127.0.0.1
PORT=15598
HEALTH_FAILURES_REQUIRED=2
EOF
chmod 0600 "$config_home/no-more-404/runtime.env"

cat >"$fake_bin/systemctl" <<EOF
#!/usr/bin/env bash
set -Eeuo pipefail
[[ "\${1:-}" == --user ]] && shift
printf '%s\n' "\$*" >>"$systemctl_log"
case "\${1:-}" in
  is-active)
    [[ "\${2:-}" == --quiet ]] && shift
    case "\${2:-}" in
      no-more-404.target) [[ -e "$target_state" ]] ;;
      no-more-404-router.service) [[ -e "$router_state" ]] ;;
      *) exit 1 ;;
    esac
    ;;
  restart | start)
    printf '%s\n' "\$*" >>"$watch_log"
    ;;
  show-environment)
    exit 0
    ;;
  *)
    exit 0
    ;;
esac
EOF

cat >"$fake_bin/curl" <<EOF
#!/usr/bin/env bash
set -Eeuo pipefail
exit 0
EOF

chmod 0755 "$fake_bin/systemctl" "$fake_bin/curl"
ln -s /usr/bin/bash "$fake_bin/bash"

export PATH="$fake_bin:/usr/bin:/bin"
export XDG_CONFIG_HOME="$config_home"
export XDG_STATE_HOME="$state_home"

watchdog="$repo_root/bin/no-more-404-health"

expect_no_restart() {
  if [[ -s "$watch_log" ]]; then
    printf 'unexpected restart issued: %s\n' "$(cat "$watch_log")" >&2
    exit 1
  fi
}

expect_restart() {
  grep -Fxq 'restart no-more-404.target' "$watch_log" || {
    printf 'expected "restart no-more-404.target" in: %s\n' "$watch_log" >&2
    exit 1
  }
  : >"$watch_log"
}

counter_is() {
  local want="$1"
  local got='(missing)'
  [[ -f "$counter_file" ]] && got="$(<"$counter_file")"
  if [[ "$got" != "$want" ]]; then
    printf 'failure counter is %s, want %s\n' "$got" "$want" >&2
    exit 1
  fi
}

# 1. Runtime inactive: the watchdog must not start or restart anything.
rm -f "$target_state" "$router_state"
: >"$watch_log"
"$watchdog"
expect_no_restart
counter_is 0

# 2. Target active but router inactive: do not defeat deliberate non-restart
#    exits for invalid configuration or missing input, but never hide the
#    broken runtime behind a successful watchdog result.
: >"$target_state"
: >"$watch_log"
set +e
inactive_router_output="$("$watchdog" 2>&1)"
inactive_router_status=$?
set -e
[[ "$inactive_router_status" != 0 ]]
grep -Fq 'router service no-more-404-router.service is inactive while runtime target no-more-404.target is active' \
  <<<"$inactive_router_output"
expect_no_restart
counter_is 0

# 3. Active router answering health checks: no restart, counter stays zero.
: >"$router_state"
: >"$watch_log"
"$watchdog"
expect_no_restart
counter_is 0

# 4. Active router that has wedged: the first failed check records a failure
#    but does not restart yet.
cat >"$fake_bin/curl" <<EOF
#!/usr/bin/env bash
set -Eeuo pipefail
exit 1
EOF
: >"$watch_log"
"$watchdog"
expect_no_restart
counter_is 1

# 5. Second consecutive failure: the watchdog restarts the runtime and
#    resets the counter so a single restart is never re-triggered.
: >"$watch_log"
"$watchdog"
expect_restart
counter_is 0

# 6. A recovery window resets the count: after healthy ticks, a single failed
#    check must not restart.
cat >"$fake_bin/curl" <<EOF
#!/usr/bin/env bash
set -Eeuo pipefail
exit 0
EOF
: >"$watch_log"
"$watchdog"
expect_no_restart
counter_is 0
cat >"$fake_bin/curl" <<EOF
#!/usr/bin/env bash
set -Eeuo pipefail
exit 1
EOF
: >"$watch_log"
"$watchdog"
expect_no_restart
counter_is 1

# 7. If the threshold is omitted, the documented default of two still applies.
sed -i '/^HEALTH_FAILURES_REQUIRED=/d' "$config_home/no-more-404/runtime.env"
printf '0\n' >"$counter_file"
: >"$watch_log"
"$watchdog"
expect_no_restart
counter_is 1
"$watchdog"
expect_restart
counter_is 0

# 8. Invalid endpoint configuration is observable and must never trigger a
#    restart of an endpoint the watchdog cannot safely identify.
printf 'BIND_HOST = 0.0.0.0\nPORT = 15598\n' >"$config_home/no-more-404/runtime.env"
: >"$watch_log"
if "$watchdog" >/dev/null 2>&1; then
  printf 'invalid endpoint configuration unexpectedly passed\n' >&2
  exit 1
fi
expect_no_restart
counter_is 0

printf 'health watchdog tests passed\n'
