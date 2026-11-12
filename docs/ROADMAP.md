# Roadmap

Open source, MIT, no paid tier. The project stays useful only if it runs where people actually ride, so the order below follows what blocks a rider today.

## Done

- Binary protocol of the controller, encrypted sessions, gear engine, gestures.
- Network publication with mDNS and TCP, in the shared core.
- Android tap injection through an accessibility service.
- Linux keyboard and pointer injection through X11 and XTest.
- Persisted settings, gear profile selection, continuous Android and iOS builds.
- Controller link supervision: plain-handshake fallback, silence detection and
  automatic reconnection, with the locked-controller case named instead of
  hanging (`docs/controllers.md`).
- A Click v2 held open past the minute it used to die at, without the Zwift
  application: `FF 04 00` finishes the opening, and a `0x18` reset every 50 s —
  while the link still answers — makes the pod reboot, re-advertise and reopen its
  session in about two seconds. Verified on the right pod in MyWhoosh on
  2026-11-12, including repeated shifts from quick presses
  (`docs/controllers.md`, `docs/INTEGRATION-PLAN.md`).
- The pod in hand is named: both pods announce themselves as `Zwift Click`, and
  the manufacturer data says which one it is, so a pairing list can no longer
  quietly pair the left one — the only one Zwift locks.
- The "needs unlock" hint: a controller that stays silent says what to do
  instead of showing a link that looks alive.
- Browser build: one codebase, a capability layer that names what a page cannot
  do, Web Bluetooth pairing through the device chooser, and a publication card
  that explains instead of pretending.
- Windows and web builds in CI, next to Android and iOS.
- Console relay: a page drives a bridge over a WebSocket, from the Target screen,
  with a code the bridge displays. Verified in Chrome: a button of the page
  reaches the bridge, and a gear changed on the bridge moves the page.
- Windows keyboard and pointer injection through `SendInput`, with the buffer
  layout tested in plain Dart and a zero return from the call raised as a
  failure instead of counted as a gear change (`docs/injection.md`).
- The console route measured end to end on Windows: a console on another machine
  moved the gear and a focused window that did not own the application received
  the injected keys (`docs/injection.md`).
- A device report a rider copies in one tap — version, host, device identity,
  Device Information strings, GATT tree and the last 40 frames with direction
  and timing — because no development machine here has a Bluetooth radio.
- The bridge serves its own console over `http` on its relay port, so a phone can
  reach it: a hosted page is `https://` and a browser will not open a `ws://`
  socket from one.
- The bridge can be the page itself: Direct Sockets in an installed web app give
  a real mDNS announcement (341 bytes) and a real TCP server on port 47123,
  verified end to end in Chrome 145.
- Trainer gearing by wheel size: one command per gear, the parked gear of the
  bike asked once and stored, the wheel window a riding application may impose
  honoured, and Cycling Power published next to FTMS (`docs/trainer-proxy.md`).

## Next, in order

### 1. What the browser cannot do, and the three ways around it
A page in a tab cannot open a listening socket, announce a service or act as a
Bluetooth peripheral, so a plain page can never be the bridge a training
application discovers. Two routes are done: the page is the console of a bridge on
the local network, over a WebSocket (`docs/console.md`), and the page is the bridge
itself when Chrome installs it as an Isolated Web App and grants Direct Sockets
(`docs/browser-bridge.md`, verified end to end on Chrome 145). What remains:

- drive the smart trainer directly over FTMS with Web Bluetooth: the gears become
  wheel sizes, no bridge at all, which covers applications that do not handle
  shifting. The arithmetic and the frames are already written
  (`docs/trainer-proxy.md`); what remains is a Web Bluetooth link to the machine.

### 2. What the training applications do with injected events
`SendInput` itself is measured: on a Windows PC, a console on another machine
moved the gear and a window that did not own the application received `i` and
`k` (`docs/injection.md`). What no machine here can answer is the next layer —
does a shift reach MyWhoosh, Zwift and Rouvy? Each application decides at which
layer it reads the keyboard, and an event that is inserted but never read moves
nothing, silently. If one of them ignores injected events (Raw Input,
DirectInput, exclusive fullscreen), `docs/injection.md` records the alternative —
a virtual gamepad through ViGEm — and the trade it costs. Two smaller
measurements belong here as well: the same chain with both applications at
normal integrity, and the refusal UIPI produces when the application runs
elevated and openzclick does not.

### 3. macOS keyboard injection
`CGEventPost`, with the accessibility permission requested from the user.

### 4. Trainer proxy
The bridge connects to the smart trainer, applies the resistance of the selected gear, and presents itself to the training application as an ordinary trainer. This is the only path that works on iPhone, because iOS allows a Bluetooth peripheral without any Apple entitlement.

State: the FTMS codec, the virtual trainer logic, the wheel-size command and the Cycling Power service are implemented and tested (`docs/trainer-proxy.md`), with a scripted ride that runs without hardware. What remains is the Bluetooth part: an FTMS client towards the real trainer, a GATT server that exposes the services to the application, and the control loop between them.

### 5. iPhone multicast entitlement
Not code: a request to Apple, with the paperwork written in `docs/ios-multicast.md`. Until it is granted, iOS listens but cannot announce.

## Planned from the survey of neighbouring projects

The six phases, with what each one takes from which project and how it is verified,
live in [`INTEGRATION-PLAN.md`](INTEGRATION-PLAN.md): per-application key profiles,
both pods and the arrows they own, gestures, battery and sleep, macOS injection,
then the spare buttons.

## Small, well bounded, ideal for a first contribution

- Battery level and firmware shown on the controller screen.
- Exportable diagnostic log, for bug reports.
- Editing key bindings and tap positions from the interface.
- Translations: the interface is English only, the gear profiles labels are French.
- A second gear profile file format, so people can describe their own transmission.

## How to claim something

Open an issue with the item name, say what you plan to do, and wait for a short answer before writing code. The module boundaries in `docs/ARCHITECTURE.md` explain where each piece belongs: the core stays free of I/O, a platform capability is a `KeyInjector` or a `Transport`.
