#!/usr/bin/env bash

set -Eeuo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
test_directory="$(mktemp -d)"
trap 'rm -rf -- "$test_directory"' EXIT

fake_bin="$test_directory/bin"
binary_path="$test_directory/llama server"
fit_binary_path="$test_directory/llama-fit-params"
server_state="$test_directory/server-active"
argument_capture="$test_directory/server-arguments"
fit_argument_capture="$test_directory/fit-arguments"
mkdir -p "$fake_bin"

cat >"$binary_path" <<'EOF'
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

printf '%s\n' "$@" >"$FAKE_ARGUMENT_CAPTURE"
if [[ "${FAKE_PROBE_MEMORY_FAILURE:-false}" == true ]]; then
  printf '%s\n' 'llama_params_fit: failed to fit params to free device memory' >&2
  exit 1
fi

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

cat >"$fit_binary_path" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail

if [[ "${1:-}" == --help ]]; then
  printf '%s\n' '--model --parallel --fit --fit-target --fit-ctx --flash-attn --verbose'
  exit 0
fi

printf '%s\n' "$@" >"$FAKE_FIT_ARGUMENT_CAPTURE"
if [[ "${FAKE_FIT_MEMORY_FAILURE:-false}" == true ]]; then
  printf '%s\n' 'llama_fit_params: failed to fit params to available memory' >&2
  exit 1
fi
printf '%s\n' \
  'llama_fit_params: projected to use 4096 MiB of 32768 MiB host memory' \
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
    printf '{"default_generation_settings":{"n_ctx":%s}}\n' \
      "${FAKE_CONTEXT:-131072}" >"$output_path"
    ;;
  */v1/chat/completions)
    printf '%s\n' '{"choices":[{"message":{"content":"OK"}}]}' >"$output_path"
    [[ -z "$write_output" ]] || printf '%s' "${FAKE_CHAT_HTTP_CODE:-200}"
    ;;
  *)
    printf 'unexpected fake curl URL: %s\n' "$url" >&2
    exit 2
    ;;
esac
EOF

cat >"$fake_bin/ss" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF

cat >"$fake_bin/uname" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' x86_64
EOF

cat >"$fake_bin/awk" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail

last_argument="${!#}"
if [[ -n "${FAKE_MEM_AVAILABLE_MIB:-}" && "$last_argument" == /proc/meminfo &&
  "${1:-}" == *MemAvailable* ]]; then
  printf '%s\n' "$FAKE_MEM_AVAILABLE_MIB"
  exit 0
fi
exec /usr/bin/awk "$@"
EOF

chmod 0755 \
  "$binary_path" \
  "$fit_binary_path" \
  "$fake_bin/awk" \
  "$fake_bin/curl" \
  "$fake_bin/ss" \
  "$fake_bin/uname"

prepare_home() {
  local test_home="$1"
  local config_directory="$test_home/.config/no-more-404"
  mkdir -p "$config_directory"
  cp "$repo_root/config/runtime.env.example" "$config_directory/runtime.env"
  cp "$repo_root/config/models.ini.example" "$config_directory/models.ini"
  chmod 0600 "$config_directory/runtime.env" "$config_directory/models.ini"
}

run_setup() {
  local test_home="$1"
  local model_path="$2"
  shift 2
  printf '%s\n%s\n%s\n' "$binary_path" "$model_path" 'my-local-model' |
    HOME="$test_home" \
      XDG_CONFIG_HOME="$test_home/.config" \
      PATH="$fake_bin:/usr/bin:/bin" \
      FAKE_SERVER_STATE="$server_state" \
      FAKE_ARGUMENT_CAPTURE="$argument_capture" \
      FAKE_FIT_ARGUMENT_CAPTURE="$fit_argument_capture" \
      "$@" \
      "$repo_root/bin/no-more-404" setup
}

test_home="$test_directory/home with spaces"
config_directory="$test_home/.config/no-more-404"
model_path="$test_home/model file.gguf"
prepare_home "$test_home"
printf 'synthetic model fixture\n' >"$model_path"

setup_output="$(run_setup "$test_home" "$model_path" env)"

grep -Fq 'No persistent service or Hermes process will be started.' <<<"$setup_output"
grep -Fq 'A temporary local model test will run' <<<"$setup_output"
grep -Fq 'Memory preflight passed without loading model weights.' <<<"$setup_output"
grep -Fq 'Model test passed. llama.cpp selected a 131072-token context' <<<"$setup_output"
grep -Fq 'Configuration saved without starting the runtime.' <<<"$setup_output"
grep -Fq 'Hermes was not found. After installing it, run:' <<<"$setup_output"
grep -Fq "LLAMA_SERVER_BIN=\"$binary_path\"" "$config_directory/runtime.env"
grep -Fq "MODELS_PRESET=\"$config_directory/models.ini\"" \
  "$config_directory/runtime.env"
grep -Fxq '[my-local-model]' "$config_directory/models.ini"
grep -Fq 'ctx-size = 131072' "$config_directory/models.ini"
grep -Fq 'fit = on' "$config_directory/models.ini"
grep -Fq 'fit-target = 1024' "$config_directory/models.ini"
grep -Fq 'fit-ctx = 64000' "$config_directory/models.ini"
grep -Fq "model = $model_path" "$config_directory/models.ini"
! grep -Fq 'n-gpu-layers' "$config_directory/models.ini"
! grep -Fq '/absolute/path/to' \
  "$config_directory/runtime.env" "$config_directory/models.ini"
[[ "$(stat -c '%a' "$config_directory/runtime.env")" == 600 ]]
[[ "$(stat -c '%a' "$config_directory/models.ini")" == 600 ]]
grep -Fxq -- --fit "$argument_capture"
grep -Fxq -- --fit-target "$argument_capture"
grep -Fxq -- --fit-ctx "$argument_capture"
if grep -Fxq -- --ctx-size "$argument_capture"; then
  printf 'setup forced a context instead of allowing llama.cpp to fit it\n' >&2
  exit 1
fi
grep -Fxq -- --model "$fit_argument_capture"
grep -Fxq -- --parallel "$fit_argument_capture"
grep -Fxq -- --fit "$fit_argument_capture"
grep -Fxq -- --fit-target "$fit_argument_capture"
grep -Fxq -- --fit-ctx "$fit_argument_capture"
grep -Fxq -- --flash-attn "$fit_argument_capture"
grep -Fxq -- --verbose "$fit_argument_capture"
[[ ! -e "$server_state" ]]

runtime_hash="$(sha256sum "$config_directory/runtime.env")"
model_hash="$(sha256sum "$config_directory/models.ini")"
set +e
second_output="$(
  HOME="$test_home" \
    XDG_CONFIG_HOME="$test_home/.config" \
    PATH="$fake_bin:/usr/bin:/bin" \
    "$repo_root/bin/no-more-404" setup 2>&1
)"
second_status=$?
set -e
[[ "$second_status" != 0 ]]
grep -Fq 'configuration already appears customised' <<<"$second_output"
[[ "$(sha256sum "$config_directory/runtime.env")" == "$runtime_hash" ]]
[[ "$(sha256sum "$config_directory/models.ini")" == "$model_hash" ]]

# Pressing Enter when no llama-server is on PATH reuses or installs the pinned
# official runtime and continues the same guided setup.
provision_home="$test_directory/provision-home"
provision_model="$provision_home/model.gguf"
provision_runtime_directory="$provision_home/.local/share/no-more-404/llama.cpp/b10859-vulkan-x64"
prepare_home "$provision_home"
mkdir -p "$provision_runtime_directory"
cp "$binary_path" "$provision_runtime_directory/llama-server"
cp "$fit_binary_path" "$provision_runtime_directory/llama-fit-params"
printf '%s\n' 'Synthetic upstream licence fixture.' >"$provision_runtime_directory/LICENSE"
chmod 0700 \
  "$provision_runtime_directory" \
  "$provision_runtime_directory/llama-server" \
  "$provision_runtime_directory/llama-fit-params"
printf 'synthetic provisioned-runtime model\n' >"$provision_model"
provision_output="$(
  printf '\n%s\n%s\n' "$provision_model" 'provisioned-model' |
    HOME="$provision_home" \
      XDG_CONFIG_HOME="$provision_home/.config" \
      PATH="$fake_bin:/usr/bin:/bin" \
      FAKE_SERVER_STATE="$server_state" \
      FAKE_ARGUMENT_CAPTURE="$argument_capture" \
      FAKE_FIT_ARGUMENT_CAPTURE="$fit_argument_capture" \
      "$repo_root/bin/no-more-404" setup 2>&1
)"
grep -Fq 'Using the already installed pinned llama.cpp runtime' <<<"$provision_output"
grep -Fq 'Model test passed. llama.cpp selected a 131072-token context' <<<"$provision_output"
grep -Fq "LLAMA_SERVER_BIN=\"$provision_runtime_directory/llama-server\"" \
  "$provision_home/.config/no-more-404/runtime.env"
grep -Fxq '[provisioned-model]' "$provision_home/.config/no-more-404/models.ini"

# A model whose own usable context is below Hermes's floor is rejected without
# changing either configuration file.
short_home="$test_directory/short-context-home"
short_model="$short_home/short.gguf"
prepare_home "$short_home"
printf 'synthetic short-context model\n' >"$short_model"
set +e
short_output="$(run_setup "$short_home" "$short_model" env FAKE_CONTEXT=32768 2>&1)"
short_status=$?
set -e
[[ "$short_status" != 0 ]]
grep -Fq 'reported a 32768-token context' <<<"$short_output"
grep -Fq 'whose GGUF metadata and published documentation support at least 64K context' \
  <<<"$short_output"
grep -Fq '/absolute/path/to/llama-server' "$short_home/.config/no-more-404/runtime.env"
grep -Fq 'ctx-size = 0' "$short_home/.config/no-more-404/models.ini"

# The no-load projection blocks a memory-fit failure before llama-server starts,
# gives model-neutral file-size guidance, and leaves configuration untouched.
preflight_home="$test_directory/preflight-memory-failure-home"
preflight_model="$preflight_home/oversized.gguf"
prepare_home "$preflight_home"
truncate -s 8G "$preflight_model"
rm -f -- "$argument_capture"
set +e
preflight_output="$(
  run_setup "$preflight_home" "$preflight_model" env FAKE_FIT_MEMORY_FAILURE=true 2>&1
)"
preflight_status=$?
set -e
[[ "$preflight_status" != 0 ]]
grep -Fq 'Memory preflight failed before llama-server was started.' <<<"$preflight_output"
grep -Fq 'failed to fit params to available memory' <<<"$preflight_output"
grep -Fq 'try a GGUF around' <<<"$preflight_output"
grep -Fq 'not a model recommendation' <<<"$preflight_output"
[[ ! -e "$argument_capture" ]]
grep -Fq '/absolute/path/to/llama-server' \
  "$preflight_home/.config/no-more-404/runtime.env"
grep -Fq 'ctx-size = 0' "$preflight_home/.config/no-more-404/models.ini"

# A later allocation failure remains visible and safe if free memory changes
# between the no-load projection and the temporary load.
memory_home="$test_directory/memory-failure-home"
memory_model="$memory_home/oversized.gguf"
prepare_home "$memory_home"
truncate -s 8G "$memory_model"
set +e
memory_output="$(
  run_setup "$memory_home" "$memory_model" env FAKE_PROBE_MEMORY_FAILURE=true 2>&1
)"
memory_status=$?
set -e
[[ "$memory_status" != 0 ]]
grep -Fq 'failed to fit params to free device memory' <<<"$memory_output"
grep -Fq 'try a GGUF around' <<<"$memory_output"
grep -Fq 'not a model recommendation' <<<"$memory_output"
grep -Fq '/absolute/path/to/llama-server' "$memory_home/.config/no-more-404/runtime.env"
grep -Fq 'ctx-size = 0' "$memory_home/.config/no-more-404/models.ini"

# A custom llama-server without the companion estimator gets a conservative
# physical-RAM check. An obviously oversized split GGUF is blocked by default,
# and an expert can explicitly approve the temporary load.
fallback_directory="$test_directory/custom-runtime"
fallback_binary="$fallback_directory/llama-server"
fallback_home="$test_directory/fallback-home"
fallback_model="$fallback_home/split-00001-of-00002.gguf"
mkdir -p "$fallback_directory"
cp "$binary_path" "$fallback_binary"
chmod 0755 "$fallback_binary"
prepare_home "$fallback_home"
truncate -s 4G "$fallback_model"
truncate -s 4G "$fallback_home/split-00002-of-00002.gguf"
rm -f -- "$argument_capture"
set +e
fallback_output="$(
  printf '%s\n%s\n%s\n\n' "$fallback_binary" "$fallback_model" 'fallback-model' |
    HOME="$fallback_home" \
      XDG_CONFIG_HOME="$fallback_home/.config" \
      PATH="$fake_bin:/usr/bin:/bin" \
      FAKE_MEM_AVAILABLE_MIB=8192 \
      FAKE_SERVER_STATE="$server_state" \
      FAKE_ARGUMENT_CAPTURE="$argument_capture" \
      FAKE_FIT_ARGUMENT_CAPTURE="$fit_argument_capture" \
      "$repo_root/bin/no-more-404" setup 2>&1
)"
fallback_status=$?
set -e
[[ "$fallback_status" != 0 ]]
grep -Fq 'companion executable not found' <<<"$fallback_output"
grep -Fq 'swap is not counted' <<<"$fallback_output"
grep -Fq 'GGUF set is approximately 8.0 GiB' <<<"$fallback_output"
grep -Fq 'make the desktop unresponsive' <<<"$fallback_output"
grep -Fq 'cancelled before llama-server was started' <<<"$fallback_output"
[[ ! -e "$argument_capture" ]]
grep -Fq '/absolute/path/to/llama-server' "$fallback_home/.config/no-more-404/runtime.env"

override_home="$test_directory/fallback-override-home"
override_model="$override_home/oversized.gguf"
prepare_home "$override_home"
truncate -s 8G "$override_model"
override_output="$(
  printf '%s\n%s\n%s\nyes\n' "$fallback_binary" "$override_model" 'override-model' |
    HOME="$override_home" \
      XDG_CONFIG_HOME="$override_home/.config" \
      PATH="$fake_bin:/usr/bin:/bin" \
      FAKE_MEM_AVAILABLE_MIB=8192 \
      FAKE_SERVER_STATE="$server_state" \
      FAKE_ARGUMENT_CAPTURE="$argument_capture" \
      FAKE_FIT_ARGUMENT_CAPTURE="$fit_argument_capture" \
      "$repo_root/bin/no-more-404" setup 2>&1
)"
grep -Fq 'explicitly approved the temporary load' <<<"$override_output"
grep -Fq 'Model test passed. llama.cpp selected a 131072-token context' <<<"$override_output"
grep -Fxq '[override-model]' "$override_home/.config/no-more-404/models.ini"
[[ ! -e "$server_state" ]]

printf 'initial setup and automatic sizing tests passed\n'
