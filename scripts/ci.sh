#!/usr/bin/env bash
# Deterministic gate: tests, Release build, full fixture, index/search budgets,
# headless scenarios and bundle assembly. No network, no window server focus.
# `scripts/test.sh` adds the network-dependent Google render on top.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

# The CI runner's Xcode 26.3 asset agent can crash while compositing the layered
# raster icon. Exercise the legacy icns path in CI; release builds still require
# Assets.car.
export URFONTS_LEGACY_ICON=1

# Repo hygiene: generated fonts, databases and signing material never belong in
# the tree. Generated icon artifacts are rebuilt by build-app.sh.
forbidden="$(find . \
    -path ./.git -prune -o \
    -path ./.build -prune -o \
    -path ./build -prune -o \
    -type f \( \
        -iname '*.ttf' -o -iname '*.otf' -o -iname '*.ttc' -o \
        -iname '*.otc' -o -iname '*.dfont' -o \
        -name '.env' -o -name '*.p12' -o -name '*.p8' -o \
        -name '*.cer' -o -name '*.pem' -o -name '*.key' -o \
        -name '*.mobileprovision' -o -name '*.provisionprofile' \
    \) -print -quit)"
if [ -n "$forbidden" ]; then
    echo "repo hygiene: forbidden file in the tree: $forbidden" >&2
    exit 1
fi

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

# One-file delta: touch a fixture file, then scan only that path.
delta_file="$(find "$work/fixtures" -type f -name '*.ttf' -print -quit)"
touch "$delta_file"
delta_line="$("$bin/urfonts-cli" scan-changes \
    "$work/fixtures" "$delta_file" --db "$db" | grep '^delta ')"
echo "$delta_line"
delta_ms="$(echo "$delta_line" | awk '{print $2}')"
if ! awk -v ms="$delta_ms" 'BEGIN { exit !(ms < 50) }'; then
    echo "single-file delta ${delta_ms} ms exceeds the 50 ms budget" >&2
    exit 1
fi

# Search p99 must stay under 16 ms. The bench scenario enforces it.
"$bin/UrFonts" --headless bench --db "$db"

"$bin/UrFonts" --headless focus-check
"$bin/UrFonts" --headless render
"$bin/UrFonts" --headless list-spike
"$bin/UrFonts" --headless settings
"$bin/UrFonts" --headless help
"$bin/UrFonts" --headless welcome

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
test -x "build/UrFonts.app/Contents/MacOS/UrFonts"
