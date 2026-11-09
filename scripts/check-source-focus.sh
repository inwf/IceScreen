#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ "$(uname -s)" != "Darwin" ]]; then
    echo "Source focus checks require a macOS graphical session and Accessibility / Screen Recording permissions." >&2
    exit 1
fi
mkdir -p .build/tmp .build/focus-checks
export TMPDIR="$PWD/.build/tmp"
swiftc -parse-as-library -emit-module -emit-library -module-name IceCore Sources/IceCore/*.swift \
    -emit-module-path .build/focus-checks/IceCore.swiftmodule -o .build/focus-checks/libIceCore.dylib
app_sources=()
for source in Sources/IceScreen/*.swift; do
    if [[ "$source" != "Sources/IceScreen/IceScreenApp.swift" ]]; then app_sources+=("$source"); fi
done
swiftc -parse-as-library -I .build/focus-checks -L .build/focus-checks -lIceCore \
    -Xlinker -rpath -Xlinker "$PWD/.build/focus-checks" \
    "${app_sources[@]}" scripts/check-source-focus.swift -o .build/focus-checks/source-focus
for fixture in Source Other; do
    bundle="$PWD/.build/focus-checks/$fixture.app"
    mkdir -p "$bundle/Contents/MacOS"
    cp .build/focus-checks/source-focus "$bundle/Contents/MacOS/Fixture"
    /usr/libexec/PlistBuddy -c 'Clear dict' \
        -c "Add :CFBundleIdentifier string org.icescreen.tests.$fixture" \
        -c "Add :CFBundleName string $fixture" \
        -c 'Add :CFBundleExecutable string Fixture' \
        -c 'Add :CFBundlePackageType string APPL' "$bundle/Contents/Info.plist"
    codesign --force --sign - "$bundle"
done
.build/focus-checks/source-focus "$PWD/.build/focus-checks"
