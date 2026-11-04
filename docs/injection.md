# Local injection

Some applications accept neither the network protocol nor a Bluetooth controller. The bridge then acts as a keyboard or a finger: it translates each action into a keystroke or a tap on the host where the application runs.

## Where it stands

| Host | Keyboard | Pointer | State |
|---|---|---|---|
| Linux, X11 | yes, through XTest (`libXtst`) | yes, motion and left click | implemented, verified |
| Android | no (the platform forbids it) | yes, through the accessibility service | implemented, verified |
| Windows | yes, through `SendInput` (`user32.dll`) | yes, cursor move and left click | implemented, unverified on hardware |
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

## The Windows implementation

`app/lib/net/windows_injection.dart` loads `user32.dll` at runtime with `dart:ffi`, like the Linux file loads X11. It was written from the review on the project's Reddit thread, and it carries the traps that were pointed out there, each one a known way to lose an afternoon:

- **`cbSize` is `sizeof(INPUT)`**, 40 bytes on x64, and not `sizeof(KEYBDINPUT)`, which is 24. Passing the smaller size makes every call fail with a parameter error that names none of it. The layout is built in `windows_key_event.dart`, in plain Dart, so a test asserts every offset without a Windows machine: the size, the type at offset 0, the virtual key at 8, the key-up flag at 12, `dwExtraInfo` at 24 — not 20, which would overwrite the timestamp.
- **A press and a release are two separate calls**, twelve milliseconds apart. An application that polls the key state sees nothing if both arrive in one buffer.
- **`SendInput` returns how many events it inserted, and zero is a failure.** UIPI refuses to inject into a window of higher integrity, and `GetLastError` does not name that as the cause. A zero return is raised as an error here, never counted as a gear change: a shift the rider did not see is worse than a shift that announces it failed.
- **A key name that the table does not know is refused**, not guessed: a wrong virtual-key code presses a key nobody asked for. `windows_keys.dart` holds the table, which covers the X11 names the bindings already use (`Left`, `Page_Up`, `BackSpace`).

`tapAt` uses `SetCursorPos` followed by `mouse_event`, which is enough for a click on a control. Coordinates are fractions of the screen, as on Linux.

### What this design cannot promise, and the alternative

`SendInput` places events in the session's input queue and hopes the target application listens at that layer. Linux has the stronger position: XTest reaches a virtual device that the system treats as hardware. Applications reading Raw Input, DirectInput or an exclusive fullscreen surface may ignore injected events entirely, and nothing in the bridge can detect that — the call succeeds and the gear does not move.

The alternative, raised in the same review, is to emulate a device rather than inject: a virtual gamepad through ViGEm on Windows, `IOHIDUserDevice` on macOS. Training applications already support controllers, so a virtual pad lands on well trodden ground and needs no accessibility permission on macOS. It was not taken here for one reason: ViGEm needs a signed kernel driver installed on the rider's machine, and the promise of this project is that there is nothing to install beyond the application itself. If measurement shows the injector is ignored by the applications riders actually use, that trade changes and this paragraph becomes the plan.

## Writing the macOS port

The contract is one small interface, `KeyInjector`, with two methods. A port is a single file plus a line in `AppState`:

- **macOS**: `CGEventCreateKeyboardEvent` and `CGEventPost`, which requires the accessibility permission in System Settings, granted by the user to the application.

Constraints that keep the port mergeable:

1. Load the system library at runtime, never link against it at build time.
2. Return a clear error when the platform refuses, instead of failing silently.
3. Add a unit test with `MemoryKeyInjector` for the routing, and describe in the pull request how you verified the real injection.

## Why not a Bluetooth HID keyboard

Presenting the bridge as a Bluetooth keyboard would need no permission on the host, but it only reaches another machine, never the application running on the same device. It is a different feature, not a shortcut for this one.
