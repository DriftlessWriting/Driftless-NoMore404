#!/usr/bin/env bash

set -Eeuo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
test_dir="$(mktemp -d)"
trap 'rm -rf -- "$test_dir"' EXIT

fake_bin="$test_dir/bin"
test_home="$test_dir/home"
config_home="$test_home/.config"
runtime_dir="$test_dir/runtime"
systemctl_log="$test_dir/systemctl.log"
enabled_state="$test_dir/follower-enabled"
active_state="$test_dir/follower-active"
fake_server="$test_dir/llama-server"
fake_model="$test_dir/model.gguf"
mkdir -p \
  "$fake_bin" \
  "$config_home/no-more-404" \
  "$config_home/systemd/user" \
  "$runtime_dir"
: >"$systemctl_log"
: >"$fake_server"
: >"$fake_model"
chmod 0755 "$fake_server"
cp "$repo_root/systemd/user/no-more-404-hermes-follower.service" \
  "$config_home/systemd/user/no-more-404-hermes-follower.service"

cat >"$config_home/no-more-404/runtime.env" <<EOF
LLAMA_SERVER_BIN="$fake_server"
MODELS_PRESET="$config_home/no-more-404/models.ini"
BIND_HOST=127.0.0.1
PORT=15598
EOF
cat >"$config_home/no-more-404/models.ini" <<EOF
version = 1
[*]
ctx-size = 65536
fit = on
fit-target = 1024
fit-ctx = 64000
[chosen-model]
model = $fake_model
load-on-startup = false
EOF
chmod 0600 \
  "$config_home/no-more-404/runtime.env" \
  "$config_home/no-more-404/models.ini"

cat >"$fake_bin/systemctl" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
[[ "${1:-}" == --user ]] && shift
printf '%s\n' "$*" >>"$FAKE_SYSTEMCTL_LOG"
case "${1:-}" in
  show-environment | daemon-reload) exit 0 ;;
  enable)
    [[ "${2:-}" == --now && "${3:-}" == no-more-404-hermes-follower.service ]]
    : >"$FAKE_ENABLED_STATE"
    : >"$FAKE_ACTIVE_STATE"
    ;;
  disable)
    [[ "${2:-}" == --now && "${3:-}" == no-more-404-hermes-follower.service ]]
    rm -f -- "$FAKE_ENABLED_STATE" "$FAKE_ACTIVE_STATE"
    ;;
  is-enabled)
    [[ "${2:-}" == --quiet ]] && shift
    [[ "${2:-}" == no-more-404-hermes-follower.service && -e "$FAKE_ENABLED_STATE" ]]
    ;;
  is-active)
    [[ "${2:-}" == --quiet ]] && shift
    [[ "${2:-}" == no-more-404-hermes-follower.service && -e "$FAKE_ACTIVE_STATE" ]]
    ;;
  status) exit 0 ;;
  *)
    printf 'unexpected fake systemctl arguments: %s\n' "$*" >&2
    exit 2
    ;;
esac
EOF
chmod 0755 "$fake_bin/systemctl"

export HOME="$test_home"
export XDG_CONFIG_HOME="$config_home"
export XDG_RUNTIME_DIR="$runtime_dir"
export PATH="$fake_bin:/usr/bin:/bin"
export FAKE_SYSTEMCTL_LOG="$systemctl_log"
export FAKE_ENABLED_STATE="$enabled_state"
export FAKE_ACTIVE_STATE="$active_state"
cli="$repo_root/bin/no-more-404"

integration_output="$($cli integrate-hermes-desktop)"
grep -Fq 'Automatic Hermes Desktop integration is enabled.' <<<"$integration_output"
grep -Fq 'it will never start Hermes itself' <<<"$integration_output"
[[ -e "$enabled_state" && -e "$active_state" ]]
grep -Fxq 'enable --now no-more-404-hermes-follower.service' "$systemctl_log"

removal_output="$($cli remove-hermes-desktop-integration)"
grep -Fq 'Automatic Hermes Desktop integration is disabled.' <<<"$removal_output"
[[ ! -e "$enabled_state" && ! -e "$active_state" ]]
grep -Fxq 'disable --now no-more-404-hermes-follower.service' "$systemctl_log"

# Placeholder configuration is rejected before systemd can enable anything.
sed -i "s#LLAMA_SERVER_BIN=.*#LLAMA_SERVER_BIN=\"/absolute/path/to/llama-server\"#" \
  "$config_home/no-more-404/runtime.env"
: >"$systemctl_log"
set +e
placeholder_output="$($cli integrate-hermes-desktop 2>&1)"
placeholder_status=$?
set -e
[[ "$placeholder_status" != 0 ]]
grep -Eq "configure an executable llama-server|finish 'no-more-404 setup'" \
  <<<"$placeholder_output"
if grep -Eq '^enable( |$)' "$systemctl_log"; then
  printf 'invalid integration enabled the follower service\n' >&2
  exit 1
fi

printf 'Hermes Desktop integration command tests passed\n'
