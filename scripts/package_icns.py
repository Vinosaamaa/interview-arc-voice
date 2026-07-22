#!/usr/bin/env python3
"""Package modern PNG icon representations into an Apple ICNS container."""

from pathlib import Path
import struct
import sys


def chunk(kind: bytes, payload: bytes) -> bytes:
    return kind + struct.pack(">I", len(payload) + 8) + payload


def main() -> None:
    icon_dir = Path(sys.argv[1])
    destination = Path(sys.argv[2])
    representations = (
        (b"icp4", "icon_16x16.png"),
        (b"icp5", "icon_32x32.png"),
        (b"icp6", "icon_64x64.png"),
        (b"ic07", "icon_128x128.png"),
        (b"ic08", "icon_256x256.png"),
        (b"ic09", "icon_512x512.png"),
        (b"ic10", "icon_1024x1024.png"),
    )
    body = b"".join(chunk(kind, (icon_dir / filename).read_bytes()) for kind, filename in representations)
    destination.write_bytes(b"icns" + struct.pack(">I", len(body) + 8) + body)


if __name__ == "__main__":
    main()
