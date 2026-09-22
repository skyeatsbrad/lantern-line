from __future__ import annotations

import hashlib
import json
import math
import random
import struct
import zlib
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "assets" / "generated" / "visual"
SEED = 0x1A17E2


def _chunk(kind: bytes, data: bytes) -> bytes:
    return (
        struct.pack(">I", len(data))
        + kind
        + data
        + struct.pack(">I", zlib.crc32(kind + data) & 0xFFFFFFFF)
    )


def write_png(
    path: Path,
    width: int,
    height: int,
    pixel_fn,
) -> None:
    rows = bytearray()
    for y in range(height):
        rows.append(0)
        for x in range(width):
            rows.extend(pixel_fn(x, y))
    png = bytearray(b"\x89PNG\r\n\x1a\n")
    png.extend(_chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0)))
    png.extend(_chunk(b"IDAT", zlib.compress(bytes(rows), 9)))
    png.extend(_chunk(b"IEND", b""))
    path.write_bytes(png)


def byte(value: float) -> int:
    return max(0, min(255, round(value * 255.0)))


def radial_pixel(width: int, height: int, power: float):
    def pixel(x: int, y: int) -> bytes:
        nx = (x + 0.5 - width * 0.5) / (width * 0.5)
        ny = (y + 0.5 - height * 0.5) / (height * 0.5)
        distance = min(1.0, math.sqrt(nx * nx + ny * ny))
        alpha = max(0.0, 1.0 - distance) ** power
        return bytes((255, 255, 255, byte(alpha)))

    return pixel


def headlight_pixel(width: int, height: int):
    def pixel(x: int, y: int) -> bytes:
        tx = x / max(1, width - 1)
        ny = abs((y + 0.5 - height * 0.5) / (height * 0.5))
        half_width = 0.08 + tx * 0.92
        edge = min(1.0, ny / max(0.001, half_width))
        lateral = max(0.0, 1.0 - edge * edge)
        forward = (1.0 - tx) ** 0.55
        alpha = lateral * forward
        return bytes((255, 255, 255, byte(alpha)))

    return pixel


def spark_pixel(width: int, height: int):
    def pixel(x: int, y: int) -> bytes:
        nx = abs((x + 0.5 - width * 0.5) / (width * 0.5))
        ny = abs((y + 0.5 - height * 0.5) / (height * 0.5))
        alpha = max(0.0, 1.0 - nx * 0.7 - ny * 1.7) ** 1.4
        return bytes((255, 255, 255, byte(alpha)))

    return pixel


def grain_pixel(width: int, height: int):
    rng = random.Random(SEED)
    values = [
        rng.random() * 0.55 + rng.random() * 0.25
        for _ in range(width * height)
    ]

    def pixel(x: int, y: int) -> bytes:
        value = values[y * width + x]
        alpha = 0.025 + value * 0.09
        warm = 0.86 + value * 0.14
        return bytes((byte(warm), byte(warm * 0.96), byte(warm * 0.84), byte(alpha)))

    return pixel


def main() -> None:
    OUTPUT.mkdir(parents=True, exist_ok=True)
    specs = [
        ("soft_particle.png", 64, 64, radial_pixel(64, 64, 1.8)),
        ("light_radial.png", 128, 128, radial_pixel(128, 128, 1.35)),
        ("headlight_falloff.png", 256, 128, headlight_pixel(256, 128)),
        ("spark.png", 32, 32, spark_pixel(32, 32)),
        ("grain.png", 128, 128, grain_pixel(128, 128)),
    ]
    for filename, width, height, pixel_fn in specs:
        write_png(OUTPUT / filename, width, height, pixel_fn)

    manifest = {
        "generator": Path(__file__).name,
        "seed": SEED,
        "files": {
            path.name: {
                "bytes": path.stat().st_size,
                "sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
            }
            for path in sorted(OUTPUT.glob("*.png"))
        },
    }
    (OUTPUT / "manifest.json").write_text(
        json.dumps(manifest, indent=2) + "\n",
        encoding="utf-8",
    )


if __name__ == "__main__":
    main()

