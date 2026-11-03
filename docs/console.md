# Driving a bridge from a browser

A page cannot open a listening socket, cannot announce a service over mDNS, and cannot act as a Bluetooth peripheral. A browser can therefore never be the bridge a training application discovers. What it can do is the opposite: dial the bridge running on the machine where that application runs, and drive it.

That is the console. It is the only route that also works on an iPhone, where no browser exposes Web Bluetooth: the buttons on the page travel over a WebSocket, and the bridge publishes them exactly as it publishes a controller press.

```
phone or laptop browser          bridge (Windows, macOS, Linux, Android)
┌───────────────────────┐        ┌──────────────────────────────────────┐
│ openzclick web page   │  ws    │ console relay   :47124 /console      │
│ controller over Web   │───────▶│        │                             │
│ Bluetooth, or buttons │◀───────│        ▼                             │
│ and gears on screen   │  state │ gear engine ──▶ mDNS + TCP :47123    │
└───────────────────────┘        └──────────────┬───────────────────────┘
                                                │ OpenBikeControl frames
                                                ▼
                                        training application
```

## On the bridge

Start the publication on the Target screen. The card **Browser console** then shows a QR code, the address to open and the four letter code:

```
ws://192.168.1.24:47124/console?token=abcd
```

Scanning the QR with a phone opens the published page with the bridge and the code in the URL (`?bridge=192.168.1.24:47124&code=abcd`), and the page connects on its own: nothing is typed. Typing the address and the code by hand still works, for a desktop browser or a phone without a camera.

Three rules make that code the only thing to protect:

- it is generated at every start, from an alphabet without `0`/`O` and `1`/`I`, because it is read on a screen and typed on a phone;
- a console that presents a wrong code is refused before the upgrade, with no hint about the expected one;
- the relay closes with the publication: stopping the bridge also disconnects every console.

The relay listens on `47124`, next to the TCP port `47123` the application uses. It carries only what the interface shows: `{"action":"shiftUp"}` in one direction, `{"type":"state","gearIndex":9,...}` in the other.

## On the page

Open the published page, go to **Target**, enter the address and the code (or scan the QR code of the bridge). The address may be a bare IP (`192.168.1.24`), an IP with a port (`192.168.1.24:47124`) or a full `ws://` URL, because a rider copies whatever the bridge shows.

Once connected:

- the buttons of the page reach the bridge, which shifts its gear and tells every console where it landed;
- the gear the page displays follows the bridge, so a console left open on a shelf never drifts from the real state;
- the controller paired by the page over Web Bluetooth is another input of the console: its presses take the same path.

## Checking the link without a controller

```bash
cd transports
dart run tool/console_bridge.dart 47124 abcd 10
```

The tool starts the relay alone, keeps a gear engine and prints every action a page sends. The optional third argument makes it shift up every ten seconds and publish the new state, which is how the other direction is checked: a page left open must follow the gear without being touched.
