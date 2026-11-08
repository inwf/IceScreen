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
staging_dir="$(mktemp -d "$PWD/.build/dmg.XXXXXX")"
trap 'rm -rf "$staging_dir"' EXIT
ditto "$app_dir" "$staging_dir/IceScreen.app"
ln -s /Applications "$staging_dir/Applications"

hdiutil create -volname IceScreen -srcfolder "$staging_dir" \
    -fs HFS+ -format UDZO -imagekey zlib-level=9 -ov "$output_file"
hdiutil verify "$output_file"

if [[ "${SIGN_IDENTITY:--}" != "-" ]]; then
    codesign --force --sign "$SIGN_IDENTITY" "$output_file"
    codesign --verify --strict "$output_file"
fi

echo "Built $output_file"
