#!/usr/bin/env bash

set -Eeuo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
test_dir="$(mktemp -d)"
trap 'rm -rf -- "$test_dir"' EXIT

fake_bin="$test_dir/bin"
config_home="$test_dir/config"
runtime_dir="$test_dir/runtime"
model_file="$test_dir/model.gguf"
projector_file="$test_dir/projector.gguf"
mkdir -p "$fake_bin" "$config_home/no-more-404" "$config_home/systemd/user" "$runtime_dir"
: >"$model_file"
: >"$projector_file"

fake_server="$fake_bin/llama-server"
cat >"$fake_server" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "${FAKE_HELP_FLAGS:---models-preset --models-max --models-autoload --sleep-idle-seconds --fit --fit-target --fit-ctx --parallel --flash-attn --jinja --cache-prompt --host --port --timeout --no-webui --metrics --slots --no-slots}"
EOF

cat >"$fake_bin/systemctl" <<EOF
#!/usr/bin/env bash
set -Eeuo pipefail
[[ "\${1:-}" == --user ]] && shift
case "\${1:-}" in
  show-environment) exit 0 ;;
  is-enabled)
    printf '%s\n' static
    ;;
  is-active)
    [[ "\${2:-}" == --quiet ]] && shift
    case "\${2:-}" in
      no-more-404.target) [[ -e "$test_dir/target-active" ]] ;;
      no-more-404-router.service) [[ -e "$test_dir/router-active" ]] ;;
      no-more-404-watch.timer) [[ -e "$test_dir/timer-active" ]] ;;
      *) exit 1 ;;
    esac
    ;;
  show)
    printf '%s\n' 4242
    ;;
  *) exit 0 ;;
esac
EOF

cat >"$fake_bin/ss" <<EOF
#!/usr/bin/env bash
if [[ -e "$test_dir/router-active" ]]; then
  printf 'LISTEN 0 128 127.0.0.1:15598 0.0.0.0:* users:(("llama-server",pid=4242,fd=3))\n'
fi
EOF

cat >"$fake_bin/curl" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF

chmod 0755 "$fake_server" "$fake_bin/systemctl" "$fake_bin/ss" "$fake_bin/curl"
ln -s /usr/bin/bash "$fake_bin/bash"
ln -s /usr/bin/flock "$fake_bin/flock"

for unit in \
  no-more-404.target \
  no-more-404-router.service \
  no-more-404-watch.service \
  no-more-404-watch.timer \
  no-more-404-hermes-follower.service; do
  : >"$config_home/systemd/user/$unit"
done

write_good_config() {
  cat >"$config_home/no-more-404/runtime.env" <<EOF
LLAMA_SERVER_BIN="$fake_server"
MODELS_PRESET="$config_home/no-more-404/models.ini"
BIND_HOST=127.0.0.1
PORT=15598
MAX_MODELS=1
IDLE_SECONDS=60
REQUEST_TIMEOUT_SECONDS=1800
ROUTER_START_TIMEOUT_SECONDS=20
HEALTH_FAILURES_REQUIRED=2
ENABLE_METRICS=false
ENABLE_SLOTS=false
EOF
  chmod 0600 "$config_home/no-more-404/runtime.env"
}

write_good_preset() {
  cat >"$config_home/no-more-404/models.ini" <<EOF
version = 1
[*]
ctx-size = 65536
fit = on
fit-target = 1024
fit-ctx = 64000

[test]
model = $model_file
mmproj = $projector_file
load-on-startup = false
EOF
  chmod 0600 "$config_home/no-more-404/models.ini"
}

export PATH="$fake_bin:/usr/bin:/bin"
export XDG_CONFIG_HOME="$config_home"
export XDG_RUNTIME_DIR="$runtime_dir"
cli="$repo_root/bin/no-more-404"

write_good_config
write_good_preset
doctor_output="$($cli doctor)"
grep -Fq 'all configured model and projector paths are readable absolute files' <<<"$doctor_output"
grep -Fq "all configured models meet Hermes's 64K minimum context" <<<"$doctor_output"
grep -Fq 'MAX_MODELS is one, so model changes use one safe replacement slot' \
  <<<"$doctor_output"
grep -Fq 'Doctor finished with 0 failure(s)' <<<"$doctor_output"

set +e
incompatible_output="$(
  FAKE_HELP_FLAGS='--models-preset --models-max --models-autoload --sleep-idle-seconds --fit --fit-target --fit-ctx --parallel --flash-attn --jinja --cache-prompt --host --port --timeout --no-webui' \
    "$cli" doctor 2>&1
)"
incompatible_status=$?
set -e
[[ "$incompatible_status" != 0 ]]
grep -Fq 'llama-server does not support --no-slots' <<<"$incompatible_output"

sed -i 's/HEALTH_FAILURES_REQUIRED=2/HEALTH_FAILURES_REQUIRED=1/' \
  "$config_home/no-more-404/runtime.env"
set +e
threshold_output="$($cli doctor 2>&1)"
threshold_status=$?
set -e
[[ "$threshold_status" != 0 ]]
grep -Fq 'HEALTH_FAILURES_REQUIRED must be an integer of at least two' <<<"$threshold_output"

write_good_config
sed -i 's/MAX_MODELS=1/MAX_MODELS=2/' "$config_home/no-more-404/runtime.env"
set +e
resident_output="$($cli doctor 2>&1)"
resident_status=$?
set -e
[[ "$resident_status" != 0 ]]
grep -Fq 'MAX_MODELS must be exactly one so the previous model is replaced during a switch' \
  <<<"$resident_output"

write_good_config
sed -i "s#model = $model_file#model = $test_dir/missing.gguf#" \
  "$config_home/no-more-404/models.ini"
set +e
model_output="$($cli doctor 2>&1)"
model_status=$?
set -e
[[ "$model_status" != 0 ]]
grep -Fq 'invalid or unreadable model/projector path' <<<"$model_output"

write_good_preset
sed -i 's/ctx-size = 65536/ctx-size = 32000/' \
  "$config_home/no-more-404/models.ini"
set +e
context_output="$($cli doctor 2>&1)"
context_status=$?
set -e
[[ "$context_status" != 0 ]]
grep -Fq 'must set an effective ctx-size of at least 64000 for Hermes (found 32000)' \
  <<<"$context_output"

write_good_preset
sed -i 's/fit = on/fit = off/' "$config_home/no-more-404/models.ini"
set +e
fit_output="$($cli doctor 2>&1)"
fit_status=$?
set -e
[[ "$fit_status" != 0 ]]
grep -Fq 'must enable fit = on for automatic hardware sizing' <<<"$fit_output"

write_good_preset
sed -i 's/fit-target = 1024/fit-target = 0/' "$config_home/no-more-404/models.ini"
set +e
margin_output="$($cli doctor 2>&1)"
margin_status=$?
set -e
[[ "$margin_status" != 0 ]]
grep -Fq 'needs a positive fit-target memory margin' <<<"$margin_output"

write_good_preset
sed -i 's/fit-ctx = 64000/fit-ctx = 32000/' "$config_home/no-more-404/models.ini"
set +e
fit_context_output="$($cli doctor 2>&1)"
fit_context_status=$?
set -e
[[ "$fit_context_status" != 0 ]]
grep -Fq 'fit-ctx must preserve at least 64000 tokens' <<<"$fit_context_output"

write_good_preset
sed -i '/fit-ctx = 64000/a n-gpu-layers = all' "$config_home/no-more-404/models.ini"
gpu_override_output="$($cli doctor)"
grep -Fq "explicitly sets GPU layers; this overrides llama.cpp's automatic placement" \
  <<<"$gpu_override_output"

write_good_preset
: >"$test_dir/target-active"
set +e
timer_output="$($cli doctor 2>&1)"
timer_status=$?
set -e
[[ "$timer_status" != 0 ]]
grep -Fq 'runtime target is active but its health watchdog timer is not' <<<"$timer_output"

: >"$test_dir/timer-active"
set +e
inactive_router_output="$($cli doctor 2>&1)"
inactive_router_status=$?
set -e
[[ "$inactive_router_status" != 0 ]]
grep -Fq 'runtime target is active but the router service is inactive' \
  <<<"$inactive_router_output"

: >"$test_dir/router-active"
active_output="$($cli doctor)"
grep -Fq 'health watchdog timer is active with the runtime target' <<<"$active_output"
grep -Fq 'active router owns the configured listener and answered its health check' <<<"$active_output"

printf 'doctor validation tests passed\n'
