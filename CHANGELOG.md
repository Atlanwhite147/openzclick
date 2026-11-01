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

### Fixed
- The Bluetooth link used the wrong channels: it subscribed to the write-only characteristic, which never notifies, and wrote the handshake to the reply channel. Buttons arrive on the asynchronous channel and the handshake answer on the synchronous one, as `docs/controllers.md` now states.
- A controller that stays silent is reported as needing one pairing in the official application instead of leaving a connection that looks alive and does nothing.
- Frames now match the OpenBikeControl specification byte for byte: the length byte this project added after the type byte is gone, so an application that implements the specification reads our messages instead of a body length mistaken for a button identifier.
- The mDNS announcement carries the TXT record the specification describes (`version`, `id`, `name`, `service-uuids`, `manufacturer`, `model`) instead of short private keys, so a conforming browser finds the bridge and its model.
- Application info frames carry their format version byte, and a frame announcing another version is rejected instead of misread.
- The stream decoder works without a length field: a buffer that decodes whole is one message, two messages coalesced in one read stay apart, and an undecodable write no longer accumulates in the buffer of a peer.

### Added
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
