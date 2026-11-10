#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ "$(uname -s)" != "Darwin" ]]; then
    echo "Capture input checks require macOS, a graphical session, and Accessibility permission." >&2
    exit 1
fi
mkdir -p .build/tmp .build/input-checks
export TMPDIR="$PWD/.build/tmp"
swiftc -parse-as-library -emit-module -emit-library -module-name IceCore Sources/IceCore/*.swift \
    -emit-module-path .build/input-checks/IceCore.swiftmodule -o .build/input-checks/libIceCore.dylib
swiftc -parse-as-library -I .build/input-checks -L .build/input-checks -lIceCore \
    -Xlinker -rpath -Xlinker "$PWD/.build/input-checks" \
    Sources/IceScreen/HotkeyMonitor.swift scripts/check-capture-input.swift -o .build/input-checks/capture-input
.build/input-checks/capture-input
