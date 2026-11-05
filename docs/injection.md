# Local injection

Some applications accept neither the network protocol nor a Bluetooth controller. The bridge then acts as a keyboard or a finger: it translates each action into a keystroke or a tap on the host where the application runs.

## Where it stands

| Host | Keyboard | Pointer | State |
|---|---|---|---|
| Linux, X11 | yes, through XTest (`libXtst`) | yes, motion and left click | implemented, verified |
| Android | no (the platform forbids it) | yes, through the accessibility service | implemented, verified |
| Windows | yes, through `SendInput` (`user32.dll`) | yes, cursor move and left click | implemented, measured on one machine: the keys arrive in a window that does not own the application; whether a training application accepts them is unverified (`#measured-on-windows`) |
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

The keys are per application, because they are not the same: `i` and `k` are
MyWhoosh, `,` and `.` are Rouvy, `W` and `S` are Biketerra. The Network tab picks
the application, and the table lives in `app/lib/net/key_profiles.dart` with the
page each row was read from.

| Application | Shift up (harder) | Shift down (easier) | Steering | Source |
|---|---|---|---|---|
| MyWhoosh | `k` | `i` | arrows | [MyWhoosh shortcuts](https://mywhooshinfo.com/blog/mywhoosh-keyboard-shortcuts) |
| Rouvy | `.` | `,` | arrows | [Rouvy remote controls](https://support.rouvy.com/hc/en-us/articles/47742964491665-Remote-controllers-and-control-mapping) |
| Biketerra | `w` | `s` | — | [Biketerra virtual shifting](https://biketerra.com/help-center/virtual-shifting) |
| Any other | `k` | `i` | arrows | the bridge's own default |

Zwift and TrainerRoad are absent on purpose: neither exposes a virtual-shifting
key, so a row for them would be invented.

A multiplier (1 to 3) sends that many presses per button push, for applications
that expose a ladder of gears rather than a ratio. Two presses are separated by
60 ms, because an application that polls the key state sees nothing if both arrive
in the same buffer.

The direction is the one trap in the table. Public shortcut listings disagree on
whether `i` or `k` shifts up, and the MyWhoosh page names the two keys without
saying which way they go. MyWhoosh is set to `k` up and `i` down, which is what
two independent implementations do — the profile shipped by
[`zwiftboard`](https://github.com/thomaschampagne/zwiftboard) (MIT) and
[`ClickShift`](https://github.com/prioneto/ClickShift). If a rider reports an
inverted ladder, this table is the line to change — not the gear engine.

## The Windows implementation

`app/lib/net/windows_injection.dart` loads `user32.dll` at runtime with `dart:ffi`, like the Linux file loads X11. It was written from the review on the project's Reddit thread, and it carries the traps that were pointed out there, each one a known way to lose an afternoon:

- **`cbSize` is `sizeof(INPUT)`**, 40 bytes on x64, and not `sizeof(KEYBDINPUT)`, which is 24. Passing the smaller size makes every call fail with a parameter error that names none of it. The layout is built in `windows_key_event.dart`, in plain Dart, so a test asserts every offset without a Windows machine: the size, the type at offset 0, the virtual key at 8, the key-up flag at 12, `dwExtraInfo` at 24 — not 20, which would overwrite the timestamp.
- **A press and a release are two separate calls**, twelve milliseconds apart. An application that polls the key state sees nothing if both arrive in one buffer.
- **`SendInput` returns how many events it inserted, and zero is a failure.** UIPI refuses to inject into a window of higher integrity, and `GetLastError` does not name that as the cause. A zero return is raised as an error here, never counted as a gear change: a shift the rider did not see is worse than a shift that announces it failed.
- **A key name that the table does not know is refused**, not guessed: a wrong virtual-key code presses a key nobody asked for. `windows_keys.dart` holds the table, which covers the X11 names the bindings already use (`Left`, `Page_Up`, `BackSpace`).

`tapAt` uses `SetCursorPos` followed by `mouse_event`, which is enough for a click on a control. Coordinates are fractions of the screen, as on Linux.

### Typing into the right window

A keystroke goes to the window that owns the focus, and that window is rarely the
training application: the rider had to look at this one to press a button, or
something else stole the focus mid-ride. The key is then inserted, reported as
sent, and received by a chat window.

The *Type into this window only* field on the Network tab takes a fragment of the
window title — `MyWhoosh` matches `MyWhooshHD` and `MyWhoosh - Free ride`. When it
is set, every keypress first restores and raises that window, then types. When
nothing matches, the key is **not** sent and the reason is shown under the switch:
typing into an unrelated application is worse than a shift that does not happen.
Empty, the field changes nothing and the key goes to whatever has the focus.

Two limits, both honest: only the window **title** is matched (not the executable
name), and Windows refuses `SetForegroundWindow` from a process that does not own
the foreground, in which case the refusal is reported rather than hidden. The
matching rule lives in `app/lib/net/window_focus.dart` and is tested without
Windows; the enumeration is in `windows_focus.dart` and is not.

The idea comes from `zwiftboard` (MIT), which offers it per profile.

### Measured on Windows

The buffer layout was tested in plain Dart from the start; the call itself had never run, because no machine used to write the project had a Windows desktop to inject into. It has now been measured on a Windows 11 PC (build 26200), driven from another computer over the network:

1. the application ran in the interactive session, with the settings that start the network publication and the injection by themselves;
2. a console connected to the relay the bridge serves (`ws://<host>:47124/console?token=…`) and typed `shiftUp`, then `shiftDown`;
3. the state published back by the bridge went from gear 10 to 11 and back to 10;
4. a plain window that did **not** own the application received `i`, then `k`.

So `SendInput` reaches a normal window from a process that does not have the focus, which is the only thing this design could not promise by reasoning. Two things it does not establish, and which must not be written down as verified:

- **Whether a training application accepts the events.** MyWhoosh, Zwift and Rouvy each decide at which layer they read the keyboard; that is the open question in `docs/ROADMAP.md`, and it needs a ride, not a probe.
- **The everyday integrity pair.** The measured run had the application started with administrator rights, so it injected from a high-integrity process into a normal window. Two applications both at normal integrity is the common case and should behave the same; an application running *elevated* while openzclick runs normally is the case UIPI refuses, and the code reports it as a refusal rather than as a gear change. Measuring that refusal is worth an afternoon: it is the one failure a rider would otherwise blame on the bridge.

The same run also showed what a missing Windows component costs: MyWhoosh asks for the Xbox Game Bar overlay through the `ms-gamingoverlay:` URI at startup, and on a machine where Game Bar has been removed, Windows answers with a modal *"get an app to open this link"* dialog that sits in front of the game. Nothing in the application can prevent that; it belongs in the install notes.

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
