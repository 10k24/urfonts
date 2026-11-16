#!/usr/bin/env bash
# Deterministic gate: tests, Release build, full fixture, index/search budgets,
# headless scenarios and bundle assembly. No network, no window server focus.
# `scripts/test.sh` adds the network-dependent Google render on top.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

swift test
swift build -c release

bin="$(swift build -c release --show-bin-path)"

work="${RUNNER_TEMP:-${TMPDIR:-/tmp}}/urfonts-ci"
mkdir -p "$work"

fixture_count="${URFONTS_FIXTURE_COUNT:-23000}"
swift run -c release FixtureGen \
    --out "$work/fixtures" --count "$fixture_count" --subdirs 100

db="$(mktemp -t urfonts-ci-db)"
/usr/bin/time -p "$bin/urfonts-cli" index "$work/fixtures" --db "$db" \
    >"$work/index.log" 2>"$work/index.time"
grep "database:" "$work/index.log"
cold_index="$(awk '/^real / {print $2}' "$work/index.time")"
if ! awk -v seconds="$cold_index" 'BEGIN { exit !(seconds < 30) }'; then
    echo "cold index ${cold_index}s exceeds the 30s budget" >&2
    exit 1
fi
echo "cold index ${cold_index}s"
"$bin/urfonts-cli" stats --db "$db"
"$bin/urfonts-cli" search "Fixture" --db "$db" | grep -q "Fixture"

# Search p99 must stay under 16 ms. The bench scenario enforces it.
"$bin/UrFonts" --headless bench --db "$db"

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
