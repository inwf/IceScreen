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
    -Xlinker -install_name -Xlinker @rpath/libIceCore.dylib \
    -emit-module-path .build/focus-checks/IceCore.swiftmodule -o .build/focus-checks/libIceCore.dylib
app_sources=()
for source in Sources/IceScreen/*.swift; do
    if [[ "$source" != "Sources/IceScreen/IceScreenApp.swift" ]]; then app_sources+=("$source"); fi
done
swiftc -parse-as-library -I .build/focus-checks -L .build/focus-checks -lIceCore \
    -Xlinker -rpath -Xlinker @executable_path/../Frameworks \
    "${app_sources[@]}" scripts/check-source-focus.swift -o .build/focus-checks/source-focus
codesign --force --sign - .build/focus-checks/libIceCore.dylib
for fixture in Checks Source Other; do
    bundle="$PWD/.build/focus-checks/$fixture.app"
    rm -rf "$bundle"
    mkdir -p "$bundle/Contents/MacOS" "$bundle/Contents/Frameworks"
    cp .build/focus-checks/source-focus "$bundle/Contents/MacOS/source-focus"
    cp .build/focus-checks/libIceCore.dylib "$bundle/Contents/Frameworks/"
    cp scripts/panel-checks.plist "$bundle/Contents/Info.plist"
    identifier="org.icescreen.tests.$fixture"
    if [[ "$fixture" == "Checks" ]]; then identifier="org.icescreen.tests.source-focus"; fi
    /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $identifier" \
        -c "Set :CFBundleName IceScreen $fixture Focus Checks" \
        -c 'Set :CFBundleExecutable source-focus' "$bundle/Contents/Info.plist"
    if [[ "$fixture" != "Checks" ]]; then
        /usr/libexec/PlistBuddy -c 'Set :LSUIElement false' "$bundle/Contents/Info.plist"
    fi
    codesign --force --sign - "$bundle"
done
if [[ "${1:-}" == "--ci" ]]; then
    if [[ "${GITHUB_ACTIONS:-}" != "true" ]]; then
        echo "CI permission setup is only available in the ephemeral GitHub runner." >&2
        exit 1
    fi
    csreq -r='identifier "org.icescreen.tests.source-focus"' -b .build/focus-checks/source-focus.csreq
    sudo env GITHUB_ACTIONS=true "$(command -v python3)" scripts/grant-focus-test-permissions.py \
        "$PWD/.build/focus-checks/Checks.app" "$PWD/.build/focus-checks/source-focus.csreq"
elif [[ $# != 0 ]]; then
    echo "Usage: check-source-focus.sh [--ci]" >&2
    exit 1
fi
completion="$PWD/.build/focus-checks/source-focus.result"
stdout="$PWD/.build/focus-checks/source-focus.stdout"
stderr="$PWD/.build/focus-checks/source-focus.stderr"
rm -f "$completion" "$stdout" "$stderr"
open -W -n --stdout "$stdout" --stderr "$stderr" "$PWD/.build/focus-checks/Checks.app" \
    --args "$PWD/.build/focus-checks" "$completion" "$PWD"
cat "$stdout" "$stderr"
if [[ ! -f "$completion" ]] || [[ "$(cat "$completion")" != "passed" ]]; then
    echo "Source focus checks did not complete successfully." >&2
    exit 1
fi
