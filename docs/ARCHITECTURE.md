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

## Inside `app/`

```
main.dart              bootstrap only: the application root and the state
ui/shell.dart          the four sections, their navigation, the readiness lamp
ui/screens/            one file per section, no shared state of their own
  start_screen         the four steps
  gears_screen         the gear panel, and the parked-gear question
  controllers_screen   pairing, the pod's side, the device report
  network_screen       publication, the console relay, the key editor
ui/console_cards.dart  the bridge console, its QR code and its code
ui/design.dart         colours, spacing, type, and the shared widgets
ui/onboarding.dart     the first-start guide
ui/gear_panel.dart     the readout, the ladder, the two paddles
ui/mywhoosh_guide.dart the four-step card MyWhoosh needs
ui/parked_gear_card.dart the parked-gear question
```

The split is not decoration: a screen that shares a file with the navigation
shell cannot be read on its own, and every one of these files fits on a screen.
`main.dart` holds nothing but the root, so a reader looking for a behaviour knows
where to look — the section is the file name.

## Flow of a button press

1. An input backend (BLE, keyboard, HID device) produces a `ButtonEvent`.
2. `Keymap` translates the button id into an `Action`.
3. `GearEngine` updates the state (gear index, mode).
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
