# Changelog

All notable changes to this project are documented here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project adheres to [Semantic Versioning](https://semver.org/).

## [Unreleased]

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
