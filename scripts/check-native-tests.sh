#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ "$(uname -s)" != "Darwin" ]]; then
    echo "Native checks require a macOS graphical session." >&2
    exit 1
fi
result=0
if bash scripts/check-panel-events.sh; then
    echo "Native panel checks: passed."
else
    echo "Native panel checks: failed." >&2
    result=1
fi
if bash scripts/check-source-focus.sh "$@"; then
    echo "Native source focus checks: passed."
else
    echo "Native source focus checks: failed." >&2
    result=1
fi
exit "$result"
