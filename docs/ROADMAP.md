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
- The "needs unlock" hint: a controller that stays silent says what to do
  instead of showing a link that looks alive.
- Browser build: one codebase, a capability layer that names what a page cannot
  do, Web Bluetooth pairing through the device chooser, and a publication card
  that explains instead of pretending.
- Windows and web builds in CI, next to Android and iOS.
- Console relay: a page drives a bridge over a WebSocket, from the Target screen,
  with a code the bridge displays. Verified in Chrome: a button of the page
  reaches the bridge, and a gear changed on the bridge moves the page.

## Next, in order

### 1. What the browser cannot do, and the two ways around it
A page cannot open a listening socket, announce a service or act as a Bluetooth
peripheral, so a browser can never be the bridge a training application
discovers. One route is done: the page is the console of a bridge on the local
network, over a WebSocket (`docs/console.md`). What remains:

- drive the smart trainer directly over FTMS with Web Bluetooth: the gears become
  resistance setpoints, no bridge at all, which covers applications that do not
  handle shifting.

### 2. Windows keyboard injection
`SendInput`, or the scan code path for applications that ignore synthetic keys. One file, one test, no new dependency. This is the platform where most riders are.

### 3. macOS keyboard injection
`CGEventPost`, with the accessibility permission requested from the user.

### 4. Trainer proxy
The bridge connects to the smart trainer, applies the resistance of the selected gear, and presents itself to the training application as an ordinary trainer. This is the only path that works on iPhone, because iOS allows a Bluetooth peripheral without any Apple entitlement.

State: the FTMS codec and the virtual trainer logic are implemented and tested (`docs/trainer-proxy.md`), with a scripted ride that runs without hardware. What remains is the Bluetooth part: an FTMS client towards the real trainer, a GATT server that exposes the service to the application, and the control loop between them.

### 5. iPhone multicast entitlement
Not code: a request to Apple, with the paperwork written in `docs/ios-multicast.md`. Until it is granted, iOS listens but cannot announce.

## Small, well bounded, ideal for a first contribution

- Battery level and firmware shown on the controller screen.
- Exportable diagnostic log, for bug reports.
- Editing key bindings and tap positions from the interface.
- Translations: the interface is English only, the gear profiles labels are French.
- A second gear profile file format, so people can describe their own transmission.

## How to claim something

Open an issue with the item name, say what you plan to do, and wait for a short answer before writing code. The module boundaries in `docs/ARCHITECTURE.md` explain where each piece belongs: the core stays free of I/O, a platform capability is a `KeyInjector` or a `Transport`.
