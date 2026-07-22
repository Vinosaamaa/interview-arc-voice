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

codesign --force --deep --sign - "$app_dir"
"$contents_dir/MacOS/InterviewArcVoice" --verify-package
echo "$app_dir"
