#!/usr/bin/env bash

set -Eeuo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
test_dir="$(mktemp -d)"
trap 'rm -rf -- "$test_dir"' EXIT

fake_bin="$test_dir/bin"
systemctl_log="$test_dir/systemctl.log"
mkdir -p "$fake_bin"

cat >"$fake_bin/systemctl" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
[[ "${1:-}" == --user ]] && shift
printf '%s\n' "$*" >>"$FAKE_SYSTEMCTL_LOG"
case "${1:-}" in
  show-environment | daemon-reload) exit 0 ;;
  stop)
    [[ "${FAKE_STOP_FAIL:-false}" == true ]] && exit 1
    exit 0
    ;;
  *) printf 'unexpected fake systemctl arguments: %s\n' "$*" >&2; exit 2 ;;
esac
EOF
chmod 0755 "$fake_bin/systemctl"

run_installer() {
  local test_home="$1"
  shift
  HOME="$test_home" \
    XDG_CONFIG_HOME="$test_home/.config" \
    XDG_STATE_HOME="$test_home/.local/state" \
    FAKE_SYSTEMCTL_LOG="$systemctl_log" \
    PATH="$fake_bin:/usr/bin:/bin" \
    "$repo_root/scripts/install.sh" "$@"
}

run_uninstaller() {
  local test_home="$1"
  shift
  HOME="$test_home" \
    XDG_CONFIG_HOME="$test_home/.config" \
    XDG_STATE_HOME="$test_home/.local/state" \
    FAKE_SYSTEMCTL_LOG="$systemctl_log" \
    FAKE_STOP_FAIL="${FAKE_STOP_FAIL:-false}" \
    PATH="$fake_bin:/usr/bin:/bin" \
    "$repo_root/scripts/uninstall.sh" "$@"
}

safe_home="$test_dir/safe-home"
mkdir -p "$safe_home/.local/bin" "$safe_home/.config/systemd/user"
chmod 0700 "$safe_home/.local/bin" "$safe_home/.config/systemd/user"
run_installer "$safe_home" >/dev/null

[[ "$(stat -c '%a' "$safe_home/.local/bin")" == 700 ]]
[[ "$(stat -c '%a' "$safe_home/.config/systemd/user")" == 700 ]]
[[ "$(stat -c '%a' "$safe_home/.local/libexec/no-more-404")" == 755 ]]
[[ "$(stat -c '%a' "$safe_home/.config/no-more-404/runtime.env")" == 600 ]]
[[ "$(stat -c '%a' "$safe_home/.config/no-more-404/models.ini")" == 600 ]]

managed_paths=(
  "$safe_home/.local/bin/no-more-404"
  "$safe_home/.local/libexec/no-more-404/no-more-404-router"
  "$safe_home/.local/libexec/no-more-404/no-more-404-health"
  "$safe_home/.local/libexec/no-more-404/no-more-404-hermes-session"
  "$safe_home/.config/systemd/user/no-more-404.target"
  "$safe_home/.config/systemd/user/no-more-404-router.service"
  "$safe_home/.config/systemd/user/no-more-404-watch.service"
  "$safe_home/.config/systemd/user/no-more-404-watch.timer"
)
for managed_path in "${managed_paths[@]}"; do
  [[ -f "$managed_path" ]]
done
manifest="$safe_home/.local/state/no-more-404/install-manifest.tsv"
[[ "$(wc -l <"$manifest")" == 8 ]]
if grep -Eq '^(start|restart|enable)( |$)' "$systemctl_log"; then
  printf 'installer started or enabled a service\n' >&2
  exit 1
fi

# Reinstallation preserves operator configuration.
printf '# operator setting\n' >>"$safe_home/.config/no-more-404/runtime.env"
run_installer "$safe_home" >/dev/null
grep -Fxq '# operator setting' "$safe_home/.config/no-more-404/runtime.env"

# Changed managed files require an explicit upgrade, and upgrade retains a
# private backup before restoring the package version.
printf '# local managed change\n' >>"$safe_home/.local/bin/no-more-404"
set +e
changed_output="$(run_installer "$safe_home" 2>&1)"
changed_status=$?
set -e
[[ "$changed_status" != 0 ]]
grep -Fq 'refusing to overwrite changed file' <<<"$changed_output"
run_installer "$safe_home" --upgrade >/dev/null
cmp -s "$repo_root/bin/no-more-404" "$safe_home/.local/bin/no-more-404"
backup_path="$(find "$safe_home/.local/state/no-more-404/backups" -type f -name no-more-404 -print -quit)"
[[ -n "$backup_path" ]]
grep -Fq '# local managed change' "$backup_path"

# Dry-run uninstall changes nothing; the real uninstall removes only the
# manifest-owned files and leaves configuration and backups in place.
run_uninstaller "$safe_home" --dry-run >/dev/null
for managed_path in "${managed_paths[@]}"; do
  [[ -f "$managed_path" ]]
done
run_uninstaller "$safe_home" >/dev/null
for managed_path in "${managed_paths[@]}"; do
  [[ ! -e "$managed_path" ]]
done
[[ -f "$safe_home/.config/no-more-404/runtime.env" ]]
[[ -f "$safe_home/.config/no-more-404/models.ini" ]]
[[ -f "$backup_path" ]]
[[ ! -e "$manifest" ]]

# A malformed manifest is rejected before the uninstaller stops anything or
# removes any file.
corrupt_home="$test_dir/corrupt-home"
mkdir -p "$corrupt_home"
run_installer "$corrupt_home" >/dev/null
printf 'not-a-valid-manifest\n' >"$corrupt_home/.local/state/no-more-404/install-manifest.tsv"
: >"$systemctl_log"
set +e
corrupt_output="$(run_uninstaller "$corrupt_home" 2>&1)"
corrupt_status=$?
set -e
[[ "$corrupt_status" != 0 ]]
grep -Fq 'manifest is corrupt' <<<"$corrupt_output"
[[ -f "$corrupt_home/.local/bin/no-more-404" ]]
if grep -Eq '^stop( |$)' "$systemctl_log"; then
  printf 'uninstaller stopped the target before validating its manifest\n' >&2
  exit 1
fi

# A stop failure is reported before any installed file is removed.
stop_failure_home="$test_dir/stop-failure-home"
mkdir -p "$stop_failure_home"
run_installer "$stop_failure_home" >/dev/null
: >"$systemctl_log"
set +e
stop_failure_output="$(FAKE_STOP_FAIL=true run_uninstaller "$stop_failure_home" 2>&1)"
stop_failure_status=$?
set -e
[[ "$stop_failure_status" != 0 ]]
grep -Fq 'failed to stop no-more-404.target; no files were removed' \
  <<<"$stop_failure_output"
[[ -f "$stop_failure_home/.local/bin/no-more-404" ]]
[[ -f "$stop_failure_home/.local/state/no-more-404/install-manifest.tsv" ]]

# Existing non-regular configuration is rejected before managed files are
# copied, avoiding a partial install.
bad_config_home="$test_dir/bad-config-home"
mkdir -p "$bad_config_home/.config/no-more-404/runtime.env"
set +e
bad_config_output="$(run_installer "$bad_config_home" 2>&1)"
bad_config_status=$?
set -e
[[ "$bad_config_status" != 0 ]]
grep -Fq 'configuration path must be a regular file' <<<"$bad_config_output"
[[ ! -e "$bad_config_home/.local/bin/no-more-404" ]]

unsafe_mode_home="$test_dir/unsafe-mode-home"
mkdir -p "$unsafe_mode_home/.local/bin"
chmod 0775 "$unsafe_mode_home/.local/bin"
set +e
unsafe_mode_output="$(run_installer "$unsafe_mode_home" 2>&1)"
unsafe_mode_status=$?
set -e
[[ "$unsafe_mode_status" != 0 ]]
grep -Fq 'must not be group- or world-writable' <<<"$unsafe_mode_output"
[[ ! -e "$unsafe_mode_home/.local/bin/no-more-404" ]]

real_stat="$(command -v stat)"
cat >"$fake_bin/stat" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
last_argument="${!#}"
if [[ "${1:-}" == -Lc && "${2:-}" == %u && "$last_argument" == "$FAKE_WRONG_OWNER_PATH" ]]; then
  printf '%s\n' "$FAKE_WRONG_OWNER_ID"
  exit 0
fi
exec "$REAL_STAT" "$@"
EOF
chmod 0755 "$fake_bin/stat"

unsafe_owner_home="$test_dir/unsafe-owner-home"
mkdir -p \
  "$unsafe_owner_home/.local/bin" \
  "$unsafe_owner_home/.local/libexec/no-more-404" \
  "$unsafe_owner_home/.config/systemd/user"
chmod 0755 \
  "$unsafe_owner_home/.local/bin" \
  "$unsafe_owner_home/.local/libexec/no-more-404" \
  "$unsafe_owner_home/.config/systemd/user"
set +e
unsafe_owner_output="$(
  REAL_STAT="$real_stat" \
    FAKE_WRONG_OWNER_PATH="$unsafe_owner_home/.local/libexec/no-more-404" \
    FAKE_WRONG_OWNER_ID="$((EUID + 1))" \
    run_installer "$unsafe_owner_home" 2>&1
)"
unsafe_owner_status=$?
set -e
[[ "$unsafe_owner_status" != 0 ]]
grep -Fq 'is not owned by the invoking user' <<<"$unsafe_owner_output"
[[ ! -e "$unsafe_owner_home/.local/libexec/no-more-404/no-more-404-router" ]]

printf 'installer round-trip tests passed\n'
