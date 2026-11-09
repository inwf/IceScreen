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
    -emit-module-path .build/checks/IceCore.swiftmodule -o .build/checks/libIceCore.dylib
app_sources=()
for source in Sources/IceScreen/*.swift; do
    if [[ "$source" != "Sources/IceScreen/IceScreenApp.swift" ]]; then
        app_sources+=("$source")
    fi
done
swiftc -parse-as-library -I .build/checks -L .build/checks -lIceCore \
    -Xlinker -rpath -Xlinker "$PWD/.build/checks" \
    "${app_sources[@]}" scripts/check-panel-events.swift -o .build/checks/panel-events
.build/checks/panel-events
