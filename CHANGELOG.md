# Changelog

All notable changes to this project are documented here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project adheres to [Semantic Versioning](https://semver.org/).

## [0.3.0] - 2026-10-30

### Added
- Settings survive a restart: gear profile, current gear, tap positions and whether the publishers were running.
- Gear profile selector in the trainer screen, swapping the transmission without losing the position in the block.
- Entitlement template and procedure for multicast on iOS (`docs/ios-multicast.md`).

### Changed
- The trainer screen is more compact, so every control fits on a phone screen.

## [Unreleased]

### Added
- **Keys go to the window the rider means.** A synthetic keystroke lands in whatever window owns the focus, and clicking this application to press a shift hands the focus to it, which is why the phone console existed at all. The Network tab now takes a fragment of the training application's window title: when it is set, every keypress restores and raises that window first, and a missing window means the key is **not** sent rather than typed blind (`app/lib/net/window_focus.dart`, `windows_focus.dart`). Windows only, title only, and a `SetForegroundWindow` Windows refuses is reported instead of ignored. The idea is `zwiftboard`'s (MIT).
- **Wheel size instead of resistance percentage.** A trainer works out its brake force from the distance one pedal stroke covers, so the bridge now sends one wheel size per gear and leaves the terrain exactly as the riding application sent it. This removes the `trainerMaxWatts` calibration, which was a property of the machine and of the speed, and stops the bridge fighting the grade the application imposes. `core/lib/src/shifting/parked_gear.dart` holds the arithmetic, `transports/lib/src/trainer/wahoo_wheel_circumference.dart` the frame (command `0x48`, tenths of a millimetre, little endian).
- **The parked gear, asked once.** What the rider feels is the gear ratio of the bike's chain times the wheel size the trainer works from, and the bridge only controls the second half. The Gears screen now asks where the chain sits and stores the answer, because a ladder built on a wrong assumption is 89 % too hard from a 50/11 parking spot with no symptom beyond tired legs: the step sizes stay right and only the whole ladder moves. A *Quietest* button picks the lowest ratio that still keeps every gear reachable, which is also what keeps the flywheel slow and the room silent.
- **Cycling Power (0x1818)**, so applications that look for a plain power meter instead of an FTMS trainer show watts and cadence rather than `0 W` and `0 rpm`. Power and crank revolution counters come from one clock, with the fraction of a revolution carried between frames and the 16-bit counters wrapping as the specification allows.
- A trainer command is applied one gear at a time, with the acknowledgement awaited between two frames. A KICKR takes 59 to 238 ms to acknowledge (138 ms on average), so a second shift in flight used to lose one of the two frames and leave the rider in a gear the screen did not show. A gear asked for while another is being applied is dropped rather than queued.
- The start screen says where the downloadable application comes from, with the address shown and copyable, instead of asking a novice to "install openzclick" without saying that a file exists.
- **A device report, copied in one tap.** No machine used to write this project has a Bluetooth radio, so every rule runs against a fake controller, and the gap can only be closed from the other side. *Controllers*, then *Copy device report*, yields the application version (checked against `pubspec.yaml` by a test), the host, the device name and identifier, the five strings of the Device Information service, the whole GATT tree with its properties, and the last 40 frames with their direction and timing relative to the moment the link was made. Frames are recorded **before** they are parsed, so a frame the decoder does not recognise is still in the report — that is usually the finding. Identifiers are reduced to canonical form because WinRT reports a vendor service as `fc82` where Android returns the 128-bit form. `app/lib/ble/device_report.dart`.
- **Windows keyboard and pointer injection** through `SendInput`, so the platform where most riders are gets the same synthetic input Linux already had. The four traps are handled and named in the code: `cbSize` is `sizeof(INPUT)` (40 bytes) and not `sizeof(KEYBDINPUT)` (24); a press and a release are two separate calls 12 ms apart; `SendInput` returns how many events it inserted and **zero is a failure**, because UIPI refuses to inject into a window of higher integrity and `GetLastError` does not name that; and a key name the table does not know is refused rather than guessed. The buffer layout and the key table live in plain Dart, tested without Windows. `app/lib/net/windows_injection.dart`, `docs/injection.md`.
- **The Windows injector, measured on a real machine.** It had only ever run against a buffer in plain Dart, because no machine used to write the project had a radio or a Windows desktop. A PC with Windows 11 was driven from another computer: a console connected over the network to the bridge, `shiftUp` and `shiftDown` were typed there, the gear went `10 → 11 → 10`, and a window that did **not** own the application received `i` then `k`. That is the unknown the project could not close alone: `SendInput` reaches a normal window from a process that does not have the focus. It does not establish that MyWhoosh, Zwift or Rouvy *accept* injected events, which is a different question and stays open in `docs/ROADMAP.md`; `docs/injection.md` records the protocol, the result and the one caveat worth keeping — the application ran with administrator rights, so the everyday case of both sides at normal integrity is still unmeasured.

### Fixed
- **The link is held by a write, not by the buttons.** The supervision reconnected after 45 seconds without a button frame. That is wrong twice over: coasting for a minute is normal riding, and a pod keeps its session from the host side. A Click v2 drops about 65 seconds after the **last write** it received — measured by [`zwiftboard`](https://github.com/thomaschampagne/zwiftboard) (MIT) — so the bridge now writes the plain `RideOn` every three seconds, and treats a **failed write** as the only sign that the session ended. This is very likely the real cause of the *"drops after a minute"* report, which had been blamed on the controller lock.
- **The activation is complete, not just started.** A Click v2 streams its buttons only after the whole exchange: the plain `RideOn`, then `00 08 00`, then `00 08 10`, written in that order. The bridge used to send the first frame and wait, which works until it does not.
- **`i` and `k` were the wrong way round for MyWhoosh.** `shift up` is `k` and `shift down` is `i` there, and the public shortcut tables disagree on the direction. The defaults follow the profile shipped by `zwiftboard`, written against a Click v2 and MyWhoosh.
- **The address a phone is told to type could not reach the bridge.** The console address, and the URL encoded in the QR code, came from the first non-loopback interface whose name was not on an exclusion list — compared case-sensitively. Windows names the overlay adapter `Tailscale`, so the exclusion missed it and the screen advertised the VPN address: a phone on the home Wi-Fi opened a URL that resolves nowhere, and nothing on screen said why. The choice is now a pure function in `app/lib/net/local_address.dart`: it prefers a private LAN address, refuses link-local (`169.254/16`) and carrier-grade NAT (`100.64/10`) addresses whatever the interface is called, and skips the virtual switches (Hyper-V, VMware, WSL) that enumerate first on some Windows machines. Measured on the machine that produced the bug: `192.168.1.18` is chosen over `100.76.28.61`.
- **A press sent by a connected application was decoded, counted and dropped.** `NetworkPublisher._onEvent` handled connection, disconnection and errors, but not `TransportActionReceived`; only the console relay did. An application that connected and pressed a button was counted as *1 client(s)*, its frame was decoded, the gear did not move, and no error existed anywhere — the worst shape a failure can take. A press from a peer now takes the same path as a message typed in a console, so the gear engine and the local injection both see it.
- **The phone route could never reach the bridge.** The QR code opened the hosted page, which is served over `https://`, and a browser refuses to open a `ws://` socket from an `https://` document: the mixed content rule fires before the bridge sees a byte. The code was right, the bridge was running, and the only feedback was *"the bridge refused the connection: check the address and the code"*, which sent the rider to check a code that was correct. The bridge now serves the console document itself at `GET /` on its relay port, so the page and the socket share one origin, and the QR code points at `http://<bridge>:47124/?token=...`. The document is one file with no dependency and no build step, because a phone on a home network may have no internet at all. `transports/lib/src/console_page.dart`, `docs/console.md`. The hosted page also stops offering a form that cannot work: it says that an https page may not dial a bridge, and points at the `http://` address instead of reporting a refused code.
- **A Bluetooth failure is no longer a stack trace.** Tapping *Choose a controller* on a machine without a radio produced `FlutterBluePlusException | scan | web-code: 0 | Null check operator used on a null value`. A rider can only read that as "the application is broken", and it is wrong: the machine has no radio, and no retry changes it. Failures are now mapped to a sentence with a remedy, and a page that cannot use Web Bluetooth at all (plain `http`, or a browser without the API) says so before the button is pressed instead of failing after. `app/lib/ble/controller_error.dart`.
- **The Click v2 trap was invisible where it happens.** A Click stays silent until it has been paired once in the Zwift application for about three minutes, and the pairing screen said nothing about it, so a controller that connected and then did nothing looked like a bridge fault. The screen now names it before the rider pairs, and the unlock message names the application and the duration.
- **A suggestion that did not fit the bike.** The Gears screen offered *Quietest: 34/30* before the rider had described anything, which reads as the application not knowing that a single-cog setup exists: a Zwift Cog has one cog and cannot answer it. The suggestion now appears only once a chain has been described.

### Changed
- The wheel window a riding application may impose is 1800 to 2400 mm, and a value outside it is ignored rather than adopted: no bicycle has a 1200 mm wheel, so such a value is a misreading, and keeping the previous one keeps every gear usable.
- A gear the command cannot express, or one so easy that a training application would draw a stopped rider, is reported and not sent. Clamping is never an option: it hands the rider a gear nobody asked for.
- Ergometer mode is refused rather than followed: a target power and a gear contradict each other, and the machine obeys whichever arrived last.
- `docs/trainer-proxy.md` documents both routes side by side, with the acknowledgement timings and the three rules that follow from them.
- **A first screen a novice can follow.** The application used to open on the gear display, with publication on a tab called *Target* and no word about what to do inside MyWhoosh. It now opens on a guide whose four steps match MyWhoosh's own documented gesture — start the bridge here, open MyWhoosh, tap the OpenBikeControl icon in the top right, answer *Yes* — with the two steps the application can observe ticked as they complete, and the client count confirming that MyWhoosh really attached.
- A troubleshooting section in the application, listing the obstacles riders actually meet: networks that differ, Bonjour missing on Windows, Wi-Fi control refused on MyWhoosh for Android, a firewall, a controller still locked, and a trainer that MyWhoosh has paired itself.
- The README opens on the ride rather than on the architecture: four steps, a table of symptoms, and a paragraph on installing nothing.

### Changed
- The bottom navigation read *Start*, *Gears*, *Controllers*, *Network*, *Diagnostics* instead of *Trainer*, *Controllers*, *Target*, *Diagnostics*: *Target* meant nothing to anyone who had not read the specification, and the network step is what a rider looks for, not the application's target.
- **Four tabs, and the gear screen answers one question.** The codec test bench left the navigation bar for the bottom of the Network tab: it sat beside the gear a rider presses every ride, and that alone made the application look like something to configure. The gear screen now shows a large gear number, two tall shift buttons and the riding mode, with the four settings behind one expander instead of six buttons of equal weight. The shift buttons are disabled at the ends of the ladder, because a press that does nothing reads as a broken application when the largest gear is simply already engaged.
- **The parked gear is asked once, then folded away.** The card keeps its size only while unanswered; afterwards it is a single line with a *Change* button, which puts the shift buttons back in view on a phone. Choosing the chainring alone no longer does nothing: the half answer is held until the cog completes it. The start screen opens the same question in a dialog, so a first-time rider answers it without hunting for a tab, and the browser build now says it there too, having previously never mentioned it.
- Every screen carries a *Ready* or *Not ready* badge, judged on the bridge running. The parked gear is deliberately **not** part of that verdict: on the route a rider rides today MyWhoosh does its own virtual shifting and the bridge only forwards buttons, so a rider who never answered the chain question still shifts perfectly, and a Zwift Cog user has one cog and nothing to answer. Counting it would have shown *Not ready* over a working setup. The answer to "why is nothing happening" used to live on a tab the rider had to guess.
- The chain question is offered as *optional*, with the reason in one sentence, instead of being announced as a pre-condition (*Where is your chain? (optional)*, *Optional: tell the app where your chain sits*). A red icon and a bare question read as "you cannot ride yet".
- Controller states are named in words a rider uses (*Not connected yet*, *Connected*) instead of the code's names (`idle`, `ready`), and the scan button says *Choose a controller* where the browser opens its own device picker.

### Fixed
- A press sent before the training application connected no longer leaves a permanent error on screen: the transport still reports it, the publisher treats it as a hint, and an arriving client clears whatever fault came before it.
- The Bluetooth link used the wrong channels: it subscribed to the write-only characteristic, which never notifies, and wrote the handshake to the reply channel. Buttons arrive on the asynchronous channel and the handshake answer on the synchronous one, as `docs/controllers.md` now states.
- A controller that stays silent is reported as needing one pairing in the official application instead of leaving a connection that looks alive and does nothing.
- Frames now match the OpenBikeControl specification byte for byte: the length byte this project added after the type byte is gone, so an application that implements the specification reads our messages instead of a body length mistaken for a button identifier.
- The mDNS announcement carries the TXT record the specification describes (`version`, `id`, `name`, `service-uuids`, `manufacturer`, `model`) instead of short private keys, so a conforming browser finds the bridge and its model.
- Application info frames carry their format version byte, and a frame announcing another version is rejected instead of misread.
- The stream decoder works without a length field: a buffer that decodes whole is one message, two messages coalesced in one read stay apart, and an undecodable write no longer accumulates in the buffer of a peer.

### Added
- **The page can be the bridge**: an Isolated Web App — a signed bundle Chrome installs — is granted Direct Sockets, so the page opens a TCP server on 47123 and announces `_openbikecontrol._tcp` over mDNS exactly as the desktop bridge does. A training application discovers it and receives the same frames. Reproduced on Chrome 145: an announcement of 341 bytes left the page, a client connected, a click on *Shift up* arrived as button `0x01` pressed then released. `docs/browser-bridge.md` has the build, signing and install steps, and states the two platform limits: a page may send to a multicast group but not bind to it, hence a repeated announcement instead of query answers, and mobile browsers grant no Direct Sockets at all.
- `DnsPacket` and `DnsReader` in the core: the DNS-SD wire format is written once and used by both hosts, so the native responder and the page cannot drift. Reading back a packet is what the tests of each host assert against.
- **QR code on the bridge**: the Target screen shows a code that opens the published page with the bridge address and the console code already in the URL, so a phone connects by scanning instead of typing. Typing keeps working.
- **Console relay**: the bridge opens a WebSocket next to the TCP server, so a page can drive it. The address and a four letter code are shown on the Target screen; a console that presents a wrong code is refused before the upgrade. Actions typed on the page take the same path as a controller press, and the bridge pushes its gear state back so no console drifts from the real gear. This is the route that also works on an iPhone, where no browser exposes Web Bluetooth. Details: `docs/console.md`, and `transports/tool/console_bridge.dart` to check it without a controller.
- Browser build: the application compiles and runs in Chrome and Edge, pairs the controller over Web Bluetooth (through the browser's device chooser, with the service granted as an optional one), keeps the gear engine, gestures and diagnostics, and connects to a bridge as its console from the Target screen.
- `WebPublisher` and `InjectionBackend`: the publisher and the injector are now ports, so the same widgets run on a host with `dart:io` and on a host without it, without a platform conditional inside the interface.
- Web and Windows builds in CI: the page is published to GitHub Pages (HTTPS is required for Web Bluetooth), the Windows archive joins the `latest` release.
- The "needs unlock" hint: a controller that stays silent after the handshake tells the rider to pair it once in its official application.
- `ControllerLinkWatchdog`: plain-handshake fallback after three seconds, "needs unlock" after ten seconds of silence, reconnection after forty-five seconds without a frame. Pure logic in the core, tested without a radio.
- `docs/controllers.md`: the three channels, the three behaviours a controller can have, and the documented workaround for a Click v2 that drops after a minute.
- FTMS trainer proxy: control point codec, simulation parameters, target power and resistance, Indoor Bike Data.
- Virtual trainer that turns the application's requests into resistance setpoints for the real machine, through the gear engine.
- `tool/trainer_probe.dart`, a scripted ride without hardware, and `docs/trainer-proxy.md`.

### Added
- Linux keyboard and pointer injection through X11 and XTest, verified against a live X server.
- Key bindings for desktop hosts, so the same actions reach applications that only listen to shortcuts.
- `docs/injection.md` and `docs/ROADMAP.md`, including the port contract for Windows and macOS.

### Fixed
- The X11 injector no longer fails when the display is unavailable after a first attempt.

### Added
- Stable listening port (47123) and the local address shown in the application, so a client can be configured by hand.
- iOS: local network permission description and declared Bonjour service.
- iOS: the publisher listens without announcing, since multicast needs Apple's entitlement.

### Changed
- The network publisher takes an `advertise` flag instead of always binding the mDNS socket.

### Added
- Tap injection towards applications that only accept touches, driven by an Android accessibility service, with configurable relative positions for shift up, shift down, left and right.
- Readiness check before enabling injection, so a disabled service is reported instead of silently doing nothing.
- Encrypted controller sessions: ECDH P-256 handshake, HKDF-SHA256 derivation, AES-CCM frames, plain fallback.
- Two-button gesture detector: single tap shifts, double tap chooses a direction at an intersection.
- mDNS/DNS-SD responder in pure Dart (`DartMdnsAdvertiser`), shared by every platform.
- Network panel in the application: announcement, port, connected clients, direction buttons.
- Command line probe (`transports/tool/net_probe.dart`) to check the link without hardware.
- Continuous Android and iOS builds published as release assets.

### Fixed
- The direction buttons did not reach the injector.
- Android: missing `INTERNET` permission refused every socket.
- Android: multicast traffic was filtered without a multicast lock.
- Android: every CI build was signed with a different key, which prevented updates.
- mDNS: the announced service type lacked the `.local` suffix and stayed invisible to browsers.
- mDNS: container and tunnel addresses were announced, slowing down connection attempts.
- mDNS: the socket leaked when the announcement was replaced.

### Changed
- Android packages are signed with a stable community key so updates install over the previous version.
