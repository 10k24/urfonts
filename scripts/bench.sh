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

    delta_file="$(find "$work/library" -type f -name '*.ttf' -print -quit)"
    touch "$delta_file"
    "$bin/urfonts-cli" scan-changes \
        "$work/library" "$delta_file" --db "$db" | grep '^delta '
fi

"$bin/UrFonts" --headless bench --db "$db" | grep -E "load=|FAIL" || true

# Sample RSS while the row scroll runs. Peak RSS from /usr/bin/time includes
# one-off allocations; this shows the steady range the budget cares about.
rss_samples="$(mktemp -t urfonts-bench-rss)"
"$bin/UrFonts" --headless scroll --rows --db "$db" \
    >"$work/scroll.log" 2>&1 &
scroll_pid=$!
while kill -0 "$scroll_pid" 2>/dev/null; do
    ps -o rss= -p "$scroll_pid" >>"$rss_samples" 2>/dev/null || true
    sleep 0.2
done
scroll_exit=0
wait "$scroll_pid" || scroll_exit=$?
if [ "$scroll_exit" -ne 0 ]; then
    echo "scroll check failed (exit $scroll_exit)"
fi

grep -oE "pass2 p50=[0-9.]+ p99=[0-9.]+ max=[0-9.]+" \
    "$work/scroll.log" | tail -1
sort -n "$rss_samples" | awk '
    { sample[NR] = $1 }
    END {
        if (NR == 0) exit
        printf "RSS p50 %.1f MiB, p95 %.1f MiB, max %.1f MiB\n",
            sample[int((NR - 1) * 0.5) + 1] / 1024,
            sample[int((NR - 1) * 0.95) + 1] / 1024,
            sample[NR] / 1024
    }'
