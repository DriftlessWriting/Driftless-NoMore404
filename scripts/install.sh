#!/usr/bin/env bash

set -Eeuo pipefail
umask 077

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
repo_root="$(cd -- "$script_dir/.." && pwd -P)"

bin_dir="$HOME/.local/bin"
libexec_dir="$HOME/.local/libexec/no-more-404"
config_dir="${XDG_CONFIG_HOME:-$HOME/.config}/no-more-404"
unit_dir="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
state_dir="${XDG_STATE_HOME:-$HOME/.local/state}/no-more-404"
manifest="$state_dir/install-manifest.tsv"

dry_run=false
upgrade=false
backup_dir=''

usage() {
  cat <<'EOF'
Usage: ./scripts/install.sh [--dry-run] [--upgrade]

Installs Driftless-NoMore404 for the current user. It never enables or starts the
runtime, and it never overwrites runtime.env or models.ini.

  --dry-run  Show the intended changes without writing anything.
  --upgrade  Back up and replace changed Driftless-NoMore404 managed files.
EOF
}

fail() {
  printf 'install: %s\n' "$*" >&2
  exit 1
}

show_command() {
  printf '+'
  printf ' %q' "$@"
  printf '\n'
}

run() {
  if [[ "$dry_run" == true ]]; then
    show_command "$@"
  else
    "$@"
  fi
}

ensure_safe_destination_directory() {
  local path="$1"
  local create_mode="$2"
  local directory_owner directory_mode directory_permissions

  if [[ -e "$path" ]]; then
    [[ -d "$path" ]] || fail "expected a directory but found another file type: $path"
  else
    run install -d -m "$create_mode" "$path"
    [[ "$dry_run" == true ]] && return
  fi

  directory_owner="$(stat -Lc '%u' -- "$path")" ||
    fail "could not inspect destination directory ownership: $path"
  [[ "$directory_owner" == "$EUID" ]] ||
    fail "destination directory is not owned by the invoking user: $path"

  directory_mode="$(stat -Lc '%a' -- "$path")" ||
    fail "could not inspect destination directory permissions: $path"
  directory_permissions=$((8#$directory_mode))
  (( (directory_permissions & 8#022) == 0 )) ||
    fail "destination directory must not be group- or world-writable: $path"
}

while (( $# > 0 )); do
  case "$1" in
    --dry-run) dry_run=true ;;
    --upgrade) upgrade=true ;;
    -h | --help) usage; exit 0 ;;
    *) usage >&2; fail "unknown argument: $1" ;;
  esac
  shift
done

missing_commands=()
for required_command in awk cmp curl flock install realpath sha256sum ss stat systemctl tar; do
  command -v "$required_command" >/dev/null 2>&1 ||
    missing_commands+=("$required_command")
done
(( ${#missing_commands[@]} == 0 )) ||
  fail "missing required command(s): ${missing_commands[*]}; see https://github.com/DriftlessWriting/Driftless-NoMore404/blob/main/docs/QUICKSTART.md"
systemctl --user show-environment >/dev/null 2>&1 ||
  fail "the systemd user manager is unavailable in this session"

[[ -f "$repo_root/VERSION" && ! -L "$repo_root/VERSION" ]] ||
  fail "repository VERSION file is missing or unsafe"
package_version="$(<"$repo_root/VERSION")"
[[ "$package_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] ||
  fail "repository VERSION is not a stable semantic version"

managed_sources=(
  "$repo_root/bin/no-more-404"
  "$repo_root/bin/no-more-404-router"
  "$repo_root/bin/no-more-404-health"
  "$repo_root/bin/no-more-404-hermes-session"
  "$repo_root/systemd/user/no-more-404.target"
  "$repo_root/systemd/user/no-more-404-router.service"
  "$repo_root/systemd/user/no-more-404-watch.service"
  "$repo_root/systemd/user/no-more-404-watch.timer"
)
managed_destinations=(
  "$bin_dir/no-more-404"
  "$libexec_dir/no-more-404-router"
  "$libexec_dir/no-more-404-health"
  "$libexec_dir/no-more-404-hermes-session"
  "$unit_dir/no-more-404.target"
  "$unit_dir/no-more-404-router.service"
  "$unit_dir/no-more-404-watch.service"
  "$unit_dir/no-more-404-watch.timer"
)
managed_modes=(0755 0755 0755 0755 0644 0644 0644 0644)

for index in "${!managed_sources[@]}"; do
  source_path="${managed_sources[$index]}"
  destination_path="${managed_destinations[$index]}"

  [[ -f "$source_path" ]] || fail "repository file is missing: $source_path"
  [[ ! -L "$destination_path" ]] || fail "refusing to replace a symbolic link: $destination_path"
  if [[ -e "$destination_path" ]] && ! cmp -s -- "$source_path" "$destination_path"; then
    [[ "$upgrade" == true ]] ||
      fail "refusing to overwrite changed file: $destination_path (use --upgrade to back it up)"
  fi
done

ensure_safe_destination_directory "$bin_dir" 0755
ensure_safe_destination_directory "$unit_dir" 0755
ensure_safe_destination_directory "$libexec_dir" 0755
ensure_safe_destination_directory "$config_dir" 0700
ensure_safe_destination_directory "$state_dir" 0700
[[ ! -L "$libexec_dir" && ! -L "$config_dir" && ! -L "$state_dir" ]] ||
  fail "package-owned directories must not be symbolic links"
run chmod 0700 "$config_dir" "$state_dir"

for config_path in "$config_dir/runtime.env" "$config_dir/models.ini"; do
  [[ ! -L "$config_path" ]] || fail "configuration files must not be symbolic links: $config_path"
  if [[ -e "$config_path" ]]; then
    [[ -f "$config_path" ]] || fail "configuration path must be a regular file: $config_path"
  fi
done

if [[ "$upgrade" == true ]]; then
  backup_dir="$state_dir/backups/$(date -u +%Y%m%dT%H%M%SZ)"
  for index in "${!managed_sources[@]}"; do
    source_path="${managed_sources[$index]}"
    destination_path="${managed_destinations[$index]}"
    if [[ -e "$destination_path" ]] && ! cmp -s -- "$source_path" "$destination_path"; then
      run install -d -m 0700 "$backup_dir"
      run install -m 0600 "$destination_path" "$backup_dir/$(basename "$destination_path")"
    fi
  done
fi

for index in "${!managed_sources[@]}"; do
  run install -m "${managed_modes[$index]}" "${managed_sources[$index]}" "${managed_destinations[$index]}"
done

[[ ! -L "$config_dir/runtime.env" ]] || fail "runtime configuration must not be a symbolic link"
if [[ ! -e "$config_dir/runtime.env" ]]; then
  run install -m 0600 "$repo_root/config/runtime.env.example" "$config_dir/runtime.env"
else
  [[ -f "$config_dir/runtime.env" ]] || fail "runtime configuration must be a regular file"
  printf 'Preserving existing configuration: %s\n' "$config_dir/runtime.env"
fi

[[ ! -L "$config_dir/models.ini" ]] || fail "model preset must not be a symbolic link"
if [[ ! -e "$config_dir/models.ini" ]]; then
  run install -m 0600 "$repo_root/config/models.ini.example" "$config_dir/models.ini"
else
  [[ -f "$config_dir/models.ini" ]] || fail "model preset must be a regular file"
  printf 'Preserving existing model preset: %s\n' "$config_dir/models.ini"
fi

if [[ "$dry_run" == false ]]; then
  manifest_tmp="$(mktemp "$state_dir/.install-manifest.XXXXXX")"
  trap 'rm -f -- "$manifest_tmp"' EXIT
  for destination_path in "${managed_destinations[@]}"; do
    printf '%s\t%s\n' "$destination_path" "$(sha256sum "$destination_path" | awk '{print $1}')" >>"$manifest_tmp"
  done
  chmod 0600 "$manifest_tmp"
  mv -f -- "$manifest_tmp" "$manifest"
  trap - EXIT
fi

run systemctl --user daemon-reload

printf '\nInstalled without starting or enabling any service.\n'
printf '1. Choose and download a GGUF model with at least 64K context.\n'
printf '2. Run: %s setup\n' "$bin_dir/no-more-404"
printf '   Setup finds llama-server or offers a verified runtime, then sizes and tests your chosen model.\n'
printf '3. Run: %s doctor\n' "$bin_dir/no-more-404"
printf '4. Run: %s start\n' "$bin_dir/no-more-404"
printf 'Setup guide: https://github.com/DriftlessWriting/Driftless-NoMore404/blob/v%s/docs/QUICKSTART.md\n' \
  "$package_version"
case ":$PATH:" in
  *":$bin_dir:"*) ;;
  *)
    printf 'Note: %s is not currently in PATH. Use the full command path above, or add it to your shell PATH.\n' \
      "$bin_dir"
    ;;
esac
if [[ -n "$backup_dir" ]]; then
  printf 'Changed managed files were backed up under %s\n' "$backup_dir"
fi
