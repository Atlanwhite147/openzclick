# The bridge inside a browser page

An Isolated Web App (IWA) is a page Chrome treats as an installed application and
grants sockets to. It can therefore do what a normal page cannot: open a TCP
server and announce a service over mDNS. This is the route that makes the browser
edition a full bridge rather than only a console of a native one.

## What the page does

`WebBridgePublisher` answers the same question as `NetworkPublisher`, with the same
wire format:

| Step | Native bridge | Page in an IWA |
|---|---|---|
| Listen | `ServerSocket` on 47123 | `TCPServerSocket('0.0.0.0', 47123)` |
| Announce | UDP responder on 224.0.0.251:5353 | sender to 224.0.0.251:5353, repeated every 2 s |
| Answer queries | yes | **no**: a page may send to a group but not bind to it |
| Address record | interface list | ICE host candidate, via `RTCPeerConnection` |
| Frame | `ButtonStateMessage`, press then release at 60 ms | identical |

The DNS-SD bytes live in `core/lib/src/protocol/dns_sd.dart` (`DnsPacket`,
`DnsReader`) so both hosts cannot drift; the native responder was left untouched.

Because the page never answers a query, the announcement is repeated: a cache
that missed the first packet picks up the next one, and a goodbye (`TTL 0`, no A
record) is sent on stop so the instance disappears at once.

## Why it cannot ship as a plain page

A normal tab has no `TCPServerSocket`. Chrome grants it only to an origin that is
an IWA, and an IWA must be a signed Web Bundle served from an `update_manifest`
with developer mode enabled, or installed from a store. `Capabilities.canPublish`
reads exactly that: `!isWeb || directSocketsAvailable`, so a normal page still
falls back to the console of a bridge running elsewhere.

Mobile browsers have no Direct Sockets at all: the phone route stays the console
one (`docs/console.md`).

## Building and installing one

```bash
# 1. the page
cd app
flutter build web --release --base-href "/" --no-web-resources-cdn

# 2. the signed bundle (the key names the app: keep it, the id derives from it)
npx wbn-dump-id -k appkey.pem                       # the bundle id
npx wbn -d build/web -b "isolated-app://<id>/" -o app.wbn
npx wbn-sign sign app.wbn appkey.pem -o app.swbn

# 3. the update manifest, with the integrity of the bundle
python3 - <<'EOF'
import base64, hashlib, json
data = open('app.swbn', 'rb').read()
digest = base64.b64encode(hashlib.sha256(data).digest()).decode()
json.dump({"versions": [{"version": "1.0.0", "src": "app.swbn",
                         "integrity": "sha256-" + digest}]},
          open('update_manifest.json', 'w'), indent=1)
EOF
```

`--no-web-resources-cdn` is not optional: the default build loads CanvasKit from
`gstatic.com`, which the IWA's content security policy refuses, and the page then
shows nothing.

The manifest carries the permissions the bridge needs:

```json
"permissions_policy": {
  "cross-origin-isolated": ["self"],
  "direct-sockets": ["self"],
  "local-network": ["self"],
  "loopback-network": ["self"],
  "direct-sockets-multicast": ["self"]
}
```

It lives at `app/web/.well-known/manifest.webmanifest`, so `flutter build web`
copies it into the bundle.

Install it from `chrome://web-app-internals` → *Install IWA from Update Manifest*.
The page is then served from `isolated-app://<id>/`, where
`self.crossOriginIsolated` is `true` and `typeof TCPServerSocket === 'function'`.

## Platform limits worth knowing

- A page **sends** to 224.0.0.251 but cannot **bind** to it: queries from an
  application go unanswered, so discovery relies on the repeated announcement.
- `readable`/`writable` are locked streams: one writer per socket. Two writes
  issued without awaiting the first drop the second, which is why `send` chains
  them and returns a `Future`.
- Closing a socket's writer closes the connection, so the writer is opened once
  and kept; a writer per frame truncated a shift to its press alone.
- `UDPSocket` writes carry data only: adding `remoteAddress` to a connected
  socket is refused, silently for an unawaited future.
- The 42 MB bundle is the Flutter web engine, not the application code.

## Verified end to end

On Chrome 145, an installed bundle, a Python socket playing MyWhoosh:

```
1. port TCP ouvert par la page: True
2. mDNS: annonce de 192.168.1.240, 341 octets, service trouvé à l'offset 13
   port 47123 présent dans le paquet: True
3. client TCP connecté (rôle MyWhoosh)
4. braquet avant/après clic: ['TrainerGear 6 / 12 Road 12 gears'] -> ['TrainerGear 7 / 12 Road 12 gears']
5. trames OpenBikeControl reçues: ['01 01 01 01 01 00']
```

The last line is the shift: button `0x01` pressed (`01`) then released (`00`).
