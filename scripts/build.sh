#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ "$(uname -s)" != "Darwin" ]]; then
    echo "Building IceScreen.app requires macOS and Xcode 26 or later." >&2
    exit 1
fi
sdk_version="$(xcrun --sdk macosx --show-sdk-version)"
if [[ "${sdk_version%%.*}" -lt 26 ]]; then
    echo "Select Xcode 26 or later to build Liquid Glass controls." >&2
    exit 1
fi
mkdir -p .build/tmp
export TMPDIR="$PWD/.build/tmp"
configuration="${CONFIGURATION:-release}"
signing_identity="${SIGN_IDENTITY:--}"
app_dir="$PWD/dist/IceScreen.app"
mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources" .build/iconset
build_args=(-c "$configuration")
if [[ "${UNIVERSAL:-0}" == "1" ]]; then
    build_args+=(--arch arm64 --arch x86_64)
fi
swift build "${build_args[@]}"
binary_dir="$(swift build "${build_args[@]}" --show-bin-path)"
cp "$binary_dir/IceScreen" "$app_dir/Contents/MacOS/IceScreen"
cp Sources/IceScreen/Resources/Info.plist "$app_dir/Contents/Info.plist"
cp LICENSE NOTICE "$app_dir/Contents/Resources/"
swift scripts/make-icon.swift .build/iconset
iconutil -c icns .build/iconset/AppIcon.iconset -o "$app_dir/Contents/Resources/AppIcon.icns"
if [[ "$configuration" == "release" ]]; then
    strip -x "$app_dir/Contents/MacOS/IceScreen"
fi
codesign --force --options runtime --sign "$signing_identity" "$app_dir"
codesign --verify --strict --verbose=2 "$app_dir"
echo "Built $app_dir"
bash scripts/package-dmg.sh
