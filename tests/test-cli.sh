#!/usr/bin/env bash

set -Eeuo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
test_dir="$(mktemp -d)"
trap 'rm -rf -- "$test_dir"' EXIT

fake_bin="$test_dir/bin"
config_home="$test_dir/config"
runtime_dir="$test_dir/runtime"
state_file="$test_dir/systemd-active"
systemctl_log="$test_dir/systemctl.log"
journalctl_log="$test_dir/journalctl.log"
mkdir -p "$fake_bin" "$config_home/no-more-404" "$runtime_dir"

cat >"$config_home/no-more-404/runtime.env" <<'EOF'
BIND_HOST=127.0.0.1
PORT = 15598
ROUTER_START_TIMEOUT_SECONDS=2
EOF
chmod 0600 "$config_home/no-more-404/runtime.env"

cat >"$fake_bin/systemctl" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
[[ "${1:-}" == --user ]] && shift
printf '%s\n' "$*" >>"$FAKE_SYSTEMCTL_LOG"
case "${1:-}" in
  show-environment)
    exit 0
    ;;
  is-active)
    [[ "${2:-}" == --quiet ]] && shift
    [[ -e "$FAKE_SYSTEMD_STATE" ]]
    ;;
  start | restart)
    : >"$FAKE_SYSTEMD_STATE"
    ;;
  stop)
    [[ "${FAKE_STOP_FAIL:-false}" == true ]] && exit 1
    rm -f -- "$FAKE_SYSTEMD_STATE"
    ;;
  show)
    printf '%s\n' "$FAKE_MAIN_PID"
    ;;
  status)
    exit 0
    ;;
  *)
    printf 'unexpected fake systemctl arguments: %s\n' "$*" >&2
    exit 2
    ;;
esac
EOF

cat >"$fake_bin/ss" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
if [[ -e "$FAKE_SYSTEMD_STATE" ]]; then
  printf 'LISTEN 0 128 127.0.0.1:15598 0.0.0.0:* users:(("llama-server",pid=%s,fd=3))\n' "$FAKE_MAIN_PID"
elif [[ "${FAKE_FOREIGN_LISTENER:-false}" == true ]]; then
  printf 'LISTEN 0 128 127.0.0.1:15598 0.0.0.0:* users:(("foreign",pid=9999,fd=3))\n'
fi
EOF

cat >"$fake_bin/curl" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF

cat >"$fake_bin/journalctl" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
printf '%s\n' "$*" >"$FAKE_JOURNALCTL_LOG"
EOF

chmod 0755 \
  "$fake_bin/systemctl" \
  "$fake_bin/ss" \
  "$fake_bin/curl" \
  "$fake_bin/journalctl"
ln -s /usr/bin/bash "$fake_bin/bash"

export PATH="$fake_bin:/usr/bin:/bin"
export XDG_CONFIG_HOME="$config_home"
export XDG_RUNTIME_DIR="$runtime_dir"
export FAKE_SYSTEMD_STATE="$state_file"
export FAKE_MAIN_PID=4242
export FAKE_SYSTEMCTL_LOG="$systemctl_log"
export FAKE_JOURNALCTL_LOG="$journalctl_log"

cli="$repo_root/bin/no-more-404"

[[ "$($cli endpoint)" == 'http://127.0.0.1:15598/v1' ]]

"$cli" logs
grep -Fxq -- \
  '--user --unit no-more-404-router.service --unit no-more-404-watch.service --follow' \
  "$journalctl_log"

"$cli" start >/dev/null
[[ -e "$state_file" ]]
"$cli" restart >/dev/null
[[ -e "$state_file" ]]
"$cli" run -- /bin/true
[[ -e "$state_file" ]]
"$cli" stop
[[ ! -e "$state_file" ]]

"$cli" run -- /bin/true
[[ ! -e "$state_file" ]]

# A cleanup stop failure is reported while the foreground command's status is
# preserved. The caller can therefore distinguish successful work from failed
# lifecycle cleanup without the wrapper rewriting the child result.
set +e
cleanup_output="$(FAKE_STOP_FAIL=true "$cli" run -- /bin/true 2>&1)"
cleanup_status=$?
set -e
[[ "$cleanup_status" == 0 ]]
grep -Fq 'failed to stop no-more-404.target after the foreground command exited' \
  <<<"$cleanup_output"
[[ -e "$state_file" ]]
rm -f -- "$state_file"

export FAKE_FOREIGN_LISTENER=true
set +e
"$cli" start >/dev/null 2>&1
collision_status=$?
set -e
unset FAKE_FOREIGN_LISTENER
[[ "$collision_status" != 0 ]]
[[ ! -e "$state_file" ]]

"$cli" run -- /bin/sleep 1 &
first_wrapper=$!
for _ in {1..20}; do
  [[ -e "$state_file" ]] && break
  sleep 0.05
done
set +e
start_output="$("$cli" start 2>&1)"
start_status=$?
set -e
[[ "$start_status" != 0 ]]
grep -Fq 'start is refused to preserve runtime ownership' <<<"$start_output"
[[ -e "$state_file" ]]

set +e
"$cli" run -- /bin/true >/dev/null 2>&1
second_status=$?
set -e
[[ "$second_status" != 0 ]]
wait "$first_wrapper"
[[ ! -e "$state_file" ]]

"$cli" start >/dev/null
[[ -e "$state_file" ]]
"$cli" stop
[[ ! -e "$state_file" ]]

# A missing restart dependency must be detected before systemctl is allowed to
# disrupt the runtime.
mv "$fake_bin/curl" "$test_dir/fake-curl"
: >"$systemctl_log"
set +e
PATH="$fake_bin" /usr/bin/bash "$cli" restart >/dev/null 2>&1
missing_curl_status=$?
set -e
mv "$test_dir/fake-curl" "$fake_bin/curl"
[[ "$missing_curl_status" != 0 ]]
if grep -Eq '^restart( |$)' "$systemctl_log"; then
  printf 'restart ran before the missing-curl preflight failed\n' >&2
  exit 1
fi

# Invalid readiness configuration is also a preflight error, not a reason to
# restart first and fail afterward.
cp "$config_home/no-more-404/runtime.env" "$test_dir/runtime.env.good"
sed -i 's/ROUTER_START_TIMEOUT_SECONDS=2/ROUTER_START_TIMEOUT_SECONDS=0/' \
  "$config_home/no-more-404/runtime.env"
: >"$systemctl_log"
set +e
"$cli" restart >/dev/null 2>&1
invalid_timeout_status=$?
set -e
mv "$test_dir/runtime.env.good" "$config_home/no-more-404/runtime.env"
[[ "$invalid_timeout_status" != 0 ]]
if grep -Eq '^restart( |$)' "$systemctl_log"; then
  printf 'restart ran before the timeout preflight failed\n' >&2
  exit 1
fi

child_pid_file="$test_dir/child.pid"
"$cli" run -- /bin/bash -c "printf '%s' \"\$\$\" >'$child_pid_file'; trap '' TERM; while true; do sleep 1; done" &
signal_wrapper=$!
for _ in {1..40}; do
  [[ -s "$child_pid_file" ]] && break
  sleep 0.05
done
[[ -s "$child_pid_file" ]]
child_pid="$(<"$child_pid_file")"
kill -TERM "$signal_wrapper"
set +e
wait "$signal_wrapper"
signal_status=$?
set -e
[[ "$signal_status" != 0 ]]
if kill -0 "$child_pid" 2>/dev/null; then
  printf 'signalled child remained alive after wrapper cleanup\n' >&2
  exit 1
fi
[[ ! -e "$state_file" ]]

printf 'CLI lifecycle tests passed\n'
