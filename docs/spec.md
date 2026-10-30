# Specification for an open source "controller -> training application" bridge

Design document for starting a free software project. No existing software brand is cited: everything below is derived from the **OpenBikeControl** open specification (MIT) and public Bluetooth standards (FTMS, FE-C, HID, mDNS/DNS-SD).

---

## 1. Purpose

Build free software that connects physical controls (gamepad buttons, shifters, sensors) to an indoor cycling application, with virtual gear shifting, without depending on the hardware of the target application's vendor.

Three problems to solve:

1. **Reading**: capture button presses from BLE controllers that speak proprietary protocols.
2. **Translation**: turn those presses into normalized actions, with gear logic (ratios, virtual chainring).
3. **Delivery**: carry those actions to the target application over the channel it understands (network, Bluetooth, or interface simulation) and, when necessary, drive the home trainer's resistance directly.

## 2. Scope

### MVP

- A BLE controller with two buttons (or more) -> gear up/gear down in a target application that speaks OpenBikeControl.
- Network mode (mDNS + TCP) and Bluetooth mode (GATT).
- "Local control" fallback by injecting keys/taps when the target application implements no protocol.
- Diagnostics: exportable log, readable connection state.

### Out of scope for v1

- Full home trainer emulation with proprietary vendor protocols.
- Activity recording, health, billing.
- Support for exotic undocumented devices.

## 3. Legal and ethical framework (read before coding)

- **Implement from the public specification**, not from decompiled code of a third-party product. The OpenBikeControl spec is MIT licensed: it allows reuse, including commercial reuse, provided the notice is kept.
- **Do not copy a proprietary implementation.** Unpublished vendor protocols (specific control points, private frames) must only be added when public documentation or an authorization is available.
- **Trademarks**: product names (controllers, trainers, applications) belong to their owners. An open source project may cite them descriptively ("compatible with...") without implying a partnership.
- **Privacy**: field protocols have no authentication. The project must say so and offer safeguards (see Section 12).

## 4. Architecture

```
   BLE controllers           button state               normalized actions
 +------------------+      +--------------------+     +-----------------------+
 |  gamepads        |----->|  input layer       |---->|  action engine        |
 |  shifters        | GATT |  (scan, pairing,   |     |  button->action map   |
 |  sensors         |      |   reconnection)    |     |  gears, ratios        |
 +------------------+      +--------------------+     +-----------+-----------+
                                                                  |
        +----------------+-------------------+---------------------+--------------+
        v                v                   v                     v              v
  network output   BLE GATT output     "local" output        trainer proxy   telemetry
  mDNS + TCP       peripheral          accessibility         FTMS/FE-C       log/export
```

Design principles:

- An **input layer** that is agnostic: it produces `(button_id, state, timestamp, device)` events.
- An **engine** with no network side effects: it decides the action and the current gear.
- **Pluggable outputs** behind a common `Transport.send(action)` interface.
- No dependency of the business layer on a platform: it must run in a unit test without Bluetooth.

### Technology choice

| Option | Advantages | Drawbacks |
|---|---|---|
| Flutter/Dart | one codebase for Android, iOS, Windows, macOS, Linux; BLE and mDNS available | uneven peripheral BLE access depending on OS |
| Kotlin Multiplatform | good native control on Android and desktop | iOS less mature |
| Rust + separate UI | testable protocol core, small binary | two BLE stacks to maintain |

Recommendation: **protocol core as a pure library** (Rust or Dart with no plugin), plus a thin UI. The core must be usable by a conformance test without hardware.

## 5. Input layer: controllers

### 5.1 Model

```dart
class ButtonEvent {
  final String deviceId;     // address or stable identifier
  final int buttonId;        // normalized (see Section 7)
  final int value;           // 0 released, 1 pressed, 2..255 analog
  final DateTime at;
}
```

### 5.2 Lifecycle

1. Scan filtered by known services, no permanent scanning (battery saving, OS requirements).
2. Explicit pairing, remembered by stable identifier, automatic reconnection with backoff (1 s, 2 s, 5 s, 15 s, cap).
3. Loss detection: BLE supervision + application heartbeat.
4. A single owner per controller: if another piece of software holds it, show a clear message rather than looping.

### 5.3 Hardware definitions

Each device = one declarative definition file: services and characteristics to listen to, notification format, button -> normalized ID table, quirks (wake on press, vendor lock, sleep time).

```yaml
id: generic-two-button
match: { service: "<service-uuid>" }
notify: { characteristic: "<notify-uuid>" }
decode: { type: raw-bytes, mapping: { 0x01: shift_up, 0x02: shift_down } }
quirks: { wake_on_press: true, sleep_after_s: 60 }
```

No conditional "if brand X" logic in the core: everything goes through these definitions, loaded at runtime.

### 5.4 Special case: locked controllers

Some manufacturers lock their firmware to their own application: the controller only broadcasts its events after pairing inside their app, or it disconnects after a minute. The project must:

- document the official workaround when one exists (prior pairing),
- never break a lock (no signature spoofing),
- display an explicit state: "controller locked by its manufacturer, user action required".

## 6. Gear engine

### 6.1 Model

- Virtual gears `1..N` (N configurable, typically 1 to 30).
- Each gear = a **ratio** (development), optionally a virtual chainring (two chainrings, switched by a button combination).
- `SIM` mode: resistance follows virtual gradient x ratio.
- `ERG` mode: resistance follows a target power; the buttons become +/- watts.
- Mode switching via a dedicated button, without leaving the saddle.

### 6.2 Resistance computation in SIM

```
target_resistance = f(gradient, estimated_bike_speed, current_ratio, rider_weight, Crr, CdA)
```

Implementation notes:

- The ratio changes the simulated speed for a given cadence, hence the resistance to apply.
- Smooth transitions (100 to 300 ms ramp) to avoid jolts.
- If the application goes silent (no gradient received), keep the last gradient and report it.

### 6.3 Perceived quality

- No excessive resistance gap between two gears: even spacing by default, named profiles ("climb", "sprint", "recovery").
- Optional vibration or sound on shift, distinct at the limit stop.
- Debouncing: never count a press twice; handling of held presses (repeat at 250 ms).

## 7. Normalized protocol (OpenBikeControl, MIT)

Source of truth: `https://openbikecontrol.org` and the `OpenBikeControl/openbikecontrol-protocol` repository (PROTOCOL.md, BLE.md, MDNS.md). Operational summary:

### 7.1 Binary messages

| Type | Direction | Format |
|---|---|---|
| `0x01` | device -> app | `[01] [button_id] [state] ...` (20 bytes max recommended) |
| `0x02` | device -> app | `[02] [battery] [connected]` |
| `0x03` | app -> device | `[03] [pattern] [duration x 10 ms] [intensity]` |
| `0x04` | app -> device | `[04] [version] [len_id][id] [len_ver][ver] [button_count][ids...]` |

State: `0x00` released, `0x01` pressed, `0x02..0xFF` analog.

### 7.2 Button identifiers

| Range | Usage |
|---|---|
| `0x01` | gear up |
| `0x02` | gear down |
| `0x03` | direct gear selection (analog value, 1-based index + 1) |
| `0x04` / `0x05` | chainring / cassette (analog) |
| `0x10..0x15` | navigation, confirm, back, menu |
| `0x18` / `0x19` | steer left / right |
| `0x1A` / `0x1B` | brake / handlebar angle (analog) |
| `0x20..0x24` | emotes, push-to-talk, capture |
| `0x30..0x3C` | difficulty +/-, pause, resume, lap, mode, cruise |
| `0x40..0x46` | camera, HUD, map, spectator |

### 7.3 Network transport

- mDNS service `_openbikecontrol._tcp.local.`
- TXT: `version=1`, `id=`, `name=`, `service-uuids=`, `manufacturer=`, `model=`
- TCP on a dynamically chosen port, published in the mDNS announcement.
- Multiple simultaneous connections possible; automatic reconnection on the application side.

### 7.4 Bluetooth transport

- Service `d273f680-d548-419d-b9d1-fa0472345229`
- `d273f681-...` buttons (read/notify)
- `d273f682-...` haptics (write)
- `d273f683-...` app information (write)
- Advertisement: 128-bit service UUID only, no manufacturer data (iOS constraint).
- Connection interval 7.5 to 15 ms, latency 0, supervision 4 s, MTU 247 preferred.

## 8. Outputs

### 8.1 OpenBikeControl network

Implement the TCP server described in Section 7.3, with a robust port selector (range 1024-65535, retry on collision) and an mDNS announcer that re-registers after an IP address change.

### 8.2 BLE peripheral

GATT server exposing the service in Section 7.4. On Android, verify that the peripheral is allowed in the background; on iOS, the advertisement is limited but sufficient.

### 8.3 Local mode (injection)

When the target application exposes no protocol: simulate the interface.

- Android: accessibility service, gestures and key events.
- Desktop: send keyboard shortcuts to the active window.
- Store **keymaps** per target application: tap positions, or key combinations.
- Always ask for explicit consent: this mode grants full control of the screen.

### 8.4 Home trainer proxy

To apply the gears to the trainer yourself:

1. Connect to the trainer over FTMS (BLE) or over the network.
2. Read power, cadence, and the gradient requested by the application.
3. Write the resistance matching the current ratio.
4. Re-publish the trainer to the application.

Warning: two resistance controllers in parallel cancel each other out. Provide an exclusive mode and a clear message: "disable the target application's shifting".

Implement public standards only: FTMS (`0x1826`, control point `0x2AD9`, indoor bike simulation `0x11`) and FE-C (`6e40fec1...`, 8-byte pages).

## 9. Network discovery: pitfalls

- Android: Wi-Fi multicast lock required to receive mDNS.
- Windows: mDNS depends on Bonjour or on the system resolver; warn the user if the announcement is not visible.
- Guest networks, client isolation, mesh repeaters: they block discovery. Document a check, "is the announcement visible?", inside the app.
- Changing band or access point invalidates sockets: re-register the announcement and reopen the TCP socket.

## 10. Minimal user experience

- Home screen: detected controllers, detected trainer, chosen target application, status of all three.
- A "test" button that sends a dummy action and shows haptic feedback if the device supports it.
- Compact overlay (current gear) above the target application.
- Diagnostic log exportable as a single file, with version, devices, last exchanges (no personal data).

## 11. Quality and testing

- **Unit tests** for the binary codec: example vectors from the spec, edge cases (20 bytes, analog, multi-button).
- **Hardware-free integration tests**: simulated BLE peripheral (GATT mock) and local TCP server.
- **Compatibility matrix**: application x channel x validated features table, versioned with the releases.
- **Load test**: 30 presses/second for 10 minutes, no memory leak, p95 latency < 50 ms over the network, < 20 ms over BLE.
- **CI**: lint, tests, build of binaries for the target platforms, publication of signed artifacts.

## 12. Security

Field protocols are **unauthenticated**. Expected measures:

- Announcement can be disabled, and is never enabled by default on first launch.
- Clear warning: any device on the same network can send actions.
- Optional address filtering (allowlist) in advanced settings.
- No personal data in logs; no telemetry without consent.
- Interface injection mode requires explicit, revocable system authorization.

## 13. Proposed repository layout

```
project/
+- core/                 # protocol, codec, gear engine (no I/O)
|  +- protocol/          # messages 0x01..0x04, button IDs
|  +- shifting/          # ratios, virtual chainring, SIM/ERG modes
|  +- mapping/           # button -> action, keymaps
+- transports/
|  +- mdns_tcp/
|  +- ble_peripheral/
|  +- local_injection/
|  +- trainer_proxy/
+- devices/              # declarative controller definitions
+- apps/                 # Android/iOS/desktop UI
+- tools/                # controller simulator, test bench
+- docs/                 # this spec, compatibility matrix
+- .github/workflows/    # CI
```

## 14. Roadmap

| Milestone | Content | Exit criterion |
|---|---|---|
| M0 | core + codec + tests | spec vectors pass |
| M1 | BLE input + one controller | presses visible in the log |
| M2 | network output | target application receives gear changes |
| M3 | BLE peripheral output | pairing and notifications OK |
| M4 | gear engine + overlay | 12 usable gears in simulation |
| M5 | local mode | control of an application with no protocol |
| M6 | trainer proxy | resistance driven, without conflict |
| M7 | hardening | load tests, docs, signed release |

## 15. MVP acceptance criteria

1. A two-button controller changes gear in the target application in under 100 ms end to end.
2. The connection survives a 30 s Wi-Fi outage and recovers on its own.
3. The log allows diagnosing a failure without access to the code.
4. No feature requires an account, a wide area network, or a third-party service.
5. The core code is testable without hardware and without Bluetooth.

---

## References

- OpenBikeControl specification (MIT)
- Bluetooth FTMS (`0x1826`)
- ANT+ FE-C over BLE
- RFC 6762 (mDNS)
- RFC 6763 (DNS-SD)
