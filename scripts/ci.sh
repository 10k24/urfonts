#!/usr/bin/env bash
# Deterministic gate: tests, Release build, fixtures, CLI round trip, headless
# scenarios and bundle assembly. No network, no window server focus.
# `scripts/test.sh` adds the network-dependent Google render on top.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

swift test
swift build -c release

bin="$(swift build -c release --show-bin-path)"

work="${RUNNER_TEMP:-${TMPDIR:-/tmp}}/urfonts-ci"
mkdir -p "$work"

swift run -c release FixtureGen \
    --out "$work/fixtures" --count 2000 --subdirs 20

db="$(mktemp -t urfonts-ci-db)"
"$bin/urfonts-cli" index "$work/fixtures" --db "$db"
"$bin/urfonts-cli" stats --db "$db"
"$bin/urfonts-cli" search "Fixture" --db "$db" | grep -q "Fixture"

"$bin/UrFonts" --headless focus-check
"$bin/UrFonts" --headless render
"$bin/UrFonts" --headless list-spike
"$bin/UrFonts" --headless settings

# Two real system fonts keep these independent of the user's library.
fonts=()
while IFS= read -r path; do
    fonts+=("$path")
done < <(find /System/Library/Fonts -type f -name '*.ttf' 2>/dev/null | head -2)
if [ "${#fonts[@]}" -eq 2 ]; then
    add_db="$(mktemp -t urfonts-ci-add)"
    "$bin/UrFonts" --headless add-files --db "$add_db" --no-rescan "${fonts[@]}"

    ignore_db="$(mktemp -t urfonts-ci-ignore)"
    "$bin/UrFonts" --headless ignore-folder --db "$ignore_db" --no-rescan "${fonts[@]}"
fi

./scripts/build-app.sh >/dev/null
test -x "build/Ur Fonts.app/Contents/MacOS/UrFonts"
