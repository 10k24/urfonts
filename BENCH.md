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
  materialized locally

## Commands

```sh
# Snapshot load and synchronous search rebuild
.build/release/UrFonts --headless bench

# Real browser rows, one row per scroll step
.build/release/UrFonts --headless scroll --rows

# Worst-case jumps across the list
.build/release/UrFonts --headless scroll

# Cold index of the 23,000-font fixture
.build/release/urfonts-cli index build/fixtures/library --db /tmp/bench.sqlite3
```

`--headless scroll` measures an offscreen window. It includes layout and display
but not the Core Animation commit a real window performs, so treat its p99 as a
lower bound until a signpost run confirms it.

## Results

| Measurement | Result | Budget | Status |
|---|---|---|---|
| Cold index, 23,000 files | 4.05 s | under 30 s | pass |
| Snapshot load, real library | 853.7 ms | not a gate | — |
| Search rebuild p50 | 5.98 ms | — | — |
| Search rebuild p99 | 7.27 ms | under 16 ms | pass |
| Scroll rows p50 | 6.48 ms | — | — |
| Scroll rows p99 | 13.96 ms | under 8.3 ms | fail |
| Scroll rows max | 14.46 ms | — | — |
| Scroll rows peak RSS | 334.8 MiB | under 300 MB steady | fail |
| Scroll jump p99 | 27.11 ms | — | stress |
| Scroll jump peak RSS | 414.2 MiB | under 300 MB steady | — |

First scroll pass on the same run: rows p50 6.93 ms, p99 11.64 ms, max 12.77 ms;
jump p50 20.32 ms, p99 37.86 ms, max 65.08 ms. The second pass is recorded in the
table because the first includes cold row creation.

## Notes

- Snapshot load is the database open plus the in-memory catalog build. It is not
  launch to first painted row, which still needs a signpost measurement in a real
  window.
- Peak RSS is the whole process at its highest point during the run, including
  AppKit and SwiftUI. The 300 MB budget is for steady RSS while scrolling; the
  harness does not sample steady state yet.
- The row-step p99 misses the 8.3 ms budget in the offscreen harness. The harness
  itself fails only above 16 ms, and the jump stress mode fails that limit. Do
  not relax the budget without a real-window measurement and a reason in
  `AGENTS.md`.
- Not measured yet: warm launch to first painted row, grid frame rate, single
  file delta, one-family activation, and steady RSS. Activation has
  `scripts/register-spike.sh` for a per-font registration sample.
