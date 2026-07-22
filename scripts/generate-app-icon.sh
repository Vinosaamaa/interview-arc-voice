#!/bin/zsh
set -euo pipefail

repo_root="${0:A:h:h}"
source_png="$repo_root/Resources/AppIcon.png"
output_icns="$repo_root/Resources/AppIcon.icns"
work_dir="$(mktemp -d)"

trap 'rm -rf "$work_dir"' EXIT

# Build every standard macOS icon size from the checked-in 1024 px master.
for size in 16 32 64 128 256 512 1024; do
  sips -z "$size" "$size" "$source_png" --out "$work_dir/icon_${size}x${size}.png" >/dev/null
done

python3 "$repo_root/scripts/package_icns.py" "$work_dir" "$output_icns"
echo "$output_icns"
