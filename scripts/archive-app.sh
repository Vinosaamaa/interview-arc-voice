#!/bin/zsh
set -euo pipefail

repo_root="${0:A:h:h}"
app_name="Interview Arc Voice.app"
app_path="$repo_root/dist/$app_name"
archive_path="$repo_root/dist/Interview-Arc-Voice.app.tar.gz"

if [[ ! -d "$app_path" ]]; then
  echo "Missing packaged app: $app_path" >&2
  exit 66
fi

for executable in InterviewArcVoice InterviewArcVoiceVerifier; do
  executable_path="$app_path/Contents/MacOS/$executable"
  if [[ ! -x "$executable_path" ]]; then
    echo "Packaged executable is not executable: $executable_path" >&2
    exit 66
  fi
done

temporary_root="$(mktemp -d)"
trap 'rm -rf "$temporary_root"' EXIT

/usr/bin/tar -czf "$temporary_root/voice-app.tar.gz" \
  -C "$repo_root/dist" \
  "$app_name"
/bin/mv "$temporary_root/voice-app.tar.gz" "$archive_path"

/usr/bin/tar -xzf "$archive_path" -C "$temporary_root"
for executable in InterviewArcVoice InterviewArcVoiceVerifier; do
  extracted="$temporary_root/$app_name/Contents/MacOS/$executable"
  if [[ ! -x "$extracted" ]]; then
    echo "Archive did not preserve executable mode: $executable" >&2
    exit 1
  fi
done
"$temporary_root/$app_name/Contents/MacOS/InterviewArcVoice" --verify-package

# GitHub Actions artifacts normalize unpacked file modes. Ship the verified
# archive as the canonical payload so download and re-upload promotion cannot
# turn app executables into ordinary data files.
rm -rf "$app_path"
echo "$archive_path"
