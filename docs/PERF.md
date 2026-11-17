# Real-window performance

The headless harness measures layout and display offscreen. It cannot measure the
Core Animation commit a visible window performs. These checks close that gap.
Record results in `BENCH.md` with the machine, OS, toolchain and library size.

## Before measuring

- `./scripts/ci.sh` is green.
- Power is connected, Low Power Mode is off, and no other heavy app is running.
- The Release bundle is current: `./scripts/build-app.sh`.
- The real library is indexed and the warm snapshot has been built once.

## Warm launch

```sh
./scripts/perf-window.sh launch 20
```

That records the `App Launch` template, then opens the trace. Read the launch
duration to first frame. Budget: under 400 ms from launch to first painted row.
Run it three times and keep the median.

## List scroll

1. Open `build/UrFonts.app`, choose All Fonts, List, and the 42 pt sample.
2. Run:

```sh
./scripts/perf-window.sh scroll 30
```

3. Scroll the list continuously up and down with a trackpad for the full
   recording.
4. In the `Animation Hitches` trace, record hitch time ratio, hitch count and
   longest hitch. A hitch longer than 8.3 ms is a missed frame.

Repeat for a search result and for a collection with a few hundred families.

## Grid scroll

Same as list scroll, with Grid selected. Record FPS and the longest hitch. The
budget is 60 fps. Keep the grid at four columns if the window is wide enough.

## Steady RSS

With the app running after a 30-second scroll:

```sh
pid=$(pgrep -n -f 'UrFonts.app/Contents/MacOS/UrFonts')
while kill -0 "$pid" 2>/dev/null; do
  ps -o rss= -p "$pid"
  sleep 1
done
```

Stop the loop after a minute. Divide the kilobytes by 1024 for MiB. Budget: under
300 MB steady, flat with library size.

## Activation

`./scripts/register-spike.sh` registers and unregisters real fonts through fontd.
Run it only when that is acceptable on the machine. Budget: one family to
confirmed scope under 250 ms.

## Record

Copy the numbers into `BENCH.md` under Results. Add the method and any caveat
next to the table, including which template produced each number. Do not adjust a
budget to make a run pass; fix the cause or record the miss.
