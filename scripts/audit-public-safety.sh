#!/bin/bash
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

failed=0

report() {
  printf 'public-safety: %s\n' "$1" >&2
  failed=1
}

while IFS= read -r path; do
  lower_path=$(printf '%s' "$path" | tr '[:upper:]' '[:lower:]')
  case "$lower_path" in
    *.env|*.env.*|*.m4a|*.mp3|*.wav|*.caf|*.db|*.sqlite|*.sqlite3|*.pem|*.p12|*.pfx|*.key|*.cer|*.provisionprofile)
      case "$path" in
        .env.example) ;;
        *) report "tracked private/runtime material: $path" ;;
      esac
      ;;
  esac
done < <(git ls-files)

# Assemble the home-path expression so this audit script does not match itself.
home_path_pattern='/'"Users/"'[A-Za-z0-9._-]+'
while IFS= read -r path; do
  report "tracked absolute user-home path: $path"
done < <(git grep -I -l -E "$home_path_pattern" -- ':!scripts/audit-public-safety.sh' || true)

credential_pattern='(-----BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY-----|gh[pousr]_[A-Za-z0-9]{20,}|sk-[A-Za-z0-9_-]{20,}|gsk_[A-Za-z0-9_-]{20,}|INTERVIEW_ARC_MCP_TOKEN[[:space:]]*=)'
while IFS= read -r path; do
  report "tracked credential-shaped content: $path"
done < <(git grep -I -l -E "$credential_pattern" -- ':!scripts/audit-public-safety.sh' || true)

max_bytes=$((10 * 1024 * 1024))
while IFS= read -r path; do
  [[ -f "$path" ]] || continue
  bytes=$(stat -f '%z' "$path")
  if (( bytes > max_bytes )); then
    report "tracked file exceeds 10 MiB: $path"
  fi
done < <(git ls-files)

if (( failed != 0 )); then
  exit 1
fi

printf 'public-safety: tracked-tree checks passed\n'
