from __future__ import annotations

import argparse
from pathlib import Path

from PIL import Image, ImageDraw


SIZES = (144, 180, 512)
BACKGROUND = "#080b14"
NIGHT = "#121a2b"
BRASS = "#d7a84c"
BONE = "#f3e5c3"
EMBER = "#b9453f"


def render_icon(size: int) -> Image.Image:
    image = Image.new("RGBA", (size, size), BACKGROUND)
    draw = ImageDraw.Draw(image)
    scale = size / 512.0

    def box(values: tuple[int, int, int, int]) -> tuple[int, int, int, int]:
        return tuple(round(value * scale) for value in values)

    draw.ellipse(box((56, 42, 456, 442)), fill=NIGHT)
    draw.polygon(
        [
            (round(248 * scale), round(250 * scale)),
            (round(486 * scale), round(146 * scale)),
            (round(486 * scale), round(354 * scale)),
        ],
        fill=BRASS,
    )
    draw.rounded_rectangle(
        box((70, 288, 356, 386)),
        radius=round(24 * scale),
        fill=BONE,
    )
    draw.rounded_rectangle(
        box((112, 226, 280, 322)),
        radius=round(20 * scale),
        fill=EMBER,
    )
    draw.rectangle(box((142, 190, 250, 244)), fill=BONE)
    draw.rectangle(box((176, 134, 216, 202)), fill=BRASS)
    draw.ellipse(box((112, 354, 184, 426)), fill=BACKGROUND)
    draw.ellipse(box((262, 354, 334, 426)), fill=BACKGROUND)
    draw.ellipse(box((132, 374, 164, 406)), fill=BRASS)
    draw.ellipse(box((282, 374, 314, 406)), fill=BRASS)
    draw.ellipse(box((254, 248, 316, 310)), fill=BRASS)
    draw.ellipse(box((268, 262, 302, 296)), fill=BONE)
    return image


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Generate deterministic Lantern Line PWA icons."
    )
    parser.add_argument(
        "--output",
        type=Path,
        default=Path("assets/web"),
        help="Output directory relative to the repository root.",
    )
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    for size in SIZES:
        render_icon(size).save(
            args.output / f"icon-{size}.png",
            format="PNG",
            optimize=True,
        )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
