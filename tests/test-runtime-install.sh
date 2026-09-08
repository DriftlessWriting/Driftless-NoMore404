#!/usr/bin/env bash

set -Eeuo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
test_directory="$(mktemp -d)"
trap 'rm -rf -- "$test_directory"' EXIT

archive_root="$test_directory/archive/llama-b10859"
archive_path="$test_directory/llama-b10859-bin-ubuntu-vulkan-x64.tar.gz"
fake_bin="$test_directory/bin"
curl_log="$test_directory/curl.log"
mkdir -p "$archive_root" "$fake_bin"

cat >"$archive_root/llama-server" <<'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" == --help ]]; then
  if [[ "${FAKE_RUNTIME_START_FAILURE:-false}" == true ]]; then
    printf '%s\n' 'llama-server: error while loading shared libraries: libgomp.so.1: cannot open shared object file' >&2
    exit 127
  fi
  printf '%s\n' '--fit-ctx'
  exit 0
fi
if [[ "${1:-}" == --list-devices ]]; then
  printf '%s\n' 'Available devices:' '  (none)'
  exit 0
fi
exit 0
EOF
cat >"$archive_root/llama-fit-params" <<'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" == --help ]]; then
  printf '%s\n' '--model --parallel --fit --fit-target --fit-ctx --flash-attn --verbose'
  exit 0
fi
exit 0
EOF
printf '%s\n' 'Synthetic upstream licence fixture.' >"$archive_root/LICENSE"
chmod 0755 "$archive_root/llama-server" "$archive_root/llama-fit-params"
tar --create --gzip --file "$archive_path" --directory "$test_directory/archive" llama-b10859

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
cp -- "$FAKE_RUNTIME_ARCHIVE" "$output_path"
EOF

cat >"$fake_bin/sha256sum" <<'EOF'
#!/usr/bin/env bash
printf '%s  %s\n' "${FAKE_RUNTIME_SHA:-388320dbb6ca8dfaf9c8b90ee28e8be777f51ea58d22b7d6e21019831dc9e2ad}" "$1"
EOF

chmod 0755 "$fake_bin/curl" "$fake_bin/sha256sum"

test_home="$test_directory/home"
data_home="$test_directory/data"
runtime_binary="$data_home/no-more-404/llama.cpp/b10859-vulkan-x64/llama-server"
common_environment=(
  HOME="$test_home"
  XDG_DATA_HOME="$data_home"
  PATH="$fake_bin:/usr/bin:/bin"
  FAKE_CURL_LOG="$curl_log"
  FAKE_RUNTIME_ARCHIVE="$archive_path"
)

install_output="$(env "${common_environment[@]}" "$repo_root/bin/no-more-404" install-runtime)"
grep -Fq 'Downloading official llama.cpp b10859 (x64 vulkan)' <<<"$install_output"
grep -Fq 'Installed the verified official llama.cpp runtime' <<<"$install_output"
[[ -x "$runtime_binary" ]]
[[ -x "$(dirname "$runtime_binary")/llama-fit-params" ]]
[[ -f "$(dirname "$runtime_binary")/LICENSE" ]]
[[ "$(stat -c '%a' "$data_home/no-more-404/llama.cpp")" == 700 ]]
[[ "$(wc -l <"$curl_log")" == 1 ]]
grep -Fq -- '--disable' "$curl_log"

reuse_output="$(env "${common_environment[@]}" "$repo_root/bin/no-more-404" install-runtime)"
grep -Fq 'Using the already installed pinned llama.cpp runtime' <<<"$reuse_output"
[[ "$(wc -l <"$curl_log")" == 1 ]]

# An existing pinned-runtime directory is never reused without the companion
# no-load memory estimator required by guided setup.
incomplete_data="$test_directory/incomplete-data"
incomplete_destination="$incomplete_data/no-more-404/llama.cpp/b10859-vulkan-x64"
mkdir -p "$incomplete_destination"
cp "$archive_root/llama-server" "$incomplete_destination/llama-server"
printf '%s\n' 'Synthetic upstream licence fixture.' >"$incomplete_destination/LICENSE"
chmod 0700 "$incomplete_destination" "$incomplete_destination/llama-server"
set +e
incomplete_output="$(
  env \
    HOME="$test_directory/incomplete-home" \
    XDG_DATA_HOME="$incomplete_data" \
    PATH="$fake_bin:/usr/bin:/bin" \
    FAKE_CURL_LOG="$curl_log" \
    FAKE_RUNTIME_ARCHIVE="$archive_path" \
    "$repo_root/bin/no-more-404" install-runtime 2>&1
)"
incomplete_status=$?
set -e
[[ "$incomplete_status" != 0 ]]
grep -Fq 'existing pinned runtime is incomplete' <<<"$incomplete_output"

bad_data_home="$test_directory/bad-data"
set +e
checksum_output="$(
  env \
    HOME="$test_directory/bad-home" \
    XDG_DATA_HOME="$bad_data_home" \
    PATH="$fake_bin:/usr/bin:/bin" \
    FAKE_CURL_LOG="$curl_log" \
    FAKE_RUNTIME_ARCHIVE="$archive_path" \
    FAKE_RUNTIME_SHA=0000000000000000000000000000000000000000000000000000000000000000 \
    "$repo_root/bin/no-more-404" install-runtime 2>&1
)"
checksum_status=$?
set -e
[[ "$checksum_status" != 0 ]]
grep -Fq 'failed SHA-256 verification' <<<"$checksum_output"
[[ ! -e "$bad_data_home/no-more-404/llama.cpp/b10859-vulkan-x64" ]]

# A binary that cannot start must expose its loader error and a useful distro
# dependency command instead of silently reducing the failure to incompatibility.
missing_home="$test_directory/missing-runtime-home"
missing_data="$test_directory/missing-runtime-data"
for flavor in vulkan cpu; do
  missing_destination="$missing_data/no-more-404/llama.cpp/b10859-$flavor-x64"
  mkdir -p "$missing_destination"
  cp "$archive_root/llama-server" "$missing_destination/llama-server"
  cp "$archive_root/llama-fit-params" "$missing_destination/llama-fit-params"
  printf '%s\n' 'Synthetic upstream licence fixture.' >"$missing_destination/LICENSE"
  chmod 0700 \
    "$missing_destination" \
    "$missing_destination/llama-server" \
    "$missing_destination/llama-fit-params"
done
set +e
missing_output="$(
  env \
    HOME="$missing_home" \
    XDG_DATA_HOME="$missing_data" \
    PATH="$fake_bin:/usr/bin:/bin" \
    FAKE_CURL_LOG="$curl_log" \
    FAKE_RUNTIME_ARCHIVE="$archive_path" \
    FAKE_RUNTIME_START_FAILURE=true \
    "$repo_root/bin/no-more-404" install-runtime 2>&1
)"
missing_status=$?
set -e
[[ "$missing_status" != 0 ]]
grep -Fq 'error while loading shared libraries: libgomp.so.1' <<<"$missing_output"
grep -Fq 'Install the ordinary runtime libraries for your distribution' <<<"$missing_output"

printf 'verified pinned runtime installation tests passed\n'
