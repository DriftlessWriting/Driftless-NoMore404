#!/usr/bin/env bash

set -Eeuo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
test_directory="$(mktemp -d)"
trap 'rm -rf -- "$test_directory"' EXIT

archive_parent="$test_directory/archive"
archive_root="$archive_parent/Driftless-NoMore404-1.2.2"
archive_path="$test_directory/Driftless-NoMore404-1.2.2.tar.gz"
fake_bin="$test_directory/bin"
test_home="$test_directory/home with spaces"
model_path="$test_home/Chosen Model.Q4_K_M.gguf"
server_state="$test_directory/server-active"
server_arguments="$test_directory/server-arguments"
fit_arguments="$test_directory/fit-arguments"
systemctl_log="$test_directory/systemctl.log"
follower_enabled="$test_directory/follower-enabled"
follower_active="$test_directory/follower-active"
hermes_state="$test_directory/hermes-state.tsv"
hermes_log="$test_directory/hermes-writes.tsv"
curl_log="$test_directory/curl.log"
dialog_log="$test_directory/dialog.log"

mkdir -p \
  "$archive_root" \
  "$fake_bin" \
  "$test_home/.local/bin"
printf 'synthetic model fixture\n' >"$model_path"
: >"$systemctl_log"
: >"$hermes_log"
: >"$curl_log"
: >"$dialog_log"
printf 'model.default\tcloud-model\nmodel.provider\topenrouter\n' >"$hermes_state"

tar --create --file - --exclude=.git --directory "$repo_root" . |
  tar --extract --file - --directory "$archive_root"
tar --create --gzip --file "$archive_path" \
  --directory "$archive_parent" "$(basename "$archive_root")"

cat >"$fake_bin/llama-server" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail

if [[ "${1:-}" == --help ]]; then
  printf '%s\n' '--model --alias --parallel --fit --fit-target --fit-ctx --flash-attn --jinja --cache-prompt --host --port --timeout --no-webui --no-slots --list-devices --models-preset --models-max --models-autoload --sleep-idle-seconds'
  exit 0
fi
if [[ "${1:-}" == --list-devices ]]; then
  printf '%s\n' 'Available devices:' '  Vulkan0: Test GPU (24576 MiB, 22528 MiB free)'
  exit 0
fi

printf '%s\n' "$@" >"$FAKE_SERVER_ARGUMENTS"
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
printf '%s\n' "$@" >"$FAKE_FIT_ARGUMENTS"
printf '%s\n' \
  'llama_fit_params: projected to use 4096 MiB of 32768 MiB host memory' \
  'llama_fit_params: successfully fit params to free device and host memory' \
  '-c 131072 -ngl -1'
EOF

cat >"$fake_bin/curl" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail

printf '%s\n' "$*" >>"$FAKE_CURL_LOG"
output_path=''
write_output=''
url=''
while (( $# > 0 )); do
  case "$1" in
    --output)
      output_path="$2"
      shift 2
      ;;
    --write-out)
      write_output="$2"
      shift 2
      ;;
    http://* | https://*)
      url="$1"
      shift
      ;;
    *) shift ;;
  esac
done

case "$url" in
  https://raw.githubusercontent.com/DriftlessWriting/Driftless-NoMore404/v1.2.2/install.sh)
    /bin/cat "$FAKE_BOOTSTRAP"
    ;;
  https://github.com/DriftlessWriting/Driftless-NoMore404/archive/refs/tags/v1.2.2.tar.gz)
    [[ -n "$output_path" ]]
    cp -- "$FAKE_RELEASE_ARCHIVE" "$output_path"
    ;;
  http://127.0.0.1:*/health)
    [[ -e "$FAKE_SERVER_STATE" ]]
    ;;
  http://127.0.0.1:*/props)
    printf '%s\n' '{"default_generation_settings":{"n_ctx":131072}}' >"$output_path"
    ;;
  http://127.0.0.1:*/v1/chat/completions)
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
command_name="${1:-}"
(( $# == 0 )) || shift
printf '%s%s\n' "$command_name" "${*:+ $*}" >>"$FAKE_SYSTEMCTL_LOG"
case "$command_name" in
  show-environment | daemon-reload | status) exit 0 ;;
  enable)
    [[ "${1:-}" == --now && "${2:-}" == no-more-404-hermes-follower.service ]]
    : >"$FAKE_FOLLOWER_ENABLED"
    : >"$FAKE_FOLLOWER_ACTIVE"
    ;;
  is-enabled)
    quiet=false
    if [[ "${1:-}" == --quiet ]]; then
      quiet=true
      shift
    fi
    case "${1:-}" in
      no-more-404.target)
        [[ "$quiet" == true ]] || printf '%s\n' static
        ;;
      no-more-404-hermes-follower.service)
        if [[ -e "$FAKE_FOLLOWER_ENABLED" ]]; then
          [[ "$quiet" == true ]] || printf '%s\n' enabled
        else
          [[ "$quiet" == true ]] || printf '%s\n' disabled
          exit 1
        fi
        ;;
      *) exit 1 ;;
    esac
    ;;
  is-active)
    [[ "${1:-}" == --quiet ]] && shift
    [[ "${1:-}" == no-more-404-hermes-follower.service &&
      -e "$FAKE_FOLLOWER_ACTIVE" ]]
    ;;
  *)
    printf 'unexpected fake systemctl arguments: %s %s\n' "$command_name" "$*" >&2
    exit 2
    ;;
esac
EOF

cat >"$fake_bin/ss" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF

cat >"$fake_bin/kdialog" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
printf '%s\n' "$*" >>"$FAKE_DIALOG_LOG"
printf '%s\n' "$FAKE_DIALOG_MODEL"
EOF

cat >"$test_home/.local/bin/hermes" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail

[[ "${1:-}" == config ]] || exit 64
case "${2:-}" in
  set)
    [[ "${3:-}" == --help ]] && exit 0
    [[ $# == 4 ]] || exit 64
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

runner="$test_directory/run-public-command"
cat >"$runner" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
bash -o pipefail -c 'curl --proto =https --tlsv1.2 --fail --silent --show-error --location https://raw.githubusercontent.com/DriftlessWriting/Driftless-NoMore404/v1.2.2/install.sh | bash'
EOF

chmod 0755 \
  "$fake_bin/llama-server" \
  "$fake_bin/llama-fit-params" \
  "$fake_bin/curl" \
  "$fake_bin/systemctl" \
  "$fake_bin/ss" \
  "$fake_bin/kdialog" \
  "$test_home/.local/bin/hermes" \
  "$runner"

export HOME="$test_home"
export XDG_CONFIG_HOME="$test_home/.config"
export XDG_STATE_HOME="$test_home/.local/state"
export XDG_RUNTIME_DIR="$test_directory/runtime"
export PATH="$fake_bin:/usr/bin:/bin"
export DISPLAY=:99
export WAYLAND_DISPLAY=''
export FAKE_BOOTSTRAP="$repo_root/install.sh"
export FAKE_RELEASE_ARCHIVE="$archive_path"
export FAKE_SERVER_STATE="$server_state"
export FAKE_SERVER_ARGUMENTS="$server_arguments"
export FAKE_FIT_ARGUMENTS="$fit_arguments"
export FAKE_SYSTEMCTL_LOG="$systemctl_log"
export FAKE_FOLLOWER_ENABLED="$follower_enabled"
export FAKE_FOLLOWER_ACTIVE="$follower_active"
export FAKE_HERMES_STATE="$hermes_state"
export FAKE_HERMES_LOG="$hermes_log"
export FAKE_CURL_LOG="$curl_log"
export FAKE_DIALOG_LOG="$dialog_log"
export FAKE_DIALOG_MODEL="$model_path"
mkdir -p "$XDG_RUNTIME_DIR"

# The first blank accepts the detected llama-server. The simulated native file
# window selects the user's GGUF. The final three blanks accept the
# filename-derived picker name, Hermes registration, and automatic following.
one_command_output="$({
  printf '\n\n\n\n'
} | timeout 45 script --quiet --return --command "$runner" /dev/null)"

grep -Fq 'Starting first-time setup in this same command.' <<<"$one_command_output"
grep -Fq 'Opening a file window so you can select your GGUF model' \
  <<<"$one_command_output"
grep -Fq 'Name shown in Hermes [Chosen Model.Q4_K_M]' <<<"$one_command_output"
grep -Fq 'Registered 1 model(s) under "NoMore404 Local" in Hermes.' \
  <<<"$one_command_output"
grep -Fq 'Automatic Hermes Desktop integration is enabled.' \
  <<<"$one_command_output"
grep -Fq 'Doctor finished with 0 failure(s) and 0 warning(s).' \
  <<<"$one_command_output"
grep -Fq 'Ready. Open Hermes Desktop, choose Refresh models' \
  <<<"$one_command_output"
grep -Fq 'Bootstrap completed from the v1.2.2 source release.' \
  <<<"$one_command_output"

runtime_file="$test_home/.config/no-more-404/runtime.env"
models_file="$test_home/.config/no-more-404/models.ini"
[[ -x "$test_home/.local/bin/no-more-404" ]]
[[ "$(stat -c '%a' "$runtime_file")" == 600 ]]
[[ "$(stat -c '%a' "$models_file")" == 600 ]]
grep -Fxq '[Chosen Model.Q4_K_M]' "$models_file"
grep -Fq "model = $model_path" "$models_file"
grep -Fq 'ctx-size = 131072' "$models_file"
if grep -Fq '/absolute/path/to/llama-server' "$runtime_file" ||
  grep -Fq '/absolute/path/to/models.ini' "$runtime_file" ||
  grep -Fq '/absolute/path/to/main-model.gguf' "$models_file"; then
  printf 'one-command setup left an example placeholder\n' >&2
  exit 1
fi
[[ -e "$follower_enabled" && -e "$follower_active" ]]
grep -Fxq 'enable --now no-more-404-hermes-follower.service' "$systemctl_log"
grep -Fq 'providers.no-more-404.api' "$hermes_log"
grep -Fq 'providers.no-more-404.models.Chosen Model\.Q4_K_M.context_length' \
  "$hermes_log"
grep -Fq -- '--getopenfilename' "$dialog_log"
if grep -Eq '^model\.(default|provider)[[:space:]]' "$hermes_log"; then
  printf 'one-command setup changed Hermes current model or provider\n' >&2
  exit 1
fi
[[ ! -e "$server_state" ]]
grep -Fxq -- --fit "$server_arguments"
grep -Fxq -- --fit-ctx "$server_arguments"
grep -Fxq -- --model "$fit_arguments"

printf 'one-command first-install and self-wiring tests passed\n'
