#!/bin/zsh
set -euo pipefail

repo_root="${0:A:h:h}"
cd "$repo_root"

swift build -c release
bin_dir="$(swift build -c release --show-bin-path)"
app_dir="$repo_root/dist/Interview Arc Voice.app"
contents_dir="$app_dir/Contents"

rm -rf "$app_dir"
mkdir -p "$contents_dir/MacOS" "$contents_dir/Resources"
cp "$repo_root/Resources/Info.plist" "$contents_dir/Info.plist"
cp "$bin_dir/InterviewArcVoice" "$contents_dir/MacOS/InterviewArcVoice"
cp "$repo_root/Resources/AppIcon.icns" "$contents_dir/Resources/AppIcon.icns"

for resource_bundle in "$bin_dir"/*.bundle; do
  if [[ -d "$resource_bundle" ]]; then
    cp -R "$resource_bundle" "$contents_dir/Resources/"
  fi
done

# CI has no access to the user's private local signing identity. This ad-hoc
# signature is therefore a transport signature only: it makes the artifact
# internally verifiable but is not a stable installation identity. Before an
# artifact replaces the installed app, scripts/sign-app-for-install.sh applies
# the persistent certificate-backed identity from the user's Keychain.
signing_requirement='=designated => identifier "app.interviewarc.voice"'
codesign --force --deep --sign - --requirements "$signing_requirement" "$app_dir"
codesign --verify --deep --strict "$app_dir"

actual_requirement="$(codesign -d -r- "$app_dir" 2>&1)"
if [[ "$actual_requirement" != *'designated => identifier "app.interviewarc.voice"'* ]]; then
  echo "Packaged app is missing the stable designated requirement." >&2
  exit 1
fi

"$contents_dir/MacOS/InterviewArcVoice" --verify-package
echo "$app_dir"
