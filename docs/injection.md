# Local injection

Some applications accept neither the network protocol nor a Bluetooth controller. The bridge then acts as a keyboard or a finger: it translates each action into a keystroke or a tap on the host where the application runs.

## Where it stands

| Host | Keyboard | Pointer | State |
|---|---|---|---|
| Linux, X11 | yes, through XTest (`libXtst`) | yes, motion and left click | implemented, verified |
| Android | no (the platform forbids it) | yes, through the accessibility service | implemented, verified |
| Windows | no | no | **needs a contributor** |
| macOS | no | no | **needs a contributor** |
| iOS | no | no | impossible, iOS has no synthetic input |

## The Linux implementation

`app/lib/net/x11_injection.dart` loads `libX11` and `libXtst` at runtime with `dart:ffi`. It never links against them, so the application still starts on a headless machine and simply reports that injection is unavailable.

- `pressKey(name)` resolves the name with `XStringToKeysym`, converts it with `XKeysymToKeycode`, then calls `XTestFakeKeyEvent` for the press and the release, twelve milliseconds apart, which is enough for applications that poll the key state.
- `tapAt(x, y)` moves the pointer and clicks, with coordinates relative to the screen.

Verified on a virtual X server: injecting `i`, `Left` and `k` produced the matching `KeyPress` and `KeyRelease` events in `xev`, with the expected keycodes and keysyms. Reproduce it with:

```bash
Xvfb :99 -screen 0 1280x720x24 &
DISPLAY=:99 xev -root -event keyboard &
cd app && DISPLAY=:99 dart run tool/x11_probe.dart i Left k
```

## Default bindings

| Action | Key |
|---|---|
| shift up | `i` |
| shift down | `k` |
| steer left | `Left` |
| steer right | `Right` |

These match the shortcuts of common training applications. They live in `InjectionPublisher.defaultKeys` and are easy to make configurable.

## Writing the Windows or macOS port

The contract is one small interface, `KeyInjector`, with two methods. A port is a single file plus a line in `AppState`:

- **Windows**: `SendInput` with `INPUT_KEYBOARD` structures, or `keybd_event` for a first version. The scan code path is more reliable for games, which is why some projects use it.
- **macOS**: `CGEventCreateKeyboardEvent` and `CGEventPost`, which requires the accessibility permission in System Settings, granted by the user to the application.

Constraints that keep the port mergeable:

1. Load the system library at runtime, never link against it at build time.
2. Return a clear error when the platform refuses, instead of failing silently.
3. Add a unit test with `MemoryKeyInjector` for the routing, and describe in the pull request how you verified the real injection.

## Why not a Bluetooth HID keyboard

Presenting the bridge as a Bluetooth keyboard would need no permission on the host, but it only reaches another machine, never the application running on the same device. It is a different feature, not a shortcut for this one.
