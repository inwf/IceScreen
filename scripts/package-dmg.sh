#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

if [[ "$(uname -s)" != "Darwin" ]]; then
    echo "Packaging IceScreen.dmg requires macOS and hdiutil." >&2
    exit 1
fi

app_dir="$PWD/dist/IceScreen.app"
output_file="$PWD/dist/IceScreen-macOS.dmg"
if [[ ! -x "$app_dir/Contents/MacOS/IceScreen" ]]; then
    echo "Build dist/IceScreen.app before packaging." >&2
    exit 1
fi

codesign --verify --strict "$app_dir"
mkdir -p .build dist
export TMPDIR="$PWD/.build/tmp"
mkdir -p "$TMPDIR"
staging_dir="$(mktemp -d "$PWD/.build/dmg.XXXXXX")"
mount_dir="$staging_dir/mounted"
image_path="$staging_dir/writable.dmg"
mkdir -p "$staging_dir/content/.background" "$mount_dir"
mounted=0
cleanup() {
    if [[ "$mounted" == "1" ]]; then hdiutil detach "$mount_dir"; fi
    rm -rf "$staging_dir"
}
trap cleanup EXIT
ditto "$app_dir" "$staging_dir/content/IceScreen.app"
ln -s /Applications "$staging_dir/content/Applications"
cp assets/dmg-background.tiff "$staging_dir/content/.background/"
cp "$app_dir/Contents/Resources/AppIcon.icns" "$staging_dir/content/.VolumeIcon.icns"
hdiutil create -volname IceScreen -srcfolder "$staging_dir/content" -fs HFS+ -format UDRW -ov "$image_path"
hdiutil attach -nobrowse -noverify -mountpoint "$mount_dir" "$image_path"
mounted=1
osascript scripts/configure-dmg.applescript "$mount_dir" "$mount_dir/.background/dmg-background.tiff"
xcrun SetFile -a C "$mount_dir"
hdiutil detach "$mount_dir"
mounted=0
hdiutil convert "$image_path" -format UDZO -imagekey zlib-level=9 -ov -o "$output_file"
hdiutil verify "$output_file"

if [[ "${SIGN_IDENTITY:--}" != "-" ]]; then
    codesign --force --sign "$SIGN_IDENTITY" "$output_file"
    codesign --verify --strict "$output_file"
fi

echo "Built $output_file"
