from __future__ import annotations

import binascii
import struct
import zlib
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]
OUTPUT_PATH = REPO_ROOT / "tools" / "qa" / "fixtures" / "compression_probe.png"
WIDTH = 32
HEIGHT = 32


def chunk(kind: bytes, payload: bytes) -> bytes:
    body = kind + payload
    return (
        struct.pack(">I", len(payload))
        + body
        + struct.pack(">I", binascii.crc32(body) & 0xFFFFFFFF)
    )


def build_png() -> bytes:
    rows = bytearray()
    for y in range(HEIGHT):
        rows.append(0)
        for x in range(WIDTH):
            rows.extend(
                (
                    int(255 * x / (WIDTH - 1)),
                    int(255 * y / (HEIGHT - 1)),
                    160 if (x + y) % 2 == 0 else 48,
                    255,
                )
            )
    header = struct.pack(">IIBBBBB", WIDTH, HEIGHT, 8, 6, 0, 0, 0)
    return (
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", header)
        + chunk(b"IDAT", zlib.compress(bytes(rows), level=9))
        + chunk(b"IEND", b"")
    )


def main() -> int:
    OUTPUT_PATH.parent.mkdir(parents=True, exist_ok=True)
    expected = build_png()
    if OUTPUT_PATH.is_file() and OUTPUT_PATH.read_bytes() == expected:
        print(f"[texture-probe] unchanged {OUTPUT_PATH}")
        return 0
    OUTPUT_PATH.write_bytes(expected)
    print(f"[texture-probe] wrote {OUTPUT_PATH}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
