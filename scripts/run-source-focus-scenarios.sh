#!/usr/bin/env bash
set -euo pipefail
fixtures="${1:?Pass the absolute fixture directory}"
report="${2:?Pass the absolute output directory}"
project="${3:?Pass the absolute working directory}"
mkdir -p "$report"
result=0
for scenario in terminal interactions; do
    completion="$report/$scenario.result"
    stdout="$report/$scenario.stdout"
    stderr="$report/$scenario.stderr"
    rm -f "$completion" "$completion.jsonl" "$stdout" "$stderr"
    launch_status=0
    open -W -n --stdout "$stdout" --stderr "$stderr" "$fixtures/Checks.app" \
        --args "$fixtures" "$completion" "$project" "$scenario" || launch_status=$?
    for output in "$stdout" "$stderr"; do if [[ -f "$output" ]]; then cat "$output"; fi; done
    if [[ "$launch_status" != 0 || ! -f "$completion" ]] || [[ "$(cat "$completion")" != "passed" ]]; then
        echo "Source focus scenario failed: $scenario (launch status $launch_status)." >&2
        result=1
    else
        echo "Source focus scenario passed: $scenario."
    fi
done
exit "$result"
