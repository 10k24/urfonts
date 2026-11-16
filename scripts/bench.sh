#!/usr/bin/env bash
# Release performance sample. Without --db, generates a fixture library and
# times a cold index, then measures that database. With --db, measures an
# existing library and skips indexing.
#
# Usage: scripts/bench.sh [--db PATH] [--count N]
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

db=""
count=23000
while [ $# -gt 0 ]; do
    case "$1" in
        --db)
            db="${2:?--db needs a path}"
            shift 2
            ;;
        --count)
            count="${2:?--count needs a number}"
            shift 2
            ;;
        *)
            echo "usage: scripts/bench.sh [--db PATH] [--count N]" >&2
            exit 1
            ;;
    esac
done

swift build -c release
bin="$(swift build -c release --show-bin-path)"
work="${TMPDIR:-/tmp}/urfonts-bench"
mkdir -p "$work"

if [ -z "$db" ]; then
    swift run -c release FixtureGen \
        --out "$work/library" --count "$count" --subdirs 100
    db="$(mktemp -t urfonts-bench-db)"
    /usr/bin/time -p "$bin/urfonts-cli" index "$work/library" --db "$db" \
        >"$work/index.log" 2>"$work/index.time"
    grep "database:" "$work/index.log"
    awk '/^real / {print "cold index " $2 " s"}' "$work/index.time"
fi

"$bin/UrFonts" --headless bench --db "$db" | grep -E "load=|FAIL" || true

/usr/bin/time -l "$bin/UrFonts" --headless scroll --rows --db "$db" \
    >"$work/scroll.log" 2>"$work/scroll.time" || true
grep -oE "pass2 p50=[0-9.]+ p99=[0-9.]+ max=[0-9.]+" \
    "$work/scroll.log" | tail -1
awk '/maximum resident set size/ {
    printf "peak RSS %.1f MiB\n", $1 / 1048576
}' "$work/scroll.time"
