#!/usr/bin/env bash
# The local gate. CI runs the same commands.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

swift test
swift run -c release UrFonts --headless focus-check
swift run -c release UrFonts --headless render
swift run -c release UrFonts --headless list-spike
