# Domo

A small macOS menu bar app for the smart things around the house.
Click the icon, change what you need, get back to work.

<p align="center">
  <img src="docs/screenshot.png" width="400" alt="Domo's air conditioner panel">
  &nbsp;
  <img src="docs/setup.png" width="400" alt="Connecting Domo to LG ThinQ">
</p>

## What it controls

| Accessory | Integration | Status |
| --- | --- | --- |
| Air conditioner | LG ThinQ (official ThinQ Connect API) | ✅ Working |
| Cat feeder | Xiaomi (local miIO) | Planned |
| Smart plugs | Meross (local HTTP) | Planned |
| Lights, curtains, door, cameras | — | Planned |

### Air conditioner

- Power, target temperature (slider or −/+), Eco Mode
- Mode, fan speed, sleep timer and swing direction from native menus
- Room temperature, and the set temperature right in the menu bar
- Reads what your unit actually supports from LG's device profile: per-mode
  temperature ranges, 0.5° steps, the fan speeds it offers
- Changes apply instantly and roll back if LG rejects them; rapid −/+ taps
  are sent as one command

The motion is deliberately quiet: digits roll when the temperature changes,
the vent glows in the mode's color while the unit runs, buttons react on
press, and everything falls back to simple fades when *Reduce Motion* is on.

## Requirements

- macOS 26 or later
- Swift 6.2+ (Xcode 26 or later, or the matching Command Line Tools)

## Build and install

```bash
./build.sh
```

This builds a release binary, wraps it in `Domo.app`, signs it ad hoc and
installs it to `~/Applications`. Open it from there; it lives in the menu bar
(no Dock icon). *Open at Login* is in the settings menu at the bottom right.

## Connecting LG ThinQ

1. Sign in at [connect-pat.lgthinq.com](https://connect-pat.lgthinq.com).
2. Add a new token with **view devices**, **view device status** and
   **device control** permissions.
3. Open Domo and paste the token. It's checked against LG before it's saved.

Change it later from the settings menu → **Change Token…**.

The region is currently fixed to Turkey (`x-country: TR`, EIC endpoint); see
`ThinQClient.swift` to change it.

## Privacy

- The token is stored only on your Mac, in `~/.config/lg-thinq/token`,
  readable by your user alone.
- Domo talks to LG's API and nothing else. No analytics, no accounts.

## Project layout

```
Sources/Domo/
  App/                 App entry point, menu bar label, snapshot tooling
  Shared/              Theme, reusable controls (tiles, toggles, slider), JSON
  Accessories/
    AirConditioner/    LG ThinQ client, state store, panel, token screen
Resources/             Images bundled into the app
```

Each accessory keeps its client, its state and its views in its own folder,
so adding one (say, `Accessories/CatFeeder/`) doesn't touch the others.

### Previewing without the menu bar

```bash
~/Applications/Domo.app/Contents/MacOS/Domo --snapshot panel.png --swiftui
```

Renders the panel with demo data and quits. Add `--off` for the powered-off
state, `--live` for your real unit, or `--setup` for the token screen.

## Credits

- Air conditioner control uses LG's official
  [ThinQ Connect API](https://smartsolution.developer.lge.com/en/apiManage/thinq_connect);
  request headers follow LG's
  [`thinqconnect`](https://github.com/thinq-connect/pythinqconnect) SDK (Apache-2.0).
- The air conditioner image is LG's product photo of the AC18BH, from
  [lg.com](https://www.lg.com/tr/klima/split-klima/ac18bh/). © LG Electronics.

Domo is a personal project and isn't affiliated with or endorsed by LG
Electronics. LG and ThinQ are trademarks of LG Electronics.
