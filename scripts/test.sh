#!/usr/bin/env bash
# Local gate: the CI gate plus the network-dependent Google render.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

./scripts/ci.sh

bin="$(swift build -c release --show-bin-path)"
"$bin/UrFonts" --headless google-detail --family Inter
