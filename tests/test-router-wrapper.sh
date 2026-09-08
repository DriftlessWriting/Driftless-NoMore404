#!/usr/bin/env bash

set -Eeuo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
test_dir="$(mktemp -d)"
trap 'rm -rf -- "$test_dir"' EXIT

fake_server="$test_dir/fake llama-server"
capture_file="$test_dir/arguments"
preset_file="$test_dir/models.ini"

cat >"$fake_server" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
if [[ "${1:-}" == --help ]]; then
  printf '%s\n' "${FAKE_HELP_FLAGS:---models-preset --models-max --models-autoload --sleep-idle-seconds --fit --fit-target --fit-ctx --parallel --flash-attn --jinja --cache-prompt --host --port --timeout --no-webui --metrics --slots --no-slots}"
  exit 0
fi
printf '%s\n' "$@" >"$ARG_CAPTURE"
EOF
chmod 0755 "$fake_server"

cat >"$preset_file" <<'EOF'
version = 1
[test-model]
model = /models/test.gguf
load-on-startup = false
EOF

ARG_CAPTURE="$capture_file" \
LLAMA_SERVER_BIN="$fake_server" \
MODELS_PRESET="$preset_file" \
LLAMA_CACHE_DIR="$test_dir/cache" \
BIND_HOST=127.0.0.1 \
PORT=15598 \
MAX_MODELS=1 \
IDLE_SECONDS=7 \
REQUEST_TIMEOUT_SECONDS=30 \
ENABLE_METRICS=false \
ENABLE_SLOTS=false \
  "$repo_root/bin/no-more-404-router"

for expected in \
  --models-preset "$preset_file" \
  --models-max 1 \
  --models-autoload \
  --sleep-idle-seconds 7 \
  --host 127.0.0.1 \
  --port 15598 \
  --timeout 30 \
  --no-webui \
  --no-slots; do
  grep -Fxq -- "$expected" "$capture_file" || {
    printf 'missing expected argument: %s\n' "$expected" >&2
    exit 1
  }
done

if grep -Fxq -- --metrics "$capture_file"; then
  printf 'metrics should be disabled by default in this test\n' >&2
  exit 1
fi

if grep -Fxq -- --slots "$capture_file"; then
  printf 'slots endpoint should be disabled in the default-safe test\n' >&2
  exit 1
fi

# Operators can explicitly opt in to the loopback-only slots endpoint.
ARG_CAPTURE="$capture_file" \
LLAMA_SERVER_BIN="$fake_server" \
MODELS_PRESET="$preset_file" \
LLAMA_CACHE_DIR="$test_dir/cache" \
BIND_HOST=127.0.0.1 \
PORT=15598 \
ENABLE_SLOTS=true \
  "$repo_root/bin/no-more-404-router"
grep -Fxq -- --slots "$capture_file"
if grep -Fxq -- --no-slots "$capture_file"; then
  printf 'explicit slots opt-in passed contradictory flags\n' >&2
  exit 1
fi

# A binary missing a flag used by the selected safe defaults fails during
# compatibility preflight rather than after systemd reports a misleading start.
set +e
FAKE_HELP_FLAGS='--models-preset --models-max --models-autoload --sleep-idle-seconds --fit --fit-target --fit-ctx --parallel --flash-attn --jinja --cache-prompt --host --port --timeout --no-webui' \
ARG_CAPTURE="$capture_file" \
LLAMA_SERVER_BIN="$fake_server" \
MODELS_PRESET="$preset_file" \
LLAMA_CACHE_DIR="$test_dir/cache" \
PORT=15598 \
ENABLE_SLOTS=false \
  "$repo_root/bin/no-more-404-router" >/dev/null 2>&1
missing_flag_status=$?
set -e
[[ "$missing_flag_status" == 78 ]] || {
  printf 'missing default launch flag was not rejected with EX_CONFIG\n' >&2
  exit 1
}

set +e
ARG_CAPTURE="$capture_file" \
LLAMA_SERVER_BIN="$fake_server" \
MODELS_PRESET="$preset_file" \
LLAMA_CACHE_DIR="$test_dir/cache" \
BIND_HOST=0.0.0.0 \
PORT=15598 \
  "$repo_root/bin/no-more-404-router" >/dev/null 2>&1
remote_status=$?
set -e
[[ "$remote_status" == 78 ]] || {
  printf 'remote bind was not rejected with EX_CONFIG\n' >&2
  exit 1
}

sed 's/load-on-startup = false/load-on-startup = true/' "$preset_file" >"$test_dir/preload.ini"
set +e
ARG_CAPTURE="$capture_file" \
LLAMA_SERVER_BIN="$fake_server" \
MODELS_PRESET="$test_dir/preload.ini" \
LLAMA_CACHE_DIR="$test_dir/cache" \
PORT=15598 \
  "$repo_root/bin/no-more-404-router" >/dev/null 2>&1
preload_status=$?
set -e
[[ "$preload_status" == 78 ]] || {
  printf 'startup preload was not rejected with EX_CONFIG\n' >&2
  exit 1
}

printf 'router wrapper tests passed\n'
