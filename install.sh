#!/usr/bin/env bash

set -Eeuo pipefail
umask 077

readonly package_version='1.0.0'
readonly repository='DriftlessWriting/Driftless-NoMore404'
readonly archive_url="https://github.com/$repository/archive/refs/tags/v$package_version.tar.gz"

fail() {
  printf 'no-more-404 bootstrap: %s\n' "$*" >&2
  exit 1
}

usage() {
  cat <<'EOF'
Usage: install.sh [--dry-run] [--upgrade]

Downloads the tagged Driftless-NoMore404 source into a private temporary
directory and runs its user-level installer. It never uses sudo, starts a
service, or enables a login service.

  --dry-run  Show the intended installation changes without writing them.
  --upgrade  Back up and replace changed package-managed files.
EOF
}

case "${1:-}" in
  -h | --help)
    usage
    exit 0
    ;;
esac

[[ "$(uname -s)" == Linux ]] || fail "this release supports Linux only"

for required_command in curl mkdir mktemp tar; do
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

"$source_directory/scripts/install.sh" "$@"

printf '\nBootstrap completed from the v%s source release.\n' "$package_version"
