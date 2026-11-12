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
| `Z` (left, orange) | 7 | `23 08 ff fe ff ff 0f` |
| `A` (right, green) | 4 | `23 08 ef ff ff ff 0f` |

Only `+` and `B` reach the gear engine: they are the two a rider shifts with,
and mapping the other three would change gear on a button pressed for another
reason. Naming the rest is a one-line change once a use for them exists.

The frame is decoded into a mask of the pressed positions rather than into two
booleans, so an unmapped button is still visible in the diagnostics instead of
vanishing between the decoder and the gear engine, and a frame repeated by the
second pod of a pair is a state the application already had rather than a second
press. The left pod's arrows have no measured offset yet: a guessed one would
turn a steering press into a gear change, so the device report — which keeps
frames as they arrived, in hexadecimal — is what will name them.

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

The test that section used to call for has been run, and it settles the question
against the keepalive. On 2026-11-12, on Windows, with a Click v2 (firmware
1.1.0, serial `0A-34C459DD3C3D`), the application held the link and wrote the
plain `RideOn` every three seconds: the pod echoed every write, then went quiet
and dropped **92 seconds** after the link came up, with the last echo 2.9 s
before the end and no stop notice on `0004`. The keepalive is not what holds a
Click v2.

What the drop actually is, per [BikeControl](https://bikecontrol.app/controller-zwift-click-v2/),
which documents the same unit for every non-Zwift application: the Click v2
expects an encrypted handshake refreshed with Zwift's service roughly every
**24 hours**, and once that context lapses it stops sending button events about
**a minute** after being connected. It is the first cause they list for a pod
that goes quiet elsewhere, and it is not something a host can derive on its own.
Two remedies exist:

- **Run the right pod alone.** BikeControl reports that the right pod needs no
  unlock at all; only the left one carries the daily requirement. Most riders
  only need `+` and `B`, which the right pod sends.
- **Ask Zwift once a day.** Open the Zwift application, connect the controller,
  keep it connected about thirty seconds, close it. The context is refreshed and
  any other host can read the buttons for the rest of the day.

Since the drop cannot be prevented from this side, the bridge is built to make it
invisible: it reconnects every three seconds until the link is back, rescans if
the address stops answering, and says on screen that the controller needs a
Zwift refresh when a link dies inside two minutes. That policy is the one
[`pizero_bikecomputer`](https://github.com/hishizuka/pizero_bikecomputer) uses
against the same pod, and it writes no keepalive at all.

The two open sources disagree on the opening frame, and the difference is small
enough to be worth recording: `zwiftboard` (MIT) sends `RideOn 02 03`, which is
exactly what this unit answers when it grants a plain session
(`52 69 64 65 4F 6E 02 03 C8 00 …`), while `pizero_bikecomputer` sends a bare
`RideOn` then `FF 04 00`. The bridge now asks in the unit's own words and keeps
the rest of the activation as its fallback.

### The two frames this bridge was missing

[`clickbridge`](https://github.com/jasasonc/clickbridge) (MIT, Linux) rides with
no Zwift application installed and reports sessions lasting a whole ride, so its
sequence is the one to copy. It writes:

1. `RideOn 02 03` — the opening this bridge already sent;
2. `FF 04 00`, 300 ms later, on the same write characteristic — **missing here
   until 2026-11-12**. The opening is not finished at the marker: without this
   frame the pod holds for 57 to 62 s and then stops, whatever else is written.
3. `0x18` — a reset — when the pod announces it stopped talking. It announces it
   itself, on the reply channel, with `FF 05 00 EA 05` or `FF 05 00 FA 05`, while
   the link is still up. That announcement is the last moment a restart can be
   sent: once the link is gone the pod is asleep and refuses every connection,
   which is why a rider used to need a button press mid-ride. The unit reboots,
   advertises again, and accepts a new session.

A keepalive is therefore not needed and a second `RideOn` is worse than nothing:
it looks like a fresh handshake to a pod that is already open. The period the
watchdog asks for now carries `FF 04 00` instead.

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
