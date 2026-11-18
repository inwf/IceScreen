#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ "$(uname -s)" != "Darwin" ]]; then
    echo "Native panel checks require a macOS graphical session." >&2
    exit 1
fi
mkdir -p .build/tmp .build/checks
export TMPDIR="$PWD/.build/tmp"
swiftc -parse-as-library -emit-module -emit-library -module-name IceCore Sources/IceCore/*.swift \
    -Xlinker -install_name -Xlinker @rpath/libIceCore.dylib \
    -emit-module-path .build/checks/IceCore.swiftmodule -o .build/checks/libIceCore.dylib
app_sources=()
for source in Sources/IceScreen/*.swift; do
    if [[ "$source" != "Sources/IceScreen/IceScreenApp.swift" ]]; then
        app_sources+=("$source")
    fi
done
swiftc -parse-as-library -D PANEL_EVENT_DIAGNOSTICS -I .build/checks -L .build/checks -lIceCore \
    -Xlinker -rpath -Xlinker @executable_path/../Frameworks \
    "${app_sources[@]}" scripts/check-panel-events.swift -o .build/checks/panel-events
codesign --force --sign - .build/checks/libIceCore.dylib
for name in PanelChecks Foreground; do
    bundle="$PWD/.build/checks/$name.app"
    rm -rf "$bundle"
    mkdir -p "$bundle/Contents/MacOS" "$bundle/Contents/Frameworks"
    cp .build/checks/panel-events "$bundle/Contents/MacOS/panel-events"
    cp .build/checks/libIceCore.dylib "$bundle/Contents/Frameworks/"
    cp scripts/panel-checks.plist "$bundle/Contents/Info.plist"
    if [[ "$name" == "Foreground" ]]; then
        /usr/libexec/PlistBuddy -c 'Set :CFBundleIdentifier org.icescreen.checks.foreground' \
            -c 'Set :CFBundleName IceScreen Foreground Checks' -c 'Set :LSUIElement false' "$bundle/Contents/Info.plist"
    fi
    codesign --force --sign - "$bundle"
done
bash scripts/run-panel-check-groups.sh "$PWD/.build/checks/PanelChecks.app" \
    "$PWD/.build/checks/Foreground.app" "$PWD" "$PWD/.build/checks"
