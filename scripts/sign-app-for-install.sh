#!/bin/zsh
set -euo pipefail

repo_root="${0:A:h:h}"
source "$repo_root/scripts/signing-policy.sh"

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 '/path/to/Interview Arc Voice.app'" >&2
  exit 64
fi

app_path="${1:A}"
if [[ ! -d "$app_path" || ! -f "$app_path/Contents/Info.plist" ]]; then
  echo "Expected an Interview Arc Voice application bundle." >&2
  exit 66
fi

actual_bundle_identifier="$(voice_app_bundle_identifier "$app_path")"
if [[ "$actual_bundle_identifier" != "$VOICE_BUNDLE_IDENTIFIER" ]]; then
  echo "Refusing to sign unexpected bundle identifier: $actual_bundle_identifier" >&2
  exit 65
fi

executable_path="$(voice_app_executable_path "$app_path")"
if [[ ! -x "$executable_path" ]]; then
  echo "The packaged Voice executable is missing." >&2
  exit 66
fi

"$executable_path" --verify-package
before_hash="$(/usr/bin/shasum -a 256 "$executable_path" | /usr/bin/awk '{print $1}')"

fingerprint="$(voice_signing_identity_fingerprint "$VOICE_LOCAL_SIGNING_IDENTITY")" || {
  echo "No valid '$VOICE_LOCAL_SIGNING_IDENTITY' identity exists." >&2
  echo "Run scripts/bootstrap-local-signing-identity.sh once, then retry." >&2
  exit 69
}
requirement="$(voice_signing_requirement "$fingerprint")"

/usr/bin/codesign \
  --force \
  --sign "$fingerprint" \
  --timestamp=none \
  --requirements "$requirement" \
  "$app_path"

/usr/bin/codesign --verify --deep --strict "$app_path"
/usr/bin/codesign --verify --deep --strict --requirement "$requirement" "$app_path"
"$executable_path" --verify-package

after_hash="$(/usr/bin/shasum -a 256 "$executable_path" | /usr/bin/awk '{print $1}')"

signature_details="$(/usr/bin/codesign -dvvv "$app_path" 2>&1)"
if [[ "$signature_details" == *'Signature=adhoc'* ]]; then
  echo "The install candidate still has an ad-hoc signature." >&2
  exit 1
fi

actual_requirement="$(/usr/bin/codesign -d -r- "$app_path" 2>&1)"
if [[ "${actual_requirement:u}" != *"IDENTIFIER \"${VOICE_BUNDLE_IDENTIFIER:u}\" AND CERTIFICATE LEAF = H\"$fingerprint\""* ]]; then
  echo "The install candidate does not carry the expected stable requirement." >&2
  exit 1
fi

echo "Prepared stable install candidate: $app_path"
echo "Source executable SHA-256: $before_hash"
echo "Signed executable SHA-256: $after_hash"
echo "Signing certificate SHA-1: $fingerprint"
