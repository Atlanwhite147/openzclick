# Everything on one Android phone

openzclick and MyWhoosh on the same phone, the pod connected to that phone, and
nothing else in the chain. Android allows this where iOS does not: an application
may announce a service on the local network without asking Apple for anything, and
MyWhoosh implements the OpenBikeControl protocol natively since 5.7.0.

## What the phone does

```
Zwift Click ──BLE──▶ openzclick ──OpenBikeControl/TCP──▶ MyWhoosh
                       (this app)      47123, on this phone
```

The phone is both the Bluetooth central and the OpenBikeControl device. The
training application finds the announcement the way it would find a bridge on the
network — it does not know the two are the same phone.

## Steps

1. Install the APK from the `latest` release
   (`app-release.apk`). Android will ask for the Bluetooth permissions on first
   run; the scan needs them, and nothing else does.
2. Open openzclick, **Controllers**, press a button on the pod, then **Connect**.
   The row also names which pod it is: `right pod (+)` or `left pod (arrows)`.
3. Open the **Network** tab and switch the publication on. The name shown
   (`openzclick`) is what MyWhoosh will list.
4. Open MyWhoosh, go to the device connection screen and tap the
   **OpenBikeControl** icon in the top right. Answer **Yes** to the popup.
5. Ride. The pod's buttons now shift in MyWhoosh.

A notification stays in the shade while this works: *openzclick is holding your
pod*. That notification is not decoration — see below.

## Why the notification exists

Android suspends an application as soon as another one is in front, and a
suspended application loses both its Bluetooth link and its socket. Riding means
openzclick behind MyWhoosh, so the link is owned by a **foreground service**,
which is the one state Android does not suspend. Stopping the notification stops
the link; the app stops the service by itself when the pod is released.

## The pod's minute

A Click v2 closes its session 57 to 62 s after it opens, whatever is written to
it. The app therefore writes a reset frame (`0x18`) every 50 s: the pod reboots,
re-advertises and the session reopens in about two seconds, with no press from the
rider. Expect a two-second hole in the buttons once a minute, and a brief blink of
the pod's LED at the same moment. `docs/controllers.md` has the measurements.

## When MyWhoosh does not see the phone

- **Same network.** The phone must be on Wi-Fi; the announcement does not travel
  over mobile data.
- **No VPN.** A VPN on the phone takes the multicast traffic away from the Wi-Fi
  interface, and the announcement is multicast.
- **The publication must be on.** The Network tab shows the address and port it
  is serving on; if it shows an error, that error is the reason MyWhoosh sees
  nothing.
- **MyWhoosh's own popup.** The OpenBikeControl icon has to be tapped and
  confirmed; without that confirmation MyWhoosh ignores every announcement, which
  is deliberate on its side.

## The alternative, when the network is not wanted

Android also allows **tap injection**: an accessibility service taps the on-screen
gear controls of the training application. It needs no network at all and no
MyWhoosh integration, but it depends on where those controls sit on screen, so the
tap positions are configured per application. The Network tab offers both; the
OpenBikeControl route is the one that follows the protocol rather than the layout.
