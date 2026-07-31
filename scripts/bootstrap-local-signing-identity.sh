#!/bin/zsh
set -euo pipefail
umask 077

repo_root="${0:A:h:h}"
source "$repo_root/scripts/signing-policy.sh"

if fingerprint="$(voice_signing_identity_fingerprint "$VOICE_LOCAL_SIGNING_IDENTITY" 2>/dev/null)"; then
  echo "Local Voice signing identity is already available: $fingerprint"
  exit 0
fi

login_keychain="$(
  /usr/bin/security default-keychain -d user \
    | /usr/bin/sed -E 's/^[[:space:]]*"(.*)"[[:space:]]*$/\1/'
)"
if [[ -z "$login_keychain" || ! -f "$login_keychain" ]]; then
  echo "Could not resolve the user's default Keychain." >&2
  exit 1
fi

temporary_root="$(/usr/bin/mktemp -d /private/tmp/interview-arc-voice-signing.XXXXXX)"
cleanup() {
  if [[ "$temporary_root" == /private/tmp/interview-arc-voice-signing.* ]]; then
    /bin/rm -rf "$temporary_root"
  fi
}
trap cleanup EXIT

certificate_pem="$temporary_root/certificate.pem"
private_key_pem="$temporary_root/private-key.pem"
identity_p12="$temporary_root/identity.p12"
temporary_passphrase="$(/usr/bin/openssl rand -hex 32)"

/usr/bin/openssl req \
  -newkey rsa:3072 \
  -x509 \
  -sha256 \
  -days 3650 \
  -nodes \
  -config "$repo_root/scripts/local-code-signing-openssl.cnf" \
  -keyout "$private_key_pem" \
  -out "$certificate_pem"

/usr/bin/openssl pkcs12 \
  -export \
  -name "$VOICE_LOCAL_SIGNING_IDENTITY" \
  -inkey "$private_key_pem" \
  -in "$certificate_pem" \
  -passout "pass:$temporary_passphrase" \
  -out "$identity_p12"

/usr/bin/security import "$identity_p12" \
  -k "$login_keychain" \
  -f pkcs12 \
  -P "$temporary_passphrase" \
  -x \
  -T /usr/bin/codesign

# User-scoped code-signing trust makes the self-signed identity valid for
# local packages without granting it SSL, S/MIME, or other certificate uses.
/usr/bin/security add-trusted-cert \
  -r trustRoot \
  -p codeSign \
  -k "$login_keychain" \
  "$certificate_pem"

fingerprint="$(voice_signing_identity_fingerprint "$VOICE_LOCAL_SIGNING_IDENTITY")"
echo "Created local Voice signing identity: $fingerprint"
echo "The private key is non-extractable and remains in the user's Keychain."
