# App icon pipeline

Two artifacts ship in `URFonts.app/Contents/Resources`:

| File | Used by | Source |
|---|---|---|
| `Assets.car` | macOS 26+ (light, dark, tinted, Liquid Glass) | `design/icon/UrFonts.icon` |
| `UrFonts.icns` | macOS 15–25 (light only) | `design/icon/legacy/icon-1024.png` |

`Info.plist` sets `CFBundleIconName = UrFonts` and
`CFBundleIconFile = UrFonts.icns`.

## What to design

Start from Apple's App Icon template from
<https://developer.apple.com/design/resources> — the current 1024 px grid.
Do not draw the grid or the mask by hand.

For the Liquid Glass icon:

- Artboard: 1024 × 1024, sRGB.
- Work in layers, back to front: background, middle, foreground. Three to four
  layers is plenty.
- Keep artwork inside the template's safe grid. The system applies the rounded
  rectangle mask; do not bake corners, borders or drop shadows.
- Convert text to outlines.
- Keep the background as a flat fill or gradient layer; Icon Composer adds the
  glass material.
- Export each layer as SVG with Apple's Illustrator layer-to-SVG script. Name
  them in z-order, `01-background.svg`, `02-mark.svg`, `03-detail.svg`.
  PNG layers are acceptable if the artwork is raster.

For the legacy icon (macOS 15–25):

- One 1024 × 1024 PNG on a transparent canvas, drawn with the Big Sur app icon
  template: rounded square with the standard margin and shadow already baked in.
- sRGB, no Liquid Glass effects.
- This is the light appearance only; macOS 15–25 has no dark icon variant.

The current legacy PNG is derived from the 1024 px iOS export: the art is
centered at 824 × 824 with a soft shadow, so it matches the Big Sur grid.

## Dark mode: one icon, two appearances

You do not need a second design. In Icon Composer the same layer stack is
annotated for Default (light), Dark and Mono:

- Dark usually means a darker, slightly desaturated background and the same
  foreground. Adjust the background layer's fill or opacity in the Dark
  appearance.
- Mono controls tinted and clear variants on macOS 26+. If it is not designed,
  Icon Composer's default is acceptable.
- Preview both appearances in Icon Composer before saving. Do not export separate
  flattened PNGs for dark; the `.icon` carries both.

## Files this repo expects

```
design/icon/
  UrFonts.icon                 Icon Composer file (a package)
  urfonts-v2-1024.png          Flattened Icon Composer export (source artwork)
  urfonts-icon.ai              Illustrator source
  legacy/
    icon-1024.png              Big Sur style, transparent, light only
```

The `.icon` package uses the UR mark extracted from `urfonts-v2-1024.png` as its
foreground layer, with the background kept as an adaptive fill. The legacy PNG is
the flattened export inset to the 824 px Big Sur body.

## Build

```sh
./scripts/build-icons.sh
./scripts/build-app.sh
```

`build-icons.sh` runs `actool` for `Assets.car`, then regenerates
`UrFonts.icns` from the legacy PNG with `sips` and `iconutil`. It fails with a
clear message when a source is missing.

`UrFonts.icon` is authored by hand in Icon Composer; this repo does not generate
it. Keep the `.icon` package in git so the icon is reproducible.
