#!/usr/bin/env bash

set -Eeuo pipefail
umask 077

readonly package_version='1.2.2'
readonly repository='DriftlessWriting/Driftless-NoMore404'
readonly archive_url="https://github.com/$repository/archive/refs/tags/v$package_version.tar.gz"

dry_run=false
run_setup=true
installer_arguments=()

fail() {
  printf 'no-more-404 bootstrap: %s\n' "$*" >&2
  exit 1
}

usage() {
  cat <<'EOF'
Usage: install.sh [--dry-run] [--upgrade] [--no-setup]

Downloads the tagged Driftless-NoMore404 source into a private temporary
directory and runs its user-level installer. On a first installation, it then
opens the guided model selection, wires the chosen model into Hermes when
approved, enables automatic Desktop following when approved, and runs doctor.
It never uses sudo or launches Hermes.

  --dry-run  Show the intended installation changes without writing them.
  --upgrade  Back up and replace changed package-managed files.
  --no-setup Install the package only; do not start first-time guided setup.
EOF
}

while (( $# > 0 )); do
  case "$1" in
    --dry-run)
      dry_run=true
      installer_arguments+=("$1")
      ;;
    --upgrade) installer_arguments+=("$1") ;;
    --no-setup) run_setup=false ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      usage >&2
      fail "unknown argument: $1"
      ;;
  esac
  shift
done

[[ "$(uname -s)" == Linux ]] || fail "this release supports Linux only"

for required_command in cat curl grep mkdir mktemp sleep tar; do
  command -v "$required_command" >/dev/null 2>&1 ||
    fail "required command is missing: $required_command"
done

temporary_directory="$(mktemp -d)"
trap 'rm -rf -- "$temporary_directory"' EXIT
archive_path="$temporary_directory/no-more-404.tar.gz"
source_directory="$temporary_directory/source"

printf 'Downloading Driftless-NoMore404 %s from GitHub...\n' "$package_version"
curl \
  --disable \
  --proto '=https' \
  --tlsv1.2 \
  --fail \
  --silent \
  --show-error \
  --location \
  --connect-timeout 15 \
  --max-time 300 \
  --output "$archive_path" \
  "$archive_url"

mkdir -m 0700 "$source_directory"
tar \
  --extract \
  --gzip \
  --file "$archive_path" \
  --directory "$source_directory" \
  --strip-components=1 \
  --no-same-owner \
  --no-same-permissions

[[ -f "$source_directory/VERSION" && ! -L "$source_directory/VERSION" ]] ||
  fail "downloaded release does not contain a regular VERSION file"
downloaded_version="$(<"$source_directory/VERSION")"
[[ "$downloaded_version" == "$package_version" ]] ||
  fail "downloaded release version is $downloaded_version, expected $package_version"
[[ -x "$source_directory/scripts/install.sh" ]] ||
  fail "downloaded release does not contain an executable package installer"

"$source_directory/scripts/install.sh" "${installer_arguments[@]}"

installed_cli="$HOME/.local/bin/no-more-404"
installed_config="${XDG_CONFIG_HOME:-$HOME/.config}/no-more-404/runtime.env"
installed_models="${XDG_CONFIG_HOME:-$HOME/.config}/no-more-404/models.ini"

if [[ "$dry_run" == false && "$run_setup" == true ]] &&
  grep -Fq '/absolute/path/to/llama-server' "$installed_config" &&
  grep -Fq '/absolute/path/to/main-model.gguf' "$installed_models"; then
  printf '\nStarting first-time setup in this same command.\n'
  printf 'Choose your GGUF when asked; pressing Enter accepts the safe defaults.\n\n'

  if [[ -t 0 ]]; then
    "$installed_cli" setup
  elif { exec {terminal_fd}<>/dev/tty; } 2>/dev/null; then
    "$installed_cli" setup <&"$terminal_fd"
    exec {terminal_fd}>&-
  else
    fail "the package was installed, but guided setup needs an interactive terminal; run '$installed_cli setup'"
  fi

  printf '\nRunning the final readiness check...\n'
  doctor_output="$temporary_directory/doctor.log"
  doctor_passed=false
  for ((doctor_attempt = 1; doctor_attempt <= 20; doctor_attempt++)); do
    if "$installed_cli" doctor >"$doctor_output" 2>&1; then
      doctor_passed=true
      break
    fi
    sleep 0.5
  done
  cat "$doctor_output"
  [[ "$doctor_passed" == true ]] ||
    fail "final readiness checks did not pass; run '$installed_cli doctor' for the current state"
  printf '\nReady. Open Hermes Desktop, choose Refresh models, and select the model name you configured.\n'
elif [[ "$dry_run" == false && "$run_setup" == true ]]; then
  printf '\nExisting configuration was preserved, so first-time setup was not repeated.\n'
  printf 'Verify it at any time with: %s doctor\n' "$installed_cli"
elif [[ "$dry_run" == false ]]; then
  printf '\nGuided setup was skipped by request. Run it later with: %s setup\n' "$installed_cli"
fi

printf '\nBootstrap completed from the v%s source release.\n' "$package_version"
