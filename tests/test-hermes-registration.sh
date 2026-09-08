#!/usr/bin/env bash

set -Eeuo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
test_dir="$(mktemp -d)"
trap 'rm -rf -- "$test_dir"' EXIT

fake_bin="$test_dir/bin"
config_home="$test_dir/config"
state_file="$test_dir/hermes-state.tsv"
write_log="$test_dir/hermes-writes.tsv"
mkdir -p "$fake_bin" "$config_home/no-more-404"
: >"$state_file"
: >"$write_log"

cat >"$fake_bin/hermes" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail

[[ "${1:-}" == config ]] || exit 64
case "${2:-}" in
  set)
    if [[ "${3:-}" == --help ]]; then
      exit 0
    fi
    [[ $# == 4 ]] || exit 64
    if [[ -n "${FAKE_HERMES_FAIL_KEY_PREFIX:-}" &&
      "$3" == "$FAKE_HERMES_FAIL_KEY_PREFIX"* ]]; then
      exit 70
    fi
    printf '%s\t%s\n' "$3" "$4" >>"$FAKE_HERMES_LOG"
    printf '%s\t%s\n' "$3" "$4" >>"$FAKE_HERMES_STATE"
    ;;
  get)
    [[ $# == 3 ]] || exit 64
    found=false
    value=''
    while IFS=$'\t' read -r key candidate; do
      if [[ "$key" == "$3" ]]; then
        value="$candidate"
        found=true
      fi
    done <"$FAKE_HERMES_STATE"
    [[ "$found" == true ]] || exit 1
    printf '%s\n' "$value"
    ;;
  *) exit 64 ;;
esac
EOF
chmod 0755 "$fake_bin/hermes"

cat >"$config_home/no-more-404/runtime.env" <<EOF
LLAMA_SERVER_BIN="/unused/llama-server"
MODELS_PRESET="$config_home/no-more-404/models.ini"
BIND_HOST=127.0.0.1
PORT=15598
EOF
cat >"$config_home/no-more-404/models.ini" <<'EOF'
version = 1
[*]
ctx-size = 65536

[user.model-a]
model = /unused/model-a.gguf
load-on-startup = false

[user-choice]
model = /unused/user-choice.gguf
ctx-size = 70000
load-on-startup = false
EOF
chmod 0600 \
  "$config_home/no-more-404/runtime.env" \
  "$config_home/no-more-404/models.ini"

last_value() {
  local key="$1"
  local stored_key candidate value='' found=false
  while IFS=$'\t' read -r stored_key candidate; do
    if [[ "$stored_key" == "$key" ]]; then
      value="$candidate"
      found=true
    fi
  done <"$state_file"
  [[ "$found" == true ]]
  printf '%s\n' "$value"
}

export PATH="$fake_bin:/usr/bin:/bin"
export XDG_CONFIG_HOME="$config_home"
export FAKE_HERMES_STATE="$state_file"
export FAKE_HERMES_LOG="$write_log"
cli="$repo_root/bin/no-more-404"

printf 'model.default\tcloud-model\nmodel.provider\topenrouter\n' >"$state_file"
registration_output="$($cli register-hermes)"

grep -Fq 'Registered 2 model(s) under "NoMore404 Local" in Hermes.' \
  <<<"$registration_output"
grep -Fq "Hermes's current model was not changed." <<<"$registration_output"
[[ "$(last_value providers.no-more-404.api)" == 'http://127.0.0.1:15598/v1' ]]
[[ "$(last_value providers.no-more-404.name)" == 'NoMore404 Local' ]]
[[ "$(last_value providers.no-more-404.transport)" == 'chat_completions' ]]
[[ "$(last_value providers.no-more-404.discover_models)" == false ]]
[[ "$(last_value 'providers.no-more-404.models.user\.model-a.context_length')" == 65536 ]]
[[ "$(last_value 'providers.no-more-404.models.user-choice.context_length')" == 70000 ]]
[[ "$(last_value model.default)" == cloud-model ]]
[[ "$(last_value model.provider)" == openrouter ]]
! awk -F '\t' '$1 == "model.default" || $1 == "model.provider" { found = 1 } END { exit found ? 0 : 1 }' \
  "$write_log"
! awk -F '\t' '$1 == "providers.no-more-404.default_model" { found = 1 } END { exit found ? 0 : 1 }' \
  "$write_log"

printf 'model.default\tcloud-model\nmodel.provider\topenrouter\n' >"$state_file"
printf 'providers.no-more-404.api\thttp://127.0.0.1:9999/v1\n' >>"$state_file"
: >"$write_log"
set +e
conflict_output="$($cli register-hermes 2>&1)"
conflict_status=$?
set -e
[[ "$conflict_status" != 0 ]]
grep -Fq "already points to a different endpoint; it was not changed" \
  <<<"$conflict_output"
[[ ! -s "$write_log" ]]

printf 'model.default\tcloud-model\nmodel.provider\topenrouter\n' >"$state_file"
: >"$write_log"
sed -i 's/ctx-size = 65536/ctx-size = 32000/' \
  "$config_home/no-more-404/models.ini"
set +e
context_output="$($cli register-hermes 2>&1)"
context_status=$?
set -e
[[ "$context_status" != 0 ]]
grep -Fq 'ctx-size must be at least 64000 for Hermes' <<<"$context_output"
[[ ! -s "$write_log" ]]

sed -i 's/ctx-size = 32000/ctx-size = 65536/' \
  "$config_home/no-more-404/models.ini"
sed -i 's/\[user-choice\]/[user choice]/' \
  "$config_home/no-more-404/models.ini"
: >"$write_log"
set +e
alias_output="$($cli register-hermes 2>&1)"
alias_status=$?
set -e
[[ "$alias_status" != 0 ]]
grep -Fq 'uses an unsafe alias' <<<"$alias_output"
[[ ! -s "$write_log" ]]

sed -i 's/\[user choice\]/[user-choice]/' \
  "$config_home/no-more-404/models.ini"
sed -i 's/ctx-size = 70000/ctx-size = not-a-number/' \
  "$config_home/no-more-404/models.ini"
: >"$write_log"
set +e
numeric_output="$($cli register-hermes 2>&1)"
numeric_status=$?
set -e
[[ "$numeric_status" != 0 ]]
grep -Fq 'needs an explicit numeric ctx-size' <<<"$numeric_output"
[[ ! -s "$write_log" ]]

sed -i 's/ctx-size = not-a-number/ctx-size = 70000/' \
  "$config_home/no-more-404/models.ini"
printf 'model.default\tcloud-model\nmodel.provider\topenrouter\n' >"$state_file"
: >"$write_log"
set +e
partial_output="$(
  FAKE_HERMES_FAIL_KEY_PREFIX='providers.no-more-404.models.' \
    "$cli" register-hermes 2>&1
)"
partial_status=$?
set -e
[[ "$partial_status" != 0 ]]
grep -Fq 'provider settings may already be saved' <<<"$partial_output"
grep -Fq "inspect 'hermes config'" <<<"$partial_output"
[[ "$(wc -l <"$write_log")" == 4 ]]
! grep -Fq 'providers.no-more-404.models.' "$write_log"

printf 'Hermes model-picker registration tests passed\n'
