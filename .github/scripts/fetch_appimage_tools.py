#!/usr/bin/env python3
"""Download fixed upstream AppImage tools and verify their SHA-256 digests."""

import argparse
import hashlib
from pathlib import Path
import urllib.request


DIGESTS = {
    "x86_64": (
        "c20cd71e3a4e3b80c3483cef793cda3f4e990aca14014d23c544ca3ce1270b4d",
        "ed4ce84f0d9caff66f50bcca6ff6f35aae54ce8135408b3fa33abfc3cb384eb0",
        "2fca8b443c92510f1483a883f60061ad09b46b978b2631c807cd873a47ec260d",
    ),
    "aarch64": (
        "620095110d693282b8ebeb244a95b5e911cf8f65f76c88b4b47d16ae6346fcff",
        "f0837e7448a0c1e4e650a93bb3e85802546e60654ef287576f46c71c126a9158",
        "00cbdfcf917cc6c0ff6d3347d59e0ca1f7f45a6df1a428a0d6d8a78664d87444",
    ),
}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--architecture", choices=DIGESTS, required=True)
    parser.add_argument("--output", type=Path, required=True)
    arguments = parser.parse_args()
    architecture = arguments.architecture
    digests = DIGESTS[architecture]
    assets = [
        ("linuxdeploy.AppImage", f"https://github.com/linuxdeploy/linuxdeploy/releases/download/1-alpha-20251107-1/linuxdeploy-{architecture}.AppImage", digests[0]),
        ("appimagetool.AppImage", f"https://github.com/AppImage/appimagetool/releases/download/1.9.1/appimagetool-{architecture}.AppImage", digests[1]),
        ("runtime", f"https://github.com/AppImage/type2-runtime/releases/download/20251108/runtime-{architecture}", digests[2]),
        ("linuxdeploy-plugin-gtk.sh", "https://raw.githubusercontent.com/linuxdeploy/linuxdeploy-plugin-gtk/7a3fbc31a9e5075073ff8790f26effbac5f84453/linuxdeploy-plugin-gtk.sh", "b0f4cbc684a0103a9651f0955b635eaea0096b3a66c0f5a2c2aa337960375171"),
    ]
    arguments.output.mkdir(parents=True, exist_ok=True)
    for name, url, expected in assets:
        with urllib.request.urlopen(url, timeout=120) as response:
            content = response.read()
        actual = hashlib.sha256(content).hexdigest()
        if actual != expected:
            raise SystemExit(f"SHA-256 mismatch for {name}: expected {expected}, received {actual}")
        destination = arguments.output / name
        destination.write_bytes(content)
        destination.chmod(0o755)
        print(f"Verified {name}: {actual}")


if __name__ == "__main__":
    main()
