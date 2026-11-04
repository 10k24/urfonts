#!/usr/bin/env bash
# Registration cost and behavior, measured against the fixture library.
# Run from the repo root. Leaves no fonts registered.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

swift build -c release
bin=".build/release/urfonts-cli"
library="build/fixtures/library"

if [ ! -d "$library" ]; then
    echo "missing fixtures. run: swift run -c release FixtureGen" >&2
    exit 1
fi

# Start clean.
for limit in 1000 100 1; do
    "$bin" deactivate --limit "$limit" "$library" >/dev/null 2>&1 || true
done

for limit in 1 100 1000; do
    echo "--- $limit fonts"
    "$bin" activate --timing --limit "$limit" "$library" || true
    "$bin" deactivate --timing --limit "$limit" "$library" || true
done

echo "--- duplicate PostScript name"
first="$(find "$library" -name '*.ttf' | head -1)"
cp "$first" /tmp/urfonts-duplicate.ttf
"$bin" activate "$first" >/dev/null
"$bin" activate "$first" || true
"$bin" activate /tmp/urfonts-duplicate.ttf || true
"$bin" deactivate "$first" /tmp/urfonts-duplicate.ttf >/dev/null
