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

That service is the vendor one, `0000fc82-0000-1000-8000-00805f9b34fb`, and that
is what the controller announces in its advertising packet. The
`00000001-19ca-4651-86e5-fa29dcdd09d1` identifier that names the channels is not
announced anywhere: a scan filtered on it returns nothing, whatever the state of
the controller, and the failure is silent. Measured on a Click v2, firmware
1.1.0, which also exposes `0100`, `0101` and `0102` in the same service, one per
pod of the pair.

Two mistakes follow from the names, which come from the controller's point of
view:

1. **Subscribing to `0003`.** It is write-only, so it never notifies. A bridge
   built that way connects, writes the handshake, and then waits forever.
2. **Writing the handshake to `0004`.** It is the reply channel; the write either
   fails silently or is ignored.

The buttons arrive on `0002` and the handshake acknowledgement on `0004`.
Subscribe to both, write to `0003`.

## Which button is which

Measured on a Click v2 (firmware 1.1.0), one button at a time, by reading the
mask out of the `23 08 <varint>` notification. A press clears its bit; every
other bit stays set, so the resting frame is `23 08 ff ff ff ff 0f`.

| Button | Bit | Frame while held |
|---|---|---|
| `+` (under the cluster) | 12 | `23 08 ff df ff ff 0f` |
| `B` (bottom, pink) | 5 | `23 08 df ff ff ff 0f` |
| `Y` (top, blue) | 6 | `23 08 bf ff ff ff 0f` |
| `Z` (left, orange) | 7 | `23 08 7f ff ff ff 0f` |
| `A` (right, green) | 4 | `23 08 ef ff ff ff 0f` |

Only `+` and `B` reach the gear engine: they are the two a rider shifts with,
and mapping the other three would change gear on a button pressed for another
reason. Naming the rest is a one-line change once a use for them exists.

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

   A Click v2 makes this case harder than it sounds: it replies to the encrypted
   request with a bare `RideOn` echo, six bytes and no key, and then stays
   silent. That echo is a receipt, not an answer. A bridge that treats "a frame
   arrived" as "the session is up" never sends the plain handshake, and the
   controller never streams its buttons: the link is connected, quiet, and looks
   like a broken decoder. The fallback therefore depends on the derived session
   being null, not on the absence of bytes.
3. **Silent.** Nothing arrives at all. Silence is not a radio problem: in the
   field it is almost always a controller that has never been paired in the
   official application, which is the well known Click v2 behaviour where the
   link dies about a minute after it is established.

`ControllerLinkWatchdog` in `core/lib/src/protocol/controller_watchdog.dart` turns
that silence into explicit actions: send the plain handshake, report that the
controller needs to be unlocked, or write the keepalive that holds the session
open. It is pure logic: the caller feeds it one second at a time, so every rule
is tested without hardware.

## When a Click v2 drops after a minute

Two explanations exist, and the second one is newer and testable:

1. **The unlock story.** Pair the controller once in the official application,
   keep that application open about three minutes rather than a few seconds,
   then switch to the bridge. On the units where the drop was reproduced, that is
   what stopped it. The bridge cannot reproduce that gesture by itself: it is a
   handshake the official application performs, and copying it means reversing a
   key exchange that requires that application's identity.
2. **The keepalive story.** A pod drops about a minute after the **last write it
   received**, not after the last button. [`zwiftboard`](https://github.com/thomaschampagne/zwiftboard)
   (MIT) holds a Click v2 for a whole ride on Windows without any account or any
   unlock, by writing the plain `RideOn` every three seconds, and it says so
   plainly: button silence never ends a session, a failed write does. This
   project now does the same, and also writes the two frames that complete the
   activation (`00 08 00`, `00 08 10`) after the plain handshake.

If the drop disappears with the keepalive, the first story was a misdiagnosis of
the second: a rider who paired in the official app and then launched the bridge
would have described a symptom that a three-second write prevents for a reason
that has nothing to do with pairing. Which of the two is true is settled by one
test on a controller that still drops — connect the bridge, press nothing for two
minutes, then press once. If the frame arrives, it was the keepalive.

## Reporting a controller that does not pair

Open an issue and paste the device report: **Controllers**, then *Copy device
report*. One tap, and everything a maintainer cannot guess travels with it —
application version, host, device name and identifier, the strings of the Device
Information service (manufacturer, model, serial, firmware, hardware), the whole
GATT tree with its properties, and the last 40 frames with their direction and
timing relative to the moment the link was made.

The report exists because of the shape of this project: most of it is written on
a machine with no Bluetooth radio, so most rules run against a fake controller. Asking a
rider to describe a dropout returns something incomplete and unreproducible;
asking for one pasted blob returns something that can be replayed. The frames are
recorded before they are parsed, so a frame the decoder does not recognise is
still in the report — that is usually the finding.

A pairing that works is as useful as one that fails: the table of working
firmware versions is what tells a rider whether upgrading will break their setup.
