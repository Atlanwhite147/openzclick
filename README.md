<div align="center">

# openzclick

**Use your indoor cycling controller buttons with any training app.**<br>
Runs on Windows, today, with MyWhoosh: the gradient goes to the trainer, the
buttons change the gear, the shift reaches the game.

</div>

![Zwift Click to the bridge over Bluetooth, the bridge to the training application over the local network](docs/readme-flow.svg)

A controller bought for one application usually stops working as soon as you change application. openzclick reads it over Bluetooth, turns button presses into gear changes, and publishes them on the local network with an open protocol, so the same buttons drive every application that speaks it.

**No account, no subscription, no cable, no driver, no telemetry.** One Dart codebase for Android, iOS, Windows, macOS and the browser.

## Prior art

This is not the first bridge, and the ones that came before are worth your time:

| Project | Licence | What it already covers |
|---|---|---|
| [QZ / qdomyos-zwift](https://github.com/cagnulein/qdomyos-zwift) | GPL-3.0 | The most complete of the four: Click, Click v2, Play and Ride, a long list of trainers, on Android and iOS |
| [BikeControl](https://github.com/OpenBikeControl/bikecontrol) | Non-Commercial after the `gpl3` tag, GPL-3.0 before it | The reference application for the OpenBikeControl protocol this project speaks |
| [zwiftboard](https://github.com/thomaschampagne/zwiftboard) | MIT | Presents a Click v2 as a Bluetooth keyboard, in one small Go binary |
| KSETT | closed, freemium | Gear shifting from a Click, with a second device in the middle |

The difference claimed here is deliberately narrow: **MIT**, so a host application can
embed it where the GPL would follow; no account; it runs on the machine that runs the
training application (Windows and Linux today, macOS for the controller and the gears,
not yet for the keystrokes) instead of requiring a phone; and it publishes the
OpenBikeControl protocol on the network rather than only synthesising keystrokes.

Where those differences do not matter, use QZ. It is older, it is more complete, and
it knows hardware this project has never seen. Fifteen other projects solve neighbouring
problems; [docs/prior-art.md](docs/prior-art.md) lists them with their licence.

## Measured on real hardware

Captured from a Click v2 (firmware `1.1.0`) over WinRT and asserted by a test:

![The five buttons of a Click v2 pod and the bit each one clears](docs/buttons.svg)

<details>
<summary><b>The three things that cost an evening each</b></summary>

<br>

1. **A UUID is one identifier written three ways.** Windows reports Bluetooth SIG services short: the vendor service comes back as `fc82` where the specification says `0000fc82-0000-1000-8000-00805f9b34fb`. Compare the canonical form, never the raw strings, or the service is present and never found.
2. **A connection is not a service table.** The first discovery right after a connection can return without the vendor service. Retry it before concluding that a channel is missing.
3. **An echo is not an answer.** The encrypted handshake is answered either with the device public key or with a bare `RideOn` echo and then silence. A Click v2 does the second, and the plain handshake has to go out anyway, because that is what makes it stream its buttons. The decision rests on the derived session, not on having received bytes.

The controller report lives in [#3](https://github.com/Atlanwhite147/openzclick/issues/3), with the address, the GATT tree and the raw frames.

</details>

## What works, where

| Capability | Windows | Linux | macOS | Android | iOS | Browser |
|---|:--:|:--:|:--:|:--:|:--:|:--:|
| Pair the controller, gears, left and right | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ Chrome, Edge |
| Belongs to you, no account | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| mDNS announcement + TCP server | ✅ | ✅ | ✅ | ✅ | ⚠️ needs Apple's entitlement | ⚠️ Isolated Web App only |
| Drive the bridge from a phone | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ console over WebSocket |
| Keyboard injection (no protocol support) | ✅ `SendInput` | ✅ X11 | ❌ | — | — | ❌ |
| Tap injection (on-screen controls) | ❌ | ❌ | ❌ | ✅ accessibility service | ❌ | ❌ |
| Become the trainer (FTMS peripheral) | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ |

✅ verified · ⚠️ works with a platform constraint · ❌ not implemented, open to a contributor

The macOS missing piece is one file, next to the Linux and Windows ones that already
work: [macOS `CGEventPost`](https://github.com/Atlanwhite147/openzclick/issues/2).

## Features

| | |
|---|---|
| **Gears from a controller** | single tap shifts up or down, from a gear profile (12-speed road, 8-speed flat, 24-speed hill) |
| **Five buttons decoded** | `+` and `B` shift, `Y`, `Z` and `A` are measured, named and asserted inert |
| **Left and right, on demand** | not bound to a gesture: the pod's double tap is off by default, because two quick presses for two gears were read as one direction. A **Send a direction** button in **Network** sends the steer frame |
| **Sessions, encrypted when offered** | ECDH P-256 handshake, HKDF-SHA256 derivation, AES-CCM frames, with a plain fallback the hardware actually needs |
| **Open publication** | mDNS/DNS-SD announcement plus a TCP server, both in pure Dart, identical on every platform |
| **Tap fallback** | for applications that never speak the protocol, an Android accessibility service taps their own on-screen controls |
| **Keyboard fallback** | on Linux and Windows, button presses become real key presses |
| **Works without hardware** | 630 tests without a radio; a command line probe checks the network link |
| **Settings that survive a restart** | gear profile, current gear, tap positions, keys and publishers resume where you left them |
| **Honest diagnostics** | live controller state, battery level, the raw frames, inside the application |

FTMS is decoded and encoded in pure Dart: the bridge can drive a real trainer. Presenting
itself to an application as a trainer is not written yet (see *Becoming the trainer*).

## Download

| Platform | File | Notes |
|---|---|---|
| Web | [atlanwhite147.github.io/openzclick](https://atlanwhite147.github.io/openzclick/) | nothing to install: Chrome or Edge, the controller pairs over Web Bluetooth. MyWhoosh cannot find a plain page, see below |
| Windows | [`openzclick-setup.exe`](https://github.com/Atlanwhite147/openzclick/releases/download/latest/openzclick-setup.exe) | installs for your user alone, no administrator prompt, shortcut in the Start menu. Windows may warn once about an unknown publisher: *More info*, then *Run anyway* |
| Windows, portable | [`openzclick-windows-x64.zip`](https://github.com/Atlanwhite147/openzclick/releases/download/latest/openzclick-windows-x64.zip) | unzip anywhere, double click `openzclick.exe`; nothing is registered |
| Android | [`app-release.apk`](https://github.com/Atlanwhite147/openzclick/releases/download/latest/app-release.apk) | open the file on the phone and accept *install from this source*; updates install over the previous version |
| macOS | [`openzclick-macos.zip`](https://github.com/Atlanwhite147/openzclick/releases/download/latest/openzclick-macos.zip) | unzip, drag `openzclick.app` into *Applications*. Unsigned: the first launch is refused, so open *System Settings › Privacy & Security*, scroll down and press **Open Anyway**. Controller, gears, network and console work; keyboard injection is not implemented on macOS |
| iOS | [`openzclick-unsigned.ipa`](https://github.com/Atlanwhite147/openzclick/releases/download/latest/openzclick-unsigned.ipa) | needs a computer: sign with Sideloadly or AltStore, 7 days with a free Apple ID |

Only macOS is built automatically, along with the page on GitHub Pages. The other files are built on request and stay on the release until their own workflow runs again:

```bash
gh workflow run "Windows build" -R Atlanwhite147/openzclick --ref main
gh workflow run "Android build" -R Atlanwhite147/openzclick --ref main
gh workflow run "iOS build"     -R Atlanwhite147/openzclick --ref main
gh workflow run "Web build"     -R Atlanwhite147/openzclick --ref main
gh workflow run "Web bundle"    -R Atlanwhite147/openzclick --ref main   # the Isolated Web App
```

The Android package is signed with the repository community key (`app/android/keystore/openzclick-test.jks`, password `openzclick`), which is public by design and must never be used for a store release.

## Ride with MyWhoosh in four steps

You need no account, no cable and no driver. Everything is on the [releases page](https://github.com/Atlanwhite147/openzclick/releases/latest).

1. **Start the application.** On Windows, run `openzclick-setup.exe` and open the shortcut it leaves in the Start menu; on Android, install the APK. The application runs on the machine with MyWhoosh, and the phone only drives it.
2. **Tap *Start* on the first screen.** It listens for MyWhoosh, and says whether it is announced on your network.
3. **In MyWhoosh, open the device connection screen and tap the OpenBikeControl icon, top right.** Answer **Yes** to the confirmation. The icon turns blue.
4. **Ride.** Your buttons shift. The application shows the client count going to 1, so you know MyWhoosh really attached.

Before you clip in, the **Gears** tab has *Shift up* and *Shift down* buttons that send exactly what the controller sends. If those change the gear in MyWhoosh, the link works and only the controller pairing is left.

### If MyWhoosh does not find it

| Symptom | Cause and fix |
|---|---|
| Nothing appears in MyWhoosh | the two are not on the same Wi-Fi network, or MyWhoosh runs on Android, which does not accept this connection over Wi-Fi |
| Windows finds nothing | MyWhoosh needs Bonjour on Windows (installed with iTunes, or *Bonjour Print Services*) |
| A firewall popup appeared | allow the application on private networks; without it the port stays closed |
| MyWhoosh attached but buttons do nothing | the controller is not paired: open **Controllers** and scan; the page says *Nothing answered* when the controller was asleep |
| The controller connects then drops after a minute | either a Click v2 that wants one pairing in the Zwift application (leave it open about three minutes), or a pod that heard no write — the bridge now writes a keepalive every three seconds, so if the drop is still there, it is the first |
| Something is wrong but you cannot say what | **Controllers**, then *Copy device report*: firmware, GATT tree and the last frames travel with it |
| The gear changes here but not in MyWhoosh | MyWhoosh has paired the trainer itself. Let MyWhoosh own the trainer rather than the bridge |

### From a phone, with nothing installed on the phone

A phone cannot be the bridge MyWhoosh discovers, because a normal web page may not open a server. It can drive one: run the application on the computer where MyWhoosh runs, tap *Start*, and scan the QR code in **Network**. The phone opens the console the bridge serves itself, at `http://<computer-ip>:47124`.

The address is plain `http` on purpose: a hosted page is `https://`, and browsers refuse to open a `ws://` socket from one. `docs/console.md` explains it.

Chrome alone can also install the page as a signed bundle (*Isolated Web App*), which is allowed a server; the page then announces itself and MyWhoosh finds it directly. `docs/browser-bridge.md` has the commands.

## For developers

```bash
git clone https://github.com/Atlanwhite147/openzclick.git
cd openzclick

# protocol and transports
cd core && dart pub get && dart test
cd ../transports && dart pub get && dart test

# application
cd ../app && flutter pub get
flutter run -d linux      # or windows, macos, android, ios, chrome
```

Requirements: Flutter stable (Dart 3.13 or newer). No Android SDK or Xcode needed for the protocol work.

## Architecture

<div align="center">

![Architecture](docs/architecture.svg)

</div>

```
openzclick/
├─ core/          # pure Dart, no I/O: codec, session, gear engine, mapping, gestures
├─ transports/    # dart:io: mDNS responder, TCP server, Bluetooth/injection/proxy interfaces
├─ app/           # Flutter shell: pairing, gears, publishing, diagnostics; android, ios, windows, macos, web
├─ docs/          # specification, architecture notes, diagrams
└─ CONTRACTS.md   # interface signatures between the modules
```

Three rules keep the code portable:

1. **The core never performs I/O.** Everything can be tested without Bluetooth or a network.
2. **One output, one transport.** Implementations are wired at runtime, never selected by platform conditionals.
3. **No brand logic in the core.** Devices are described by declarative definition files.

## On iPhone today

| | |
|---|---|
| Pairing the controller, gears, left and right, diagnostics | works |
| Tap injection into another application | impossible: iOS exposes no equivalent of the Android accessibility service |
| mDNS announcement | blocked until Apple grants the multicast entitlement (`docs/ios-multicast.md`) |
| TCP server on the local network | works, after the local network permission prompt |

When it cannot announce itself, the bridge displays the address to type into the application (`192.168.1.24:47123`). Applications that only discover services need the entitlement, or a bridge running on the machine where they run.

## In a browser

The same code runs in a tab, with nothing to install: the published page, or `flutter run -d chrome` from a checkout.

| Capability | In a browser |
|---|---|
| Pairing the controller, gears, left and right, diagnostics | works, through Web Bluetooth (Chrome, Edge, Chrome for Android; Safari and Firefox expose no Web Bluetooth) |
| Driving a bridge running on the local network | works: the page is the console of the bridge, over a WebSocket, and a QR code on the bridge opens it already connected (`docs/console.md`) |
| mDNS announcement, TCP server | works when the page is an **Isolated Web App**: Chrome then grants Direct Sockets, and the page becomes the bridge itself (`docs/browser-bridge.md`) |
| Tap or keyboard injection | impossible: a page cannot synthesise input for another application |
| Becoming the trainer | impossible: browsers only offer the central role of Bluetooth, never the peripheral one |

Web Bluetooth is only exposed to a secure context, so the page must be served over HTTPS or from `localhost`.

### The page as the bridge

An Isolated Web App is a signed bundle Chrome installs; it is the only context where a page is allowed a TCP server. There the page announces `_openbikecontrol._tcp` over mDNS and serves the protocol on 47123, so a training application discovers it as it discovers the desktop build. Verified on Chrome 145: an announcement left the page, a client connected, and a shift arrived as button `0x01` pressed then released.

The two limits are the platform's: a page may send to a multicast group but not bind to it, so queries are never answered and the announcement is repeated every two seconds; and nothing on iOS or Android grants Direct Sockets, so on a phone the page stays a console.

## When the application only accepts taps

Some applications expose no protocol and no keyboard shortcut: the only way to change gear is to press their on-screen button. The bridge then turns an action into a tap at a position you configure once, expressed in percentages so it survives a change of screen.

1. Install the accessibility service from **Network → Open accessibility settings** (Android only, once).
2. Enable **Tap the application controls**, then set the position of each control.
3. Press a button on the controller, or use **Send a direction** to check the calibration.

Verified on Android 13: a request is dispatched as a real touch (`tap at 182,603 accepted=true` in the log). Android only allows this through an accessibility service; no root, no shell command, and the service never reads the screen.

## Injection, when nothing else works

| Host | Keyboard | Pointer | State |
|---|---|---|---|
| Linux, X11 | XTest | XTest | implemented and verified |
| Android | not allowed by the platform | accessibility service | implemented and verified |
| Windows | `SendInput` | `SendInput` | implemented, measured against a window that does not own the application |
| macOS | - | - | open to a contributor |
| iOS | - | - | impossible, the platform forbids synthetic input |

The injection layer is measured against a window that does not own the application;
whether MyWhoosh, Zwift or Rouvy read the events is unverified. Default bindings,
the Windows port and the caveats: [docs/injection.md](docs/injection.md).

## Becoming the trainer

Two applications never share a trainer, and iOS forbids synthetic input. So the bridge can take the machine, apply the resistance of the selected gear, and present itself to the training application as an ordinary FTMS trainer.

The protocol layer is implemented and tested in pure Dart; the Bluetooth halves are the remaining work.

```
grade 4 %, gear 6   -> resistance 36.7 %  -> 07 25 written on the real trainer
shift up, gear 9    -> resistance 62.6 %  -> 07 3f
ergometer 240 W     -> forwarded unchanged -> 08 f0 00
```

Details and calibration caveats: [docs/trainer-proxy.md](docs/trainer-proxy.md).

## How the link works

**Controller side.** Scan for the vendor service, subscribe to the asynchronous channel for buttons and to the synchronous reply channel, write the handshake to the write-only one, where the three traps above are handled (`docs/controllers.md`). Button notifications are protobuf: type `23`, field 1 holding a 32-bit mask where a press clears its own bit.

**Training application side.** The bridge announces `openzclick._openbikecontrol._tcp.local` with the TXT record of the specification (`version`, `id`, `name`, `service-uuids`, `manufacturer`, `model`). A client connects over TCP, sends an application info frame, and receives one frame per action, with no length field on the wire: `01 01 01` for shift up pressed, `01 18 01` for a steer left. One write carries one message, which is what delimits frames in a protocol that has no length byte.

Check the publication without a phone:

```bash
cd transports && dart run tool/net_probe.dart 47123
```

Protocol facts are implemented in Dart from public interoperability notes; no third-party code is copied. Cryptographic primitives come from `pointycastle`.

## Status

| Module | State | Tests |
|---|---|---|
| `core/` | protocol, session, link supervision, gear engine, wheel-size scaling, mapping, gestures | 320 |
| `transports/` | mDNS responder, TCP server, console relay and the page it serves, FTMS trainer proxy, Wahoo wheel commands, Cycling Power; Bluetooth stays an interface | 137 |
| `app/` | pairing, gears, parked-gear setup, publishing, console, injection, device report, diagnostics on Android, iOS, Windows, macOS and the browser | 174 |

**Verified on Windows 11 with a Click v2:** scan, connect, plain session, five buttons identified one at a time, `+` and `B` shifting the gear end to end, and a training client on another machine reading the frames over the tailnet.

**Verified on Windows 11, the injection route:** the gear went 10 → 11 → 10 from a console on another machine, and a window that did not own the application received `i` then `k`.

**Verified on Windows 11, the console route:** the address shown for a phone, and encoded in the QR code, is the Wi-Fi adapter (`192.168.1.18`) rather than the Tailscale one (`100.76.28.61`), and that console page drove the bridge end to end from another computer.

**Verified on Android 13:** installation, first frame, gear changes, direction choices sent from **Network**, tap injection through the accessibility service, announcement visible from the local network and TCP handshake with a client.

**Verified in Chrome:** the four sections render, the gear engine runs, a click on **Shift up** reaches a headless bridge, and a gear changed on the bridge side moves the page without any click.

What is not verified is the Bluetooth radio on macOS and on iOS against real hardware: [CONTRIBUTING.md](CONTRIBUTING.md) explains how to report a controller that does not pair.

## Roadmap

- [x] binary protocol, encrypted sessions, gear engine
- [x] network publication in the shared core
- [x] persisted settings and gear profile selection
- [x] continuous Android and iOS builds
- [x] a Click v2 scanned, connected and shifting on Windows, measured frame by frame
- [x] local injection transport, with an Android accessibility service driver
- [x] Windows keyboard injection through `SendInput`, measured against a window that did not own the application
- [ ] macOS keyboard injection
- [ ] the left pod of the pair, button by button
- [ ] Bluetooth peripheral backend (advertise the bridge as a trainer)
- [ ] iPhone multicast entitlement
- [ ] browser, next: drive the trainer directly over FTMS, for the applications that do not handle shifting

The detailed roadmap, including what is open to a first contribution, lives in [docs/ROADMAP.md](docs/ROADMAP.md). The specification is in [docs/spec.md](docs/spec.md).

## Screens

<div align="center">

| First start | Gears | Controllers | Start |
|---|---|---|---|
| ![First start](docs/screenshots/onboarding.png) | ![Gears](docs/screenshots/gears.png) | ![Controllers](docs/screenshots/controllers.png) | ![Start](docs/screenshots/start.png) |

</div>

Captured from the web build of the current version, at 1280 by 800. Four screens,
one theme, no platform-specific furniture. The **Gears** shot leads with the gear in
tabular figures and draws the cassette as a ladder; the two shift paddles carry the
pod's own colours, orange for the harder gear and rose for the easier one.

The **Network** tab is not in the table because a browser cannot listen on the
network: a page shows the limitation instead. On a computer or an Android phone the
same tab carries the switch, the announced name, **Send a direction** and the QR code
a phone scans to become the console — see [docs/android.md](docs/android.md).

## Contributing

Issues and pull requests are welcome. Read [CONTRIBUTING.md](CONTRIBUTING.md) first.

## License

MIT, see [LICENSE](LICENSE).
