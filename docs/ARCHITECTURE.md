# Architecture

## Layers

```
app/          Flutter interface (android, ios, windows, macos)
  └─ depends on core + transports, holds no business logic
transports/   pluggable outputs, network and platform I/O
  └─ depends on core
core/         pure core: protocol, shifting, mapping, devices
  └─ no I/O, no plugins, testable without hardware
```

Golden rule: `core` knows neither Flutter, nor Bluetooth, nor the file system at runtime (device definitions are loaded by the caller, not by the core).

## Flow of a button press

1. An input backend (BLE, keyboard, HID device) produces a `ButtonEvent`.
2. `Keymap` translates the button id into an `Action`.
3. `GearEngine` updates the state (gear index, chainring, mode).
4. Every active `Transport` receives the action: network (`0x01` message), BLE peripheral, local injection, or trainer proxy (resistance write).

## States and errors

- Each transport exposes an event stream: connected, disconnected, error, action consumed.
- A transport error must never stop the others: the bridge keeps working on the remaining channels.
- Trainer-proxy mode and "target app controls resistance" mode are mutually exclusive, and the interface must state it explicitly.

## Testing

| Level | Tool | Coverage |
|---|---|---|
| core unit | `dart test` in `core/` | binary codec, shifting, mapping, definitions |
| transports integration | `dart test` in `transports/` | TCP server, partial frames, multiple clients |
| interface | `flutter test` in `app/` | screen states, test bench |

No test may require Bluetooth, an external network or a physical device.

## Open decisions

- BLE peripheral backend: single cross-platform plugin or native implementations per OS?
- mDNS advertiser: external dependency or minimal implementation (RFC 6762)?
- Keyboard injection on Windows/macOS: native system API or external tool?
