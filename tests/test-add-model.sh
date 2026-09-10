#!/usr/bin/env bash

set -Eeuo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
test_dir="$(mktemp -d)"
trap 'rm -rf -- "$test_dir"' EXIT

fake_bin="$test_dir/bin"
test_home="$test_dir/home"
config_home="$test_dir/config"
runtime_dir="$test_dir/runtime"
server_state="$test_dir/server-active"
target_state="$test_dir/target-active"
server_capture="$test_dir/server-arguments"
fit_capture="$test_dir/fit-arguments"
existing_model="$test_dir/existing.gguf"
added_model="$test_dir/another model.gguf"
mkdir -p "$fake_bin" "$test_home" "$config_home/no-more-404" "$runtime_dir"
printf 'existing model fixture\n' >"$existing_model"
printf 'new model fixture\n' >"$added_model"

fake_server="$fake_bin/llama-server"
cat >"$fake_server" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
if [[ "${1:-}" == --help ]]; then
  printf '%s\n' '--model --alias --parallel --fit --fit-target --fit-ctx --flash-attn --jinja --cache-prompt --host --port --timeout --no-webui --no-slots --list-devices --models-preset --models-max --models-autoload --sleep-idle-seconds'
  exit 0
fi
if [[ "${1:-}" == --list-devices ]]; then
  printf '%s\n' 'Available devices:' '  CUDA0: Test GPU (24576 MiB, 22528 MiB free)'
  exit 0
fi
printf '%s\n' "$@" >"$FAKE_SERVER_CAPTURE"
: >"$FAKE_SERVER_STATE"
cleanup() {
  rm -f -- "$FAKE_SERVER_STATE"
  exit 0
}
trap cleanup TERM INT
while true; do
  sleep 1
done
EOF

cat >"$fake_bin/llama-fit-params" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
if [[ "${1:-}" == --help ]]; then
  printf '%s\n' '--model --parallel --fit --fit-target --fit-ctx --flash-attn --verbose'
  exit 0
fi
printf '%s\n' "$@" >"$FAKE_FIT_CAPTURE"
printf '%s\n' \
  'llama_fit_params: successfully fit params to free device and host memory' \
  '-c 131072 -ngl -1'
EOF

cat >"$fake_bin/curl" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
output_path=''
write_output=''
url=''
while (( $# > 0 )); do
  case "$1" in
    --output | --write-out | --header | --data | --max-time)
      case "$1" in
        --output) output_path="$2" ;;
        --write-out) write_output="$2" ;;
      esac
      shift 2
      ;;
    --noproxy)
      shift 2
      ;;
    --fail | --silent | --show-error)
      shift
      ;;
    http://*)
      url="$1"
      shift
      ;;
    *)
      shift
      ;;
  esac
done
case "$url" in
  */health)
    [[ -e "$FAKE_SERVER_STATE" ]]
    ;;
  */props)
    printf '%s\n' '{"default_generation_settings":{"n_ctx":131072}}' >"$output_path"
    ;;
  */v1/chat/completions)
    printf '%s\n' '{"choices":[{"message":{"content":"OK"}}]}' >"$output_path"
    [[ -z "$write_output" ]] || printf '%s' 200
    ;;
  *)
    printf 'unexpected fake curl URL: %s\n' "$url" >&2
    exit 2
    ;;
esac
EOF

cat >"$fake_bin/systemctl" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
[[ "${1:-}" == --user ]] && shift
case "${1:-}" in
  show-environment) exit 0 ;;
  is-active)
    [[ "${2:-}" == --quiet ]] && shift
    [[ "${2:-}" == no-more-404.target && -e "$FAKE_TARGET_STATE" ]]
    ;;
  *) exit 0 ;;
esac
EOF

cat >"$fake_bin/ss" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF

chmod 0755 \
  "$fake_server" \
  "$fake_bin/llama-fit-params" \
  "$fake_bin/curl" \
  "$fake_bin/systemctl" \
  "$fake_bin/ss"

cat >"$config_home/no-more-404/runtime.env" <<EOF
LLAMA_SERVER_BIN="$fake_server"
MODELS_PRESET="$config_home/no-more-404/models.ini"
BIND_HOST=127.0.0.1
PORT=15598
MAX_MODELS=1
IDLE_SECONDS=60
REQUEST_TIMEOUT_SECONDS=1800
ROUTER_START_TIMEOUT_SECONDS=20
EOF
cat >"$config_home/no-more-404/models.ini" <<EOF
version = 1
[*]
ctx-size = 65536
parallel = 1
fit = on
fit-target = 1024
fit-ctx = 64000
flash-attn = auto
jinja = true
cache-prompt = true

[Existing Model]
model = $existing_model
load-on-startup = false
stop-timeout = 90
EOF
chmod 0600 \
  "$config_home/no-more-404/runtime.env" \
  "$config_home/no-more-404/models.ini"

export PATH="$fake_bin:/usr/bin:/bin"
export HOME="$test_home"
export XDG_CONFIG_HOME="$config_home"
export XDG_RUNTIME_DIR="$runtime_dir"
export FAKE_SERVER_STATE="$server_state"
export FAKE_TARGET_STATE="$target_state"
export FAKE_SERVER_CAPTURE="$server_capture"
export FAKE_FIT_CAPTURE="$fit_capture"
cli="$repo_root/bin/no-more-404"

add_output="$(printf '%s\n%s\n' "$added_model" 'Writing Model' | "$cli" add-model)"
grep -Fq 'Added "Writing Model" with the 131072-token context proven on this hardware.' \
  <<<"$add_output"
grep -Fq 'Hermes was not found.' <<<"$add_output"
grep -Fq 'Selecting this alias will switch on its first request.' <<<"$add_output"
grep -Fxq '[Existing Model]' "$config_home/no-more-404/models.ini"
grep -Fxq '[Writing Model]' "$config_home/no-more-404/models.ini"
grep -Fq 'ctx-size = 131072' "$config_home/no-more-404/models.ini"
grep -Fq "model = $added_model" "$config_home/no-more-404/models.ini"
[[ "$(grep -Fc 'load-on-startup = false' "$config_home/no-more-404/models.ini")" == 2 ]]
[[ "$(stat -c '%a' "$config_home/no-more-404/models.ini")" == 600 ]]
grep -Fxq -- --fit "$server_capture"
grep -Fxq -- --fit-ctx "$server_capture"
grep -Fxq -- --model "$fit_capture"
[[ ! -e "$server_state" ]]

# A duplicate picker name is rejected before another model load and leaves the
# previously validated preset byte-for-byte unchanged.
preset_hash="$(sha256sum "$config_home/no-more-404/models.ini")"
rm -f -- "$server_capture"
set +e
duplicate_output="$(printf '%s\n%s\n' "$added_model" 'Writing Model' | "$cli" add-model 2>&1)"
duplicate_status=$?
set -e
[[ "$duplicate_status" != 0 ]]
grep -Fq "model name 'Writing Model' is already configured" <<<"$duplicate_output"
[[ "$(sha256sum "$config_home/no-more-404/models.ini")" == "$preset_hash" ]]
[[ ! -e "$server_capture" ]]

# Adding while Hermes or a manually started runtime owns the model service is
# refused rather than competing for VRAM or disturbing the active model.
: >"$target_state"
set +e
active_output="$("$cli" add-model 2>&1)"
active_status=$?
set -e
[[ "$active_status" != 0 ]]
grep -Fq 'close Hermes Desktop or stop NoMore404 before testing another model' \
  <<<"$active_output"
[[ "$(sha256sum "$config_home/no-more-404/models.ini")" == "$preset_hash" ]]

printf 'guided additional-model tests passed\n'
