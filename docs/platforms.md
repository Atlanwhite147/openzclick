# Platforms and verified hardware

What the README keeps to one line each lives here in full: which platforms run
which part, and what was actually measured, on which machine, with which
hardware.

## Capability matrix

| Capability | Windows | Linux | macOS | Android | iOS |
|---|:--:|:--:|:--:|:--:|
| Pair the controller, gears, left and right | ✅ | ✅ | ✅ | ✅ | ✅ |
| Belongs to you, no account | ✅ | ✅ | ✅ | ✅ | ✅ |
| mDNS announcement + TCP server | ✅ | ✅ | ✅ | ✅ | ⚠️ needs Apple's entitlement |
| Drive the bridge from a phone | ✅ | ✅ | ✅ | ✅ | ✅ |
| Keyboard injection (no protocol support) | ✅ `SendInput` | ✅ X11 | ❌ | - | - |
| Tap injection (on-screen controls) | ❌ | ❌ | ❌ | ✅ accessibility service | ❌ |
| Become the trainer (FTMS peripheral) | ❌ | ❌ | ❌ | ❌ | ❌ |

✅ verified · ⚠️ works with a platform constraint · ❌ not implemented, open to a
contributor

iOS forbids synthetic input entirely, and its mDNS is blocked until Apple grants
the multicast entitlement; the bridge then shows the address to type.

## Measured on real hardware

| Where | What was verified |
|---|---|
| Windows 11, Click v2 (firmware `1.1.0`) | scan, connect, plain session, five buttons identified one at a time, `+` and `B` shifting end to end, a client on another machine reading the frames over the tailnet |
| Windows 11, injection | gear 10 → 11 → 10 from a console on another machine; a window that did not own the application received `i` then `k` |
| Android 13 | install, first frame, gear changes, direction from **Network**, tap injection through the accessibility service, announcement visible on the LAN, TCP handshake |
| macOS 26.6, Click v2 | scan, connect, the `RideOn` handshake, `+` and `B` changing the gear in MyWhoosh during a real ride; the keepalive write every three seconds |

The three modules run without a radio or a network. Still unverified: the
Bluetooth radio on iOS against real hardware ([CONTRIBUTING.md](../CONTRIBUTING.md)
explains how to report a controller that does not pair).

## Why a phone cannot be the bridge

A phone cannot be the bridge MyWhoosh discovers, because a normal web page may
not open a server. It can drive one: run the application on the computer where
MyWhoosh runs, tap **Start**, and scan the QR code in **Network**. The phone
opens the console the bridge serves itself, at `http://<computer-ip>:47124`
([console.md](console.md)).

## Builds

Only macOS is built automatically. The other files are built on request:

```
gh workflow run "Windows build" -R Atlanwhite147/openzclick --ref main
```

Same for `Android` and `iOS`.
