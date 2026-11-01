# Controllers: the link that connects and then says nothing

Everything below comes from protocol facts gathered from public interoperability
notes and from reading what two working implementations do on the wire. No
third-party code is copied: the behaviour is reimplemented in Dart and covered by
tests that run without a radio.

## The three channels, and the mistake that costs an evening

The controller exposes one custom service with three characteristics. They do not
do the same job:

| Characteristic | UUID suffix | Direction | Carries |
|---|---|---|---|
| async | `0002` | controller to host, notify | the button stream |
| syncRx | `0003` | host to controller, write | handshake and commands |
| syncTx | `0004` | controller to host, indicate | handshake reply, answers |

Two mistakes follow from the names, which come from the controller's point of
view:

1. **Subscribing to `0003`.** It is write-only, so it never notifies. A bridge
   built that way connects, writes the handshake, and then waits forever.
2. **Writing the handshake to `0004`.** It is the reply channel; the write either
   fails silently or is ignored.

The buttons arrive on `0002` and the handshake acknowledgement on `0004`.
Subscribe to both, write to `0003`.

## The three behaviours a controller can have

A controller answers the host in one of three ways, and only the first two can be
detected from the bytes:

1. **Encrypted.** It replies with `RideOn`, then `01 03`, then its 64-byte public
   key. Derive the session (P-256 ECDH, HKDF-SHA256 with salt `device || host`,
   AES-CCM, 4-byte big-endian counter) and decrypt everything after that.
2. **Plain.** It ignores the encrypted request and only understands the six-byte
   `RideOn` marker, then sends frames in the clear. Some firmware does exactly
   this, which is why the bridge sends the plain request after three seconds
   without an answer.
3. **Silent.** Nothing arrives at all. Silence is not a radio problem: in the
   field it is almost always a controller that has never been paired in the
   official application, which is the well known Click v2 behaviour where the
   link dies about a minute after it is established.

`ControllerLinkWatchdog` in `core/lib/src/protocol/controller_watchdog.dart` turns
that silence into three explicit actions: send the plain handshake, report that
the controller needs to be unlocked, or reconnect. It is pure logic: the caller
feeds it one second at a time, so every rule is tested without hardware.

## When a Click v2 drops after a minute

Documented workaround, from the field: pair the controller once in the official
application, keep that application open about three minutes rather than a few
seconds, then switch to the bridge. On the units where the drop was reproduced,
that is what stopped it. No subscription is needed, only an account that can
reach the pairing screen.

The bridge cannot repair this by itself: the unlock gesture is a handshake the
official application performs, and reproducing it means reverse engineering a key
exchange that requires that application's own identity.

## Reporting a controller that does not pair

Open an issue with the model, the firmware version, the phone or desktop model,
and the last twenty lines of the diagnostic log. A pairing that works is as
useful as one that fails: the table of working firmware versions is what tells a
rider whether upgrading will break their setup.
