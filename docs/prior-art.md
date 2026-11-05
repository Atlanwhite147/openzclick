# The landscape

Fifteen projects solve neighbouring problems, and each one answers a question
this project had to answer alone. They are listed here with the licence and the
platform read from the repository itself, not from memory — a search on GitHub
for `zwift click`, `zwift play`, `click v2` and `openbikecontrol`, filtered by hand.

Three approaches, and they are not equivalent:

1. **Turn the controller into a keyboard.** Read the Click over BLE, inject
   keystrokes into the application that reads them. Simple, works with every
   application, but needs synthetic input and a foreground window.
2. **Speak OpenBikeControl over the network.** The controller becomes a service
   the application dials. No synthetic input, no focus problem, but only
   applications that implement the protocol.
3. **Become a BLE peripheral.** An ESP32 presents itself as a real Bluetooth
   keyboard, so the host needs no software at all. Costs a €10 board and can
   reach a tablet or an Apple TV, where no helper can run.

## Keyboard-mapping bridges

| Project | Licence | Platform | What it is |
|---|---|---|---|
| [zwiftboard](https://github.com/thomaschampagne/zwiftboard) | MIT | Windows | Click v2 → keys, per-application profiles, brings the target window forward before each key. The source of this project's keepalive and activation sequence |
| [swift-click](https://github.com/benoitzelsmann/swift-click) | none declared | Windows | Right pod → MyWhoosh, media keys, named mouse targets, signed installer |
| [clickbridge](https://github.com/jasasonc/clickbridge) | GPL-3.0 | Linux (BlueZ) | Both pods → keys, tested on full rides with MyWhoosh under Wine/Proton. One press, one key: a held button does not repeat |
| [ClickShift](https://github.com/prioneto/ClickShift) | MIT | macOS | Menu-bar app, right pod → MyWhoosh, only types when the ride app owns the focus, 1–3 shifts per press |
| [click2whoosh](https://github.com/NicolaM96/click2whoosh) | NOASSERTION | macOS | Both pods, gears **and steering over OpenBikeControl**, keyboard as a fallback, every button configurable |
| [zwoosh](https://github.com/amith2368/zwoosh) | MIT | Windows, macOS, Linux | Both pods, handshake, configurable key mapping |
| [OpenBridge](https://github.com/cmdl-dev/Zwift-Click-V2-Universal-PC-Controller) | MIT | Windows | Universal BLE controller → key mapper, Zwift Ride's two radios merged into one device |
| [click2key](https://github.com/skeffling/click2key) | none declared | — | Click v2 presses → keyboard shortcuts |

## Network-protocol bridges

| Project | Licence | Platform | What it is |
|---|---|---|---|
| [qdomyos-zwift (QZ)](https://github.com/cagnulein/qdomyos-zwift) | GPL-3.0 | Android, iOS | The largest of them all: Click, Click v2, Play and Ride, a long list of trainers, an application of its own |
| [mywhoosh-shifter](https://github.com/hannahinthere/mywhoosh-shifter) | MIT | Android | A phone as a virtual shifter, OpenBikeControl over mDNS + TCP, volume keys as buttons |
| [kickr-bike-pro-open-bike-control](https://github.com/jessicah/kickr-bike-pro-open-bike-control) | MIT | Windows (C#) | KICKR Bike Pro shifters → OpenBikeControl, for applications that do not know the bike |
| [MyFreeBikeControlApp](https://github.com/edperch/MyFreeBikeControlApp) | none declared | Windows (C#) | A game controller → OpenBikeControl |

## Hardware peripherals

| Project | Licence | Platform | What it is |
|---|---|---|---|
| [RideToWooshHID](https://github.com/TheInGoF/RideToWoosh) | GPL-3.0 | ESP32-S3 | Zwift Ride handlebar → configurable BLE keyboard, works on PC, Mac, iPad and Apple TV with no helper |
| [Zword](https://github.com/Fuenfachsen/Zword_ZwiftRide-to-BLE-Keyboard) | GPL-3.0 | ESP32 | Same idea for the Zwift Ride controller |
| [zwift-ride-hid-bridge](https://github.com/brad-richardson/zwift-ride-hid-bridge) | GPL-3.0 | ESPHome | Zwift Ride → BLE HID keyboard |
| [kickr-zwift-bridge](https://github.com/jespern/kickr-zwift-bridge) | none declared | ESP32 | The other direction: KICKR Bike shifter units, presented as a Zwift Click v2 |

## The protocol and the applications

| Resource | Licence | What it is |
|---|---|---|
| [openbikecontrol-protocol](https://github.com/OpenBikeControl/openbikecontrol-protocol) | MIT | The specification this project implements |
| [BikeControl](https://github.com/OpenBikeControl/bikecontrol) | GPL-3.0 before the `gpl3` tag, Non-Commercial after | The reference application for that specification |
| KSETT | closed, freemium | Gear shifting from a Click, with a second device in the middle |

## What this changes here

- **Two projects independently confirm the shift direction**: `zwiftboard` and
  `ClickShift` both send `K` for a harder gear and `I` for an easier one in
  MyWhoosh. This project's defaults were the other way round until that was read.
- **MyWhoosh speaks OpenBikeControl natively.** `click2whoosh` and
  `mywhoosh-shifter` both rely on it, over mDNS and TCP, and neither needs
  synthetic input for gears. So the keyboard route is a fallback for
  applications that implement no protocol — not the primary path for MyWhoosh.
- **A held button is not universally wanted.** `clickbridge` states the opposite
  choice in its first paragraph — one press, one key, no repeat — which is a
  reason to keep the tap behaviour rather than a hold.
- **A €10 board beats a helper process where no helper can run**: `RideToWooshHID`
  reaches an iPad or an Apple TV, which no desktop-side injection can.

## Excluded on purpose

Four repositories rank high in those searches and are not software: pages with a
generic HTML body, a "2026 guide" title, no source and a few dozen stars. They are
search noise around *virtual shifting*, not implementations, and none of them is
listed above.
