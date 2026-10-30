# openzclick

A free bridge between indoor cycling controllers and training apps: controller buttons change virtual gears, the smart trainer follows the resistance.

A single codebase for Android, iOS, Windows and macOS.

## Status

| Module | Contents | State |
|---|---|---|
| `core/` | binary codec, controller protocol, ECDH/HKDF/AES-CCM session, gear engine, mapping, device definitions | implemented, 212 tests |
| `transports/` | mDNS/TCP network transport, Bluetooth/injection/proxy interfaces | network implemented and tested, the rest are interfaces |
| `app/` | Flutter app: controller pairing, virtual gears, diagnostics | working on the four platforms, 6 widget tests |

The app pairs a two-button Bluetooth controller, decodes its notifications (plain and encrypted sessions) and turns them into gear changes. Publishing to a training app over the network is implemented in `transports/` but not yet wired into the app; on iOS it also requires Apple's multicast entitlement.

## Download

Every push to `main` builds an unsigned iOS application and publishes it as a release asset:

**https://github.com/Atlanwhite147/openzclick/releases/download/latest/openzclick-unsigned.ipa**

Install it with Sideloadly or AltStore and a free Apple ID: the signature lasts 7 days, then it must be signed again. A paid developer account extends it to one year and allows ad-hoc distribution.

## Layout

```
openzclick/
├─ core/            # pure Dart, no I/O
├─ transports/      # network, Bluetooth, local injection, trainer proxy
├─ app/             # Flutter: android, ios, windows, macos
├─ docs/            # specification and architecture notes
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

## How the controller link works

1. Scan for the controller service (`00000001-19ca-4651-86e5-fa29dcdd09d1`).
2. Connect and subscribe to the synchronous receive channel.
3. Send the handshake: an encrypted request carrying an ephemeral P-256 public key, with a plain `RideOn` fallback after three seconds.
4. If the device answers with its public key, derive the session (ECDH, HKDF-SHA256, AES-CCM with a 4-byte MAC) and decrypt every frame; otherwise parse frames in the clear.
5. Decode button notifications (protobuf varints) and emit gear changes.

Protocol facts are reimplemented in Dart from public interoperability notes; no third-party code is copied. The cryptographic primitives come from `pointycastle`.

## Principles

- The core performs no I/O: it can be tested without hardware or Bluetooth.
- One output = one `Transport` implementation, wired at runtime.
- No brand-specific conditionals in the core: devices are described by declarative definition files.
- Field protocols are unauthenticated: network advertising is off by default and must be enabled explicitly.

## Roadmap

See `docs/spec.md`. Done: protocol core, controller input, gear engine, gear profiles, app shell. Next: native Bluetooth peripheral backend, mDNS advertiser, keyboard/touch injection, FTMS trainer proxy.

## License

MIT (see `LICENSE`).
