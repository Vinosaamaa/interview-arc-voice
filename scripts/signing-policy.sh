#!/bin/zsh

VOICE_BUNDLE_IDENTIFIER="app.interviewarc.voice"
VOICE_LOCAL_SIGNING_IDENTITY="Interview Arc Voice Local Signing"

voice_signing_requirement() {
  local certificate_sha1="${1:u}"
  if [[ ! "$certificate_sha1" =~ '^[0-9A-F]{40}$' ]]; then
    echo "Expected a 40-character certificate SHA-1 fingerprint." >&2
    return 1
  fi

  echo "=designated => identifier \"$VOICE_BUNDLE_IDENTIFIER\" and certificate leaf = H\"$certificate_sha1\""
}

voice_signing_identity_fingerprint() {
  local identity_name="$1"
  /usr/bin/security find-identity -v -p codesigning \
    | /usr/bin/awk -v expected="\"$identity_name\"" \
      'index($0, expected) { print toupper($2); matches += 1 } END { if (matches != 1) exit 1 }'
}

voice_app_bundle_identifier() {
  local app_path="$1"
  /usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app_path/Contents/Info.plist"
}

voice_app_executable_path() {
  local app_path="$1"
  local executable
  executable="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$app_path/Contents/Info.plist")"
  echo "$app_path/Contents/MacOS/$executable"
}
