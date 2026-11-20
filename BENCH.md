# Benchmarks

Release-build measurements on the development machine. These are regression
data, not marketing numbers. Re-run the commands before trusting a row after a
code change.

## Environment

- Machine: MacBook Pro (M1 Pro, 16-inch, 2021)
- OS: macOS 27.2
- Toolchain: Xcode 27.2, Swift 6.4.2
- Build: `swift build -c release`
- Real library: 24,901 fonts across 3,211 families, Dropbox folders
  materialized locally. This is the library at measurement time; re-run before
  comparing against the current library.

## Commands

```sh
# Full scripted run against the real library (no indexing)
./scripts/bench.sh --db "$HOME/Library/Application Support/Ur Fonts/library.sqlite3"

# Snapshot load and synchronous search rebuild
.build/release/UrFonts --headless bench

# Real browser rows, one row per scroll step
.build/release/UrFonts --headless scroll --rows

# Worst-case jumps across the list
.build/release/UrFonts --headless scroll

# Cold index of the 23,000-font fixture
.build/release/urfonts-cli index build/fixtures/library --db /tmp/bench.sqlite3

# One-file delta after the index. Touch only a generated fixture file.
touch build/fixtures/library/<file>.ttf
.build/release/urfonts-cli scan-changes build/fixtures/library \
    build/fixtures/library/<file>.ttf --db /tmp/bench.sqlite3
```

`--headless scroll` measures an offscreen window. It includes layout and display
but not the Core Animation commit a real window performs, so treat its p99 as a
lower bound until a signpost run confirms it. The real-window protocol is in
`docs/PERF.md`.

## Results

| Measurement | Result | Budget | Status |
|---|---|---|---|
| Cold index, 23,000 files | 3.51 s | under 30 s | pass |
| Single-file delta, 23,000-file fixture | 10.12 ms | under 50 ms | pass |
| Snapshot load, real library | 691.3 ms | not a gate | — |
| Search rebuild p50 | 5.65 ms | — | — |
| Search rebuild p99 | 7.03 ms | under 16 ms | pass |
| Scroll rows p50 | 6.51 ms | — | — |
| Scroll rows p99 | 10.28 ms | under 8.3 ms | fail |
| Scroll rows max | 15.25 ms | — | — |
| Scroll RSS p50 | 216.5 MiB | under 300 MB | pass |
| Scroll RSS p95 | 321.6 MiB | under 300 MB | fail |
| Scroll RSS max | 334.2 MiB | under 300 MB | fail |
| Scroll jump p99 | 26.84 ms | — | stress |
| Scroll jump peak RSS | 463.1 MiB | under 300 MB | — |

## Notes

- Snapshot load is the database open plus the in-memory catalog build. It is not
  launch to first painted row, which still needs a signpost measurement in a real
  window.
- RSS is sampled every 200 ms while the row scroll runs. The median stays under
  the budget; the p95 and max show that allocation spikes still cross it. The
  row-run max is 334.2 MiB; the jump stress peak is 463.1 MiB.
- The row-step p99 misses the 8.3 ms budget in the offscreen harness. The harness
  itself fails only above 16 ms, and the jump stress mode fails that limit. Do
  not relax the budget without a real-window measurement and a reason in
  `AGENTS.md`.
- The delta timer starts after the database opens and covers only the scan, not
  FSEvents delivery or process startup. Before this change the scanner loaded
  all 23,000 stamps and the delta measured 50.11 ms; it now loads only the
  changed path and measures 9.13 ms standalone, 10.12 ms in CI.
- Not measured yet: warm launch to first painted row, grid frame rate, one-family
  activation, and steady RSS under an actual drag. The scroll sample is the
  closest current proxy; activation has `scripts/register-spike.sh` for a
  per-font registration sample.
- CI enforces the cold-index, delta and search budgets on the 23,000-font
  fixture. The scroll and RSS rows stay local until a real-window signpost run
  exists.
