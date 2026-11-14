"""Writes the update manifest an Isolated Web App installs from.

Chrome fetches this file, reads the version it points at, downloads the bundle
and checks its integrity against the digest here. Getting the digest wrong is
indistinguishable, on the browser's side, from a corrupted download: the install
stops with no useful message. So the value is computed from the exact bytes that
are published, in one place, rather than by hand.

    python3 tools/iwa_manifest.py app.swbn update_manifest.json 1.0.0
"""

import base64
import hashlib
import json
import sys


def main(argv: list[str]) -> int:
    if len(argv) not in (3, 4):
        print("usage: iwa_manifest.py <bundle.swbn> <manifest.json> [version]",
              file=sys.stderr)
        return 2
    bundle_path, manifest_path = argv[1], argv[2]
    version = argv[3] if len(argv) == 4 else "1.0.0"

    data = open(bundle_path, "rb").read()
    if not data:
        print(f"{bundle_path} is empty", file=sys.stderr)
        return 1

    digest = base64.b64encode(hashlib.sha256(data).digest()).decode()
    manifest = {
        "versions": [
            {
                "version": version,
                "src": bundle_path.rsplit("/", 1)[-1],
                "integrity": f"sha256-{digest}",
            }
        ]
    }
    with open(manifest_path, "w", encoding="utf-8") as handle:
        json.dump(manifest, handle, indent=1)
        handle.write("\n")

    print(f"{len(data)} bytes, sha256-{digest}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
