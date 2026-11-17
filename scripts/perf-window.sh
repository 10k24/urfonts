#!/usr/bin/env bash
# Real-window performance capture with Instruments.
#
# Interaction is manual: the script starts the recording, you scroll the list or
# grid with a trackpad, and the trace is left open for inspection. This is not a
# headless test and does not assert focus.
#
# Usage:
#   scripts/perf-window.sh launch [seconds]
#   scripts/perf-window.sh scroll [seconds]
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

mode="${1:-scroll}"
seconds="${2:-30}"
app="$root/build/UrFonts.app"

case "$mode" in
    launch)
        template="App Launch"
        ;;
    scroll)
        template="Animation Hitches"
        ;;
    *)
        echo "usage: scripts/perf-window.sh <launch|scroll> [seconds]" >&2
        exit 1
        ;;
esac

./scripts/build-app.sh >/dev/null
stamp="$(date +%Y%m%d-%H%M%S)"
trace="$root/build/perf-$mode-$stamp.trace"

if [ "$mode" = "launch" ]; then
    echo "Recording $template for ${seconds}s."
    xcrun xctrace record \
        --template "$template" \
        --launch "$app" \
        --time-limit "${seconds}s" \
        --output "$trace"
else
    pkill -f "build/UrFonts.app/Contents/MacOS/UrFonts" || true
    sleep 1
    open "$app"
    sleep 2
    pid="$(pgrep -n -f 'UrFonts.app/Contents/MacOS/UrFonts')"
    if [ -z "$pid" ]; then
        echo "could not find the running app" >&2
        exit 1
    fi
    echo "Recording $template for ${seconds}s."
    echo "Scroll the list or grid with a trackpad now."
    xcrun xctrace record \
        --template "$template" \
        --attach "$pid" \
        --time-limit "${seconds}s" \
        --output "$trace"
fi

echo "$trace"
open "$trace"
