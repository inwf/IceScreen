#!/usr/bin/env bash
set -euo pipefail
panel_app="$1"
foreground_app="$2"
project_dir="$3"
log_dir="$4"
result=0
# A failed Swift precondition ends its process. Give each group its own process
# and completion file so one failure cannot hide another group's result.
for group in background controls resize capture transition appearance language settings; do
    prefix="$log_dir/panel-$group"
    rm -f "$prefix.result" "$prefix.stdout" "$prefix.stderr"
    echo "Running panel check group $group"
    launch=0
    open -W -n --stdout "$prefix.stdout" --stderr "$prefix.stderr" "$panel_app" \
        --args "$foreground_app" "$prefix.result" "$project_dir" "$group" || launch=$?
    for log in "$prefix.stdout" "$prefix.stderr"; do
        if [[ -f "$log" ]]; then cat "$log"; fi
    done
    if [[ $launch == 0 && -f "$prefix.result" && "$(cat "$prefix.result")" == passed ]]; then
        echo "PASS $group"
    else
        echo "FAIL $group (launch status $launch)" >&2
        result=1
    fi
done
exit "$result"
