# openzclick

A free bridge between indoor cycling controllers and training apps: controller buttons change virtual gears, the smart trainer follows the resistance.

A single codebase for Android, iOS, Windows and macOS.

## Repository status

Project baseline (milestone M0): protocol core, gear engine, device definitions and transport layer. The Flutter app is a working skeleton that shows module status and a test bench.

| Module | Contents | State |
|---|---|---|
| `core/` | binary codec, gear engine, mapping, device definitions | implemented, tested |
| `transports/` | mDNS/TCP network transport, Bluetooth/injection/proxy interfaces | network implemented and tested, the rest are interfaces |
| `app/` | Flutter shell for four platforms | skeleton |

## Layout

```
openzclick/
├─ core/            # pure Dart, no I/O
├─ transports/      # network, Bluetooth, local injection, trainer proxy
├─ app/             # Flutter: android, ios, windows, macos
├─ docs/            # specification and notes
└─ CONTRACTS.md     # interface signatures between modules
```

## Getting started

```bash
# core and transports
cd core && dart pub get && dart test
cd ../transports && dart pub get && dart test

# application
cd ../app && flutter pub get && flutter run -d linux   # or windows, macos, android, ios
```

## Principles

- The core performs no I/O: it can be tested without hardware or Bluetooth.
- One output = one `Transport` implementation, wired at runtime.
- No brand-specific conditionals in the core: devices are described by declarative definition files.
- Field protocols are unauthenticated: network advertising is off by default and must be enabled explicitly.

## Roadmap

See `docs/spec.md`. In short: per-platform Bluetooth peripheral backend, native mDNS advertiser, keyboard/touch injection, FTMS trainer proxy, then the full interface.

## License

MIT (see `LICENSE`).
