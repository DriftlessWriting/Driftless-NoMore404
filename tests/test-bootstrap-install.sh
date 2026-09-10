#!/usr/bin/env bash

set -Eeuo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
test_directory="$(mktemp -d)"
trap 'rm -rf -- "$test_directory"' EXIT

archive_parent="$test_directory/archive"
archive_root="$archive_parent/Driftless-NoMore404-1.2.2"
archive_path="$test_directory/Driftless-NoMore404-1.2.2.tar.gz"
fake_bin="$test_directory/bin"
test_home="$test_directory/home"
systemctl_log="$test_directory/systemctl.log"
curl_log="$test_directory/curl.log"

mkdir -p "$archive_root" "$fake_bin" "$test_home"
tar --create --file - --exclude=.git --directory "$repo_root" . |
  tar --extract --file - --directory "$archive_root"
tar --create --gzip --file "$archive_path" \
  --directory "$archive_parent" "$(basename "$archive_root")"

cat >"$fake_bin/curl" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
printf '%s\n' "$*" >>"$FAKE_CURL_LOG"
output_path=''
while (( $# > 0 )); do
  case "$1" in
    --output)
      output_path="$2"
      shift 2
      ;;
    *) shift ;;
  esac
done
[[ -n "$output_path" ]]
cp -- "$FAKE_RELEASE_ARCHIVE" "$output_path"
EOF

cat >"$fake_bin/systemctl" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
[[ "${1:-}" == --user ]] && shift
printf '%s\n' "$*" >>"$FAKE_SYSTEMCTL_LOG"
case "${1:-}" in
  show-environment | daemon-reload) exit 0 ;;
  *) printf 'unexpected fake systemctl arguments: %s\n' "$*" >&2; exit 2 ;;
esac
EOF

chmod 0755 "$fake_bin/curl" "$fake_bin/systemctl"

bootstrap_output="$(
  HOME="$test_home" \
    XDG_CONFIG_HOME="$test_home/.config" \
    XDG_STATE_HOME="$test_home/.local/state" \
    PATH="$fake_bin:/usr/bin:/bin" \
    FAKE_RELEASE_ARCHIVE="$archive_path" \
    FAKE_CURL_LOG="$curl_log" \
    FAKE_SYSTEMCTL_LOG="$systemctl_log" \
    "$repo_root/install.sh" --no-setup
)"

grep -Fq 'Downloading Driftless-NoMore404 1.2.2 from GitHub...' \
  <<<"$bootstrap_output"
grep -Fq 'Installed without starting or enabling any service.' \
  <<<"$bootstrap_output"
grep -Fq 'Guided setup was skipped by request.' <<<"$bootstrap_output"
grep -Fq 'Bootstrap completed from the v1.2.2 source release.' \
  <<<"$bootstrap_output"
grep -Fq 'https://github.com/DriftlessWriting/Driftless-NoMore404/archive/refs/tags/v1.2.2.tar.gz' \
  "$curl_log"
[[ -x "$test_home/.local/bin/no-more-404" ]]
[[ -f "$test_home/.config/systemd/user/no-more-404.target" ]]
[[ -f "$test_home/.config/no-more-404/runtime.env" ]]
if grep -Eq '^(start|restart|enable)( |$)' "$systemctl_log"; then
  printf 'bootstrap installer started or enabled a service\n' >&2
  exit 1
fi

dry_run_home="$test_directory/dry-run-home"
mkdir -p "$dry_run_home"
HOME="$dry_run_home" \
  XDG_CONFIG_HOME="$dry_run_home/.config" \
  XDG_STATE_HOME="$dry_run_home/.local/state" \
  PATH="$fake_bin:/usr/bin:/bin" \
  FAKE_RELEASE_ARCHIVE="$archive_path" \
  FAKE_CURL_LOG="$curl_log" \
  FAKE_SYSTEMCTL_LOG="$systemctl_log" \
    "$repo_root/install.sh" --dry-run --no-setup >/dev/null
[[ ! -e "$dry_run_home/.local/bin/no-more-404" ]]

wrong_version_parent="$test_directory/wrong-version"
wrong_version_root="$wrong_version_parent/Driftless-NoMore404-1.2.2"
wrong_version_archive="$test_directory/wrong-version.tar.gz"
wrong_version_home="$test_directory/wrong-version-home"
mkdir -p "$wrong_version_root" "$wrong_version_home"
tar --create --file - --exclude=.git --directory "$repo_root" . |
  tar --extract --file - --directory "$wrong_version_root"
printf '9.9.9\n' >"$wrong_version_root/VERSION"
tar --create --gzip --file "$wrong_version_archive" \
  --directory "$wrong_version_parent" "$(basename "$wrong_version_root")"
set +e
wrong_version_output="$(
  HOME="$wrong_version_home" \
    XDG_CONFIG_HOME="$wrong_version_home/.config" \
    XDG_STATE_HOME="$wrong_version_home/.local/state" \
    PATH="$fake_bin:/usr/bin:/bin" \
    FAKE_RELEASE_ARCHIVE="$wrong_version_archive" \
    FAKE_CURL_LOG="$curl_log" \
    FAKE_SYSTEMCTL_LOG="$systemctl_log" \
    "$repo_root/install.sh" --no-setup 2>&1
)"
wrong_version_status=$?
set -e
[[ "$wrong_version_status" != 0 ]]
grep -Fq 'downloaded release version is 9.9.9, expected 1.2.2' \
  <<<"$wrong_version_output"
[[ ! -e "$wrong_version_home/.local/bin/no-more-404" ]]

printf 'bootstrap installer tests passed\n'
