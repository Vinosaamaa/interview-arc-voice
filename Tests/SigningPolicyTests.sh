#!/bin/zsh
set -euo pipefail

repo_root="${0:A:h:h}"
source "$repo_root/scripts/signing-policy.sh"

fingerprint='0123456789abcdef0123456789abcdef01234567'
expected='=designated => identifier "app.interviewarc.voice" and certificate leaf = H"0123456789ABCDEF0123456789ABCDEF01234567"'
actual="$(voice_signing_requirement "$fingerprint")"

if [[ "$actual" != "$expected" ]]; then
  echo "Unexpected stable signing requirement: $actual" >&2
  exit 1
fi

if voice_signing_requirement 'not-a-certificate-hash' >/dev/null 2>&1; then
  echo "Invalid certificate hashes must be rejected." >&2
  exit 1
fi

if ! /usr/bin/grep -q -- '--sign "$fingerprint"' "$repo_root/scripts/sign-app-for-install.sh"; then
  echo "The install signer must use the resolved certificate identity." >&2
  exit 1
fi

if /usr/bin/grep -q -- '--deep \\' "$repo_root/scripts/sign-app-for-install.sh"; then
  echo "The install signer must not recursively re-sign the outer bundle." >&2
  exit 1
fi

if ! /usr/bin/grep -Fq \
  'codesign --force --sign - "$contents_dir/MacOS/InterviewArcVoiceVerifier"' \
  "$repo_root/scripts/package-app.sh"; then
  echo "The package builder must explicitly sign the nested verifier first." >&2
  exit 1
fi

if /usr/bin/grep -q -- '--deep --sign' "$repo_root/scripts/package-app.sh"; then
  echo "The package builder must sign nested code from the inside out." >&2
  exit 1
fi

echo "Signing policy tests passed."
