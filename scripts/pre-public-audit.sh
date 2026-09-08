#!/usr/bin/env bash

set -Eeuo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
cd "$repo_root"

failures=0
require_private=false

fail() {
  printf 'FAIL %s\n' "$*" >&2
  failures=$((failures + 1))
}

ok() {
  printf 'OK   %s\n' "$*"
}

if [[ "${1:-}" == --require-private ]]; then
  require_private=true
  shift
fi
(( $# == 0 )) || {
  printf 'Usage: ./scripts/pre-public-audit.sh [--require-private]\n' >&2
  exit 1
}

git rev-parse --is-inside-work-tree >/dev/null 2>&1 || {
  printf 'FAIL not a Git worktree\n' >&2
  exit 1
}
command -v rg >/dev/null 2>&1 || fail "ripgrep (rg) is required for a pre-public audit"

tracked_files=()
while IFS= read -r -d '' tracked; do
  tracked_files+=("$tracked")
done < <(git ls-files -z)

(( ${#tracked_files[@]} > 0 )) || fail "repository has no tracked files"

for file in "${tracked_files[@]}"; do
  [[ -f "$file" ]] || continue
  size="$(stat -c '%s' "$file")"
  (( size <= 1048576 )) || fail "tracked file exceeds 1 MiB: $file"
  case "$file" in
    *.gguf | *.safetensors | *.pt | *.pth | *.onnx | *.db | *.sqlite | *.sqlite3)
      fail "forbidden model/database artifact is tracked: $file"
      ;;
    *.env)
      fail "runtime environment file is tracked: $file"
      ;;
  esac
done

path_scan_file="$(mktemp)"
secret_scan_file="$(mktemp)"
trap 'rm -f -- "$path_scan_file" "$secret_scan_file"' EXIT

if rg --hidden --no-ignore -n -I \
  '/home/[[:alnum:]_.-]+/|/run/user/[0-9]+|C:[/\\]Users[/\\]' . \
  --glob '!.git/**' \
  --glob '!scripts/pre-public-audit.sh' >"$path_scan_file" 2>/dev/null; then
  cat "$path_scan_file" >&2
  fail "personal absolute path pattern found"
else
  ok "no personal absolute paths found"
fi

secret_pattern='(gh[pousr]_[A-Za-z0-9_]{20,}|github_pat_[A-Za-z0-9_]{20,}|sk-[A-Za-z0-9_-]{20,}|AKIA[0-9A-Z]{16}|-----BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY-----)'
if rg --hidden --no-ignore -n -I "$secret_pattern" . \
  --glob '!.git/**' \
  --glob '!scripts/pre-public-audit.sh' >"$secret_scan_file" 2>/dev/null; then
  cat "$secret_scan_file" >&2
  fail "credential-like value found"
else
  ok "no common credential patterns found"
fi

if command -v gitleaks >/dev/null 2>&1; then
  if gitleaks dir --no-banner --redact . >/dev/null; then
    ok "Gitleaks working-directory scan passed"
  else
    fail "Gitleaks reported a working-directory finding"
  fi
  if gitleaks git --no-banner --redact . >/dev/null; then
    ok "Gitleaks history scan passed"
  else
    fail "Gitleaks reported a history finding"
  fi
else
  fail "Gitleaks is required for a pre-public audit"
fi

if [[ "$require_private" == true ]] && ! command -v gh >/dev/null 2>&1; then
  fail "GitHub CLI (gh) is required to confirm private visibility"
elif [[ "$require_private" == true ]] && ! git remote get-url origin >/dev/null 2>&1; then
  fail "an origin remote is required to confirm private visibility"
elif command -v gh >/dev/null 2>&1 && git remote get-url origin >/dev/null 2>&1; then
  visibility="$(gh repo view --json visibility --jq .visibility 2>/dev/null || true)"
  if [[ "$require_private" == true && "$visibility" != PRIVATE ]]; then
    fail "GitHub repository is not confirmed private (reported: ${visibility:-unknown})"
  elif [[ "$visibility" == PRIVATE || "$visibility" == PUBLIC ]]; then
    ok "GitHub repository visibility is $visibility"
  else
    fail "GitHub repository visibility is unknown"
  fi
fi

(( failures == 0 )) || {
  printf '\nPre-public audit failed with %d finding(s).\n' "$failures" >&2
  exit 1
}

printf '\nPre-public audit passed. This is not a substitute for human review.\n'
