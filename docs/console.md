# Driving a bridge from a phone

A phone cannot open a listening socket, cannot announce a service over mDNS, and cannot act as a Bluetooth peripheral. It can therefore never be the bridge a training application discovers. What it can do is the opposite: dial the bridge running on the machine where that application runs, and drive it.

That is the console. The buttons on the page travel over a WebSocket, and the bridge publishes them exactly as it publishes a controller press. It works on an iPhone as on any other phone: it needs a browser, nothing else.

```
phone browser                   bridge (Windows, macOS, Linux, Android)
┌───────────────────────┐        ┌──────────────────────────────────────┐
│ console served by the │  ws    │ console relay   :47124 /console      │
│ bridge                │───────▶│        │                             │
│ buttons and gear      │◀───────│        ▼                             │
│ on screen             │  state │ gear engine ──▶ mDNS + TCP :47123    │
└───────────────────────┘        └──────────────┬───────────────────────┘
                                                │ OpenBikeControl frames
                                                ▼
                                        training application
```

## On the bridge

Start the publication on the Network screen. The card **Phone console** then shows a QR code, the address to open and the four letter code:

```
http://192.168.1.24:47124/?token=abcd
```

Scanning the QR with a phone opens that address, and the page connects on its own: nothing is typed. Typing `192.168.1.24:47124` in any browser also works, and the page then asks for the code.

### Why the bridge serves the page itself

The bridge answers `GET /` on its relay port with the console document. It was not the first design: the QR code used to point at the hosted page with the bridge address in a query parameter (`?bridge=...&code=...`). That could never work from a phone, and the failure said nothing useful.

A published page is served over `https://`. A browser refuses to open a `ws://` socket from an `https://` document: that is the mixed content rule, and it fires before the bridge sees a single byte. The code was correct, the bridge was running, and the only feedback was *"the bridge refused the connection: check the address and the code"* — which sent the rider to check a code that was right.

Serving the document from the bridge removes the rule at its root: the page and the socket share an origin, a host and a port, so nothing is mixed. It also means the address a phone opens is the one the bridge already knows.

The page the bridge serves is deliberately minimal: the gear, two shift buttons and the link state. It has no controller scanning, and does not need one: the bridge has Bluetooth, and it is the bridge that pairs the controller.

Three rules make that code the only thing to protect:

- it is generated at every start, from an alphabet without `0`/`O` and `1`/`I`, because it is read on a screen and typed on a phone;
- a console that presents a wrong code is refused before the upgrade, with no hint about the expected one;
- the relay closes with the publication: stopping the bridge also disconnects every console.

The relay listens on `47124`, next to the TCP port `47123` the application uses. It carries only what the interface shows: `{"action":"shiftUp"}` in one direction, `{"type":"state","gearIndex":9,...}` in the other.

## On the phone

Open the address the bridge shows, or scan its QR code. The console it serves carries the gear, two shift buttons and the link state, and nothing else: it is deliberately one file with no dependency and no build step, because a phone on a home network may have no internet at all and a page that needs the network to draw two buttons fails exactly when it is needed.

The address may be typed by hand (`192.168.1.24:47124`); the code then has to be typed too, and the address may be a bare IP, an IP with a port or a full `ws://` URL, because a rider copies whatever the bridge shows.

Once connected:

- the buttons of the page reach the bridge, which shifts its gear and tells every console where it landed;
- the gear the page displays follows the bridge, so a console left open on a shelf never drifts from the real state;
- the controller stays paired with the bridge, so its presses and the page's take the same path.

## Checking the link without a controller

```bash
cd transports
dart run tool/console_bridge.dart 47124 abcd 10
```

The tool starts the relay alone, keeps a gear engine and prints every action a page sends. The optional third argument makes it shift up every ten seconds and publish the new state, which is how the other direction is checked: a page left open must follow the gear without being touched.
