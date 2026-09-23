from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any

from PIL import Image, ImageDraw, ImageFont


BACKGROUND = "#080b14"
WORLD = "#111827"
TOP = "#26364d"
LENS = "#9a6b32"
ACTION = "#8b3a3a"
POWER = "#315f52"
SAFE = "#d7a84c"
TEXT = "#f3e5c3"
MUTED = "#aab4c3"


def font(path: Path, size: int) -> ImageFont.FreeTypeFont:
    return ImageFont.truetype(str(path), size=size)


def rect_tuple(record: dict[str, float]) -> tuple[int, int, int, int]:
    left = round(record["x"])
    top = round(record["y"])
    return (
        left,
        top,
        round(record["x"] + record["width"]),
        round(record["y"] + record["height"]),
    )


def region_fill(text: str) -> str:
    if text.startswith(("STD", "HEA", "PAL")):
        return LENS
    if text.startswith(("FOCUS", "SALVO", "FIELD", "HOLD DETACH")):
        return ACTION
    if text.startswith(("ENG", "LGT", "DEF", "REP")):
        return POWER
    return TOP


def centered_text(
    draw: ImageDraw.ImageDraw,
    rect: tuple[int, int, int, int],
    text: str,
    text_font: ImageFont.FreeTypeFont,
    fill: str,
) -> None:
    bounds = draw.textbbox((0, 0), text, font=text_font)
    width = bounds[2] - bounds[0]
    height = bounds[3] - bounds[1]
    draw.text(
        (
            rect[0] + (rect[2] - rect[0] - width) / 2,
            rect[1] + (rect[3] - rect[1] - height) / 2 - bounds[1],
        ),
        text,
        fill=fill,
        font=text_font,
    )


def validate_layout(layout: dict[str, Any]) -> None:
    checks = layout["checks"]
    failures = {
        key: value
        for key, value in checks.items()
        if isinstance(value, list) and value
    }
    if failures:
        raise RuntimeError(
            f"Live HUD layout failed at {layout['scale']}: {failures}"
        )
    if float(layout["metrics"]["clear_ratio"]) < 0.55:
        raise RuntimeError(
            f"Live HUD clear ratio fell below 55% at {layout['scale']}"
        )


def render_layout(
    layout: dict[str, Any],
    viewport: dict[str, int],
    font_path: Path,
) -> Image.Image:
    width = int(viewport["width"])
    height = int(viewport["height"])
    image = Image.new("RGB", (width, height), BACKGROUND)
    draw = ImageDraw.Draw(image)
    label_font = font(font_path, 10)
    small_font = font(font_path, 8)
    title_font = font(font_path, 13)

    metrics = layout["metrics"]
    comfort = rect_tuple(metrics["comfort"])
    top_bottom = round(metrics["top_strip_bottom"])
    bottom_top = round(metrics["bottom_row_top"])
    spacing = round(metrics["spacing"]["x"])
    regions = layout["regions"]
    lens_regions = [
        rect_tuple(region["rect"])
        for region in regions
        if region["text"].startswith(("STD", "HEA", "PAL"))
    ]
    action_regions = [
        rect_tuple(region["rect"])
        for region in regions
        if region["text"].startswith(("FOCUS", "SALVO", "FIELD", "HOLD DETACH"))
    ]
    clear_left = max(rect[2] for rect in lens_regions) + spacing
    clear_right = min(rect[0] for rect in action_regions) - spacing
    clear_rect = (clear_left, top_bottom, clear_right, bottom_top)

    draw.rectangle(clear_rect, fill=WORLD, outline=SAFE, width=2)
    draw.text(
        (clear_rect[0] + 10, clear_rect[1] + 9),
        "UNOBSTRUCTED WORLD / AIM SURFACE",
        fill=TEXT,
        font=title_font,
    )
    draw.text(
        (clear_rect[0] + 10, clear_rect[1] + 30),
        (
            f"{metrics['clear_height']:.0f}px tall | "
            f"{metrics['clear_ratio']:.1%} of screen height"
        ),
        fill=MUTED,
        font=label_font,
    )
    draw.rounded_rectangle(
        (comfort[0], comfort[1], comfort[2], top_bottom),
        radius=6,
        fill=TOP,
        outline=SAFE,
        width=1,
    )
    draw.text(
        (comfort[0] + 6, comfort[1] + 4),
        "TOP STATUS STRIP",
        fill=MUTED,
        font=small_font,
    )

    for region in regions:
        rect = rect_tuple(region["rect"])
        fill = region_fill(region["text"])
        draw.rounded_rectangle(rect, radius=6, fill=fill, outline=TEXT, width=1)
        short_text = region["text"].replace(" READY", "").replace(
            " LOCKED", ""
        )
        centered_text(draw, rect, short_text, label_font, TEXT)
        dimensions = (
            f"{region['rect']['width']:.0f}x"
            f"{region['rect']['height']:.0f}"
        )
        draw.text(
            (rect[0] + 3, rect[3] - 10),
            dimensions,
            fill=MUTED,
            font=small_font,
        )

    draw.rectangle(
        (comfort[0], comfort[1], comfort[2], comfort[3]),
        outline=SAFE,
        width=1,
    )
    scale_percent = round(float(layout["scale"]) * 100)
    draw.text(
        (4, 4),
        (
            f"LIVE GODOT HUD | {scale_percent}% targets | "
            f"{layout['state']} state | no overlap"
        ),
        fill=TEXT,
        font=label_font,
    )
    return image


def render(
    output_dir: Path,
    font_path: Path,
    layout_data_path: Path,
    contract_capture_path: Path,
) -> dict[str, object]:
    output_dir.mkdir(parents=True, exist_ok=True)
    source = json.loads(layout_data_path.read_text(encoding="utf-8"))
    viewport = source["viewport"]
    expected_scales = [1.0, 1.15, 1.3]
    expected_states = ["field", "detach"]
    layouts = source["layouts"]
    actual_layouts = sorted(
        (float(layout["scale"]), str(layout["state"]))
        for layout in layouts
    )
    expected_layouts = sorted(
        (scale, state)
        for scale in expected_scales
        for state in expected_states
    )
    if actual_layouts != expected_layouts:
        raise RuntimeError(
            f"Expected live layouts {expected_layouts}, got {actual_layouts}"
        )

    for scale in (100, 115, 130):
        legacy_path = output_dir / f"touch-hud-hit-regions-844x390-{scale}.png"
        if legacy_path.exists():
            legacy_path.unlink()

    images: dict[tuple[float, str], Image.Image] = {}
    records: list[dict[str, object]] = []
    for layout in sorted(
        layouts,
        key=lambda item: (
            float(item["scale"]),
            expected_states.index(str(item["state"])),
        ),
    ):
        validate_layout(layout)
        image = render_layout(layout, viewport, font_path)
        scale_percent = round(float(layout["scale"]) * 100)
        state = str(layout["state"])
        image_path = (
            output_dir
            / (
                "touch-hud-hit-regions-844x390-"
                f"{scale_percent}-{state}.png"
            )
        )
        image.save(image_path, format="PNG", optimize=True)
        images[(float(layout["scale"]), state)] = image
        records.append(
            {
                "scale": layout["scale"],
                "state": state,
                "clear_world_height_px": layout["metrics"]["clear_height"],
                "clear_world_height_ratio": layout["metrics"]["clear_ratio"],
                "target_px": layout["metrics"]["target"],
                "focus_target_px": layout["metrics"]["focus_target"],
                "detach_target_px": layout["metrics"]["detach_target"],
                "minimum_gap_px": layout["metrics"]["spacing"],
                "checks": layout["checks"],
                "receipt": image_path.as_posix(),
            }
        )

    sheet_gap = 8
    state_sheets: dict[str, str] = {}
    for state in expected_states:
        state_sheet = Image.new(
            "RGB",
            (
                int(viewport["width"]),
                len(expected_scales) * int(viewport["height"])
                + (len(expected_scales) - 1) * sheet_gap,
            ),
            BACKGROUND,
        )
        for row_index, scale in enumerate(expected_scales):
            state_sheet.paste(
                images[(scale, state)],
                (
                    0,
                    row_index * (int(viewport["height"]) + sheet_gap),
                ),
            )
        state_sheet_path = (
            output_dir / f"touch-hud-hit-regions-844x390-{state}.png"
        )
        state_sheet.save(state_sheet_path, format="PNG", optimize=True)
        state_sheets[state] = state_sheet_path.as_posix()

    sheet = Image.new(
        "RGB",
        (
            len(expected_states) * int(viewport["width"])
            + (len(expected_states) - 1) * sheet_gap,
            len(expected_scales) * int(viewport["height"])
            + (len(expected_scales) - 1) * sheet_gap,
        ),
        BACKGROUND,
    )
    for row_index, scale in enumerate(expected_scales):
        for column_index, state in enumerate(expected_states):
            sheet.paste(
                images[(scale, state)],
                (
                    column_index * (int(viewport["width"]) + sheet_gap),
                    row_index * (int(viewport["height"]) + sheet_gap),
                ),
            )
    sheet_path = output_dir / "touch-hud-hit-regions-844x390.png"
    sheet.save(sheet_path, format="PNG", optimize=True)
    contract_capture_path.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(contract_capture_path, format="PNG", optimize=True)

    record: dict[str, object] = {
        "viewport": viewport,
        "source": layout_data_path.as_posix(),
        "live_godot_layout": True,
        "layouts": records,
        "state_sheets": state_sheets,
        "contract_capture": contract_capture_path.as_posix(),
        "receipt": sheet_path.as_posix(),
    }
    json_path = output_dir / "touch-hud-hit-regions-844x390.json"
    json_path.write_text(json.dumps(record, indent=2) + "\n", encoding="utf-8")
    return record


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Render live audited touch HUD hit regions."
    )
    parser.add_argument(
        "--output-dir",
        type=Path,
        default=Path("design/receipts/v0.8-m1"),
    )
    parser.add_argument(
        "--font",
        type=Path,
        default=Path("assets/fonts/AtkinsonHyperlegible-Bold.ttf"),
    )
    parser.add_argument(
        "--layout-data",
        type=Path,
        default=Path(
            "design/receipts/v0.8-m1/touch-hud-live-layouts.json"
        ),
    )
    parser.add_argument(
        "--contract-capture",
        type=Path,
        default=Path("design/captures/v0.8-touch-hud-844x390.png"),
    )
    args = parser.parse_args()
    record = render(
        args.output_dir,
        args.font,
        args.layout_data,
        args.contract_capture,
    )
    print(json.dumps(record, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
