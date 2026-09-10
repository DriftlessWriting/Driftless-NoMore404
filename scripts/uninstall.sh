#!/usr/bin/env bash

set -Eeuo pipefail

bin_path="$HOME/.local/bin/no-more-404"
health_path="$HOME/.local/libexec/no-more-404/no-more-404-health"
hermes_session_path="$HOME/.local/libexec/no-more-404/no-more-404-hermes-session"
hermes_follower_path="$HOME/.local/libexec/no-more-404/no-more-404-hermes-follower"
libexec_path="$HOME/.local/libexec/no-more-404/no-more-404-router"
target_path="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user/no-more-404.target"
service_path="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user/no-more-404-router.service"
watch_service_path="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user/no-more-404-watch.service"
watch_timer_path="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user/no-more-404-watch.timer"
hermes_follower_service_path="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user/no-more-404-hermes-follower.service"
state_dir="${XDG_STATE_HOME:-$HOME/.local/state}/no-more-404"
manifest="$state_dir/install-manifest.tsv"
dry_run=false

fail() {
  printf 'uninstall: %s\n' "$*" >&2
  exit 1
}

usage() {
  cat <<'EOF'
Usage: ./scripts/uninstall.sh [--dry-run]

Removes only unchanged files recorded by the Driftless-NoMore404 install manifest.
Configuration, models, caches, backups, and modified installed files are kept.
EOF
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

while (( $# > 0 )); do
  case "$1" in
    --dry-run) dry_run=true ;;
    -h | --help) usage; exit 0 ;;
    *) usage >&2; printf 'uninstall: unknown argument: %s\n' "$1" >&2; exit 1 ;;
  esac
  shift
done

allowed_paths=(
  "$bin_path"
  "$health_path"
  "$hermes_session_path"
  "$hermes_follower_path"
  "$libexec_path"
  "$target_path"
  "$service_path"
  "$watch_service_path"
  "$watch_timer_path"
  "$hermes_follower_service_path"
)

[[ -f "$manifest" && ! -L "$manifest" ]] ||
  fail "install manifest is missing or is not a regular file; refusing to guess which files are package-owned"
command -v sha256sum >/dev/null 2>&1 || fail "sha256sum is required"
command -v systemctl >/dev/null 2>&1 || fail "systemctl is required"
systemctl --user show-environment >/dev/null 2>&1 ||
  fail "the systemd user manager is unavailable; no files were removed"

declare -A allowed_path_set=()
declare -A manifest_hashes=()
for path in "${allowed_paths[@]}"; do
  allowed_path_set["$path"]=1
done

manifest_entries=0
manifest_line=0
while IFS=$'\t' read -r recorded_path recorded_hash extra ||
  [[ -n "${recorded_path:-}${recorded_hash:-}${extra:-}" ]]; do
  manifest_line=$((manifest_line + 1))
  if [[ -z "${recorded_path:-}" ||
        ! "${recorded_hash:-}" =~ ^[[:xdigit:]]{64}$ ||
        -n "${extra:-}" ||
        -z "${allowed_path_set[${recorded_path:-}]:-}" ||
        -n "${manifest_hashes[${recorded_path:-}]:-}" ]]; then
    fail "install manifest is corrupt at line $manifest_line; refusing to remove anything"
  fi
  manifest_hashes["$recorded_path"]="${recorded_hash,,}"
  manifest_entries=$((manifest_entries + 1))
done <"$manifest"
(( manifest_entries > 0 )) || fail "install manifest is empty; refusing to remove anything"

run systemctl --user disable --now no-more-404-hermes-follower.service ||
  fail "failed to disable the Hermes Desktop session follower; no files were removed"

run systemctl --user stop no-more-404.target ||
  fail "failed to stop no-more-404.target; no files were removed"

preserved=0

for path in "${allowed_paths[@]}"; do
  expected_hash="${manifest_hashes[$path]:-}"
  if [[ -z "$expected_hash" ]]; then
    printf 'Preserving unrecorded path: %s\n' "$path"
    preserved=$((preserved + 1))
    continue
  fi
  if [[ ! -e "$path" ]]; then
    continue
  fi

  actual_hash="$(sha256sum "$path" | awk '{print $1}')"
  if [[ "$actual_hash" != "$expected_hash" ]]; then
    printf 'Preserving locally modified file: %s\n' "$path"
    preserved=$((preserved + 1))
    continue
  fi
  run rm -f -- "$path"
done

if [[ "$dry_run" == false ]]; then
  rmdir -- "$HOME/.local/libexec/no-more-404" 2>/dev/null || true
  if (( preserved == 0 )); then
    rm -f -- "$manifest"
  fi
fi

run systemctl --user daemon-reload

printf '\nUninstall complete. Configuration, models, caches, state, and backups were preserved.\n'
