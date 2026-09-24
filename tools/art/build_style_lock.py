from __future__ import annotations

import argparse
import hashlib
import json
import os
import shutil
import subprocess
import tempfile
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

import numpy as np
from PIL import Image, ImageChops, ImageDraw, ImageEnhance, ImageFilter, ImageFont


REPO_ROOT = Path(__file__).resolve().parents[2]
DEFAULT_CONFIG = (
    REPO_ROOT / "assets" / "source" / "style" / "m3a_style_lock.json"
)
DEFAULT_WORK_ROOT = REPO_ROOT / "build" / "m3a-style-lock"
DEFAULT_CANONICAL_WORK_ROOT = (
    REPO_ROOT / "build" / "m3a-style-lock-canonical"
)
DEFAULT_REVIEW_ROOT = (
    REPO_ROOT / "design" / "receipts" / "v0.8-m3a" / "media"
)
DEFAULT_CANONICAL_REVIEW_ROOT = (
    REPO_ROOT
    / "design"
    / "receipts"
    / "v0.8-m3a"
    / "canonical-media"
)
DEFAULT_RECEIPT = (
    REPO_ROOT / "design" / "receipts" / "v0.8-m3a" / "style-lock.json"
)
DEFAULT_CANONICAL_RECEIPT = (
    REPO_ROOT
    / "design"
    / "receipts"
    / "v0.8-m3a"
    / "canonical-style-lock.json"
)
BLENDER_SCRIPT = REPO_ROOT / "tools" / "art" / "style_lock_blender.py"
REGULAR_FONT = (
    REPO_ROOT / "assets" / "fonts" / "AtkinsonHyperlegible-Regular.ttf"
)
BOLD_FONT = REPO_ROOT / "assets" / "fonts" / "AtkinsonHyperlegible-Bold.ttf"
DISPLAY_FONT = REPO_ROOT / "assets" / "fonts" / "Bitter-Variable.ttf"
PREVIEW_REPLAY_MAX_CHANGED_PIXELS = 8
PREVIEW_REPLAY_MAX_CHANGED_RATIO = 0.00005
PREVIEW_REPLAY_MAX_CHANNEL_DELTA = 1
PREVIEW_REPLAY_MAX_MEAN_ABS_DELTA = 0.00001


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--config", type=Path, default=DEFAULT_CONFIG)
    parser.add_argument("--blender", type=Path)
    parser.add_argument("--work-root", type=Path)
    parser.add_argument("--review-root", type=Path)
    parser.add_argument("--receipt", type=Path)
    parser.add_argument(
        "--engine",
        choices=["preview", "canonical"],
        default="preview",
    )
    parser.add_argument("--treatment", action="append", default=[])
    parser.add_argument("--skip-blender", action="store_true")
    parser.add_argument("--clean", action="store_true")
    parser.add_argument("--verify-replay", action="store_true")
    return parser.parse_args()


def sha256_bytes(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def pixel_sha256(path: Path) -> str:
    image = Image.open(path).convert("RGBA")
    return sha256_bytes(image.tobytes())


def git_head() -> str:
    result = subprocess.run(
        ["git", "rev-parse", "HEAD"],
        cwd=REPO_ROOT,
        check=True,
        capture_output=True,
        text=True,
        encoding="utf-8",
    )
    return result.stdout.strip()


def load_json(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))


def find_blender(explicit: Path | None) -> Path:
    if explicit is not None:
        resolved = explicit.resolve()
        if not resolved.is_file():
            raise FileNotFoundError(resolved)
        return resolved
    receipt = REPO_ROOT / ".tools" / "blender_install_receipt.json"
    if receipt.is_file():
        candidate = Path(load_json(receipt)["executable"])
        if candidate.is_file():
            return candidate
    raise FileNotFoundError(
        "Pinned Blender was not found. Run tools/art/install_blender.ps1."
    )


def paths_overlap(left: Path, right: Path) -> bool:
    return (
        left == right
        or left.is_relative_to(right)
        or right.is_relative_to(left)
    )


def output_paths(
    args: argparse.Namespace,
) -> tuple[Path, Path, Path]:
    if args.engine == "canonical":
        work_root = (
            args.work_root or DEFAULT_CANONICAL_WORK_ROOT
        ).resolve()
        review_root = (
            args.review_root or DEFAULT_CANONICAL_REVIEW_ROOT
        ).resolve()
        receipt_path = (
            args.receipt or DEFAULT_CANONICAL_RECEIPT
        ).resolve()
        protected = (
            DEFAULT_WORK_ROOT.resolve(),
            DEFAULT_REVIEW_ROOT.resolve(),
            DEFAULT_RECEIPT.resolve(),
        )
    else:
        work_root = (args.work_root or DEFAULT_WORK_ROOT).resolve()
        review_root = (args.review_root or DEFAULT_REVIEW_ROOT).resolve()
        receipt_path = (args.receipt or DEFAULT_RECEIPT).resolve()
        protected = (
            DEFAULT_CANONICAL_WORK_ROOT.resolve(),
            DEFAULT_CANONICAL_REVIEW_ROOT.resolve(),
            DEFAULT_CANONICAL_RECEIPT.resolve(),
        )
    selected = {
        "work_root": work_root,
        "review_root": review_root,
        "receipt": receipt_path,
    }
    selected_items = list(selected.items())
    for index, (left_name, left_path) in enumerate(selected_items):
        for right_name, right_path in selected_items[index + 1 :]:
            if paths_overlap(left_path, right_path):
                raise ValueError(
                    f"{args.engine} {left_name} overlaps {right_name}."
                )
    if any(
        paths_overlap(path, protected_path)
        for path in selected.values()
        for protected_path in protected
    ):
        raise ValueError(
            f"{args.engine} output paths overlap the other engine's "
            "protected evidence paths."
        )
    return work_root, review_root, receipt_path


def hex_rgb(value: str) -> tuple[int, int, int]:
    text = value.lstrip("#")
    return tuple(int(text[index : index + 2], 16) for index in (0, 2, 4))


def stable_save(image: Image.Image, path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    image.convert("RGBA").save(
        path,
        format="PNG",
        compress_level=9,
        optimize=False,
    )


def font(path: Path, size: int) -> ImageFont.FreeTypeFont:
    return ImageFont.truetype(str(path), max(7, size))


def outline_mask(image: Image.Image, width: float, high_contrast: bool) -> Image.Image:
    grayscale = image.convert("RGB").convert("L").filter(
        ImageFilter.GaussianBlur(1.15 if high_contrast else 0.85)
    )
    edges = grayscale.filter(ImageFilter.FIND_EDGES)
    edges = ImageEnhance.Contrast(edges).enhance(1.55 if high_contrast else 1.35)
    threshold = 46 if high_contrast else 38
    edges = edges.point(lambda value: 255 if value >= threshold else 0)
    filter_size = max(3, int(round(width / 1.5)) * 2 + 1)
    if filter_size % 2 == 0:
        filter_size += 1
    return edges.filter(ImageFilter.MaxFilter(filter_size))


def add_outline(
    image: Image.Image,
    palette: dict[str, str],
    width: float,
    high_contrast: bool,
) -> Image.Image:
    mask = outline_mask(image, width, high_contrast)
    color = hex_rgb(palette["night_void"])
    alpha = 162 if high_contrast else 132
    layer = Image.new("RGBA", image.size, (*color, alpha))
    layer.putalpha(mask.point(lambda value: int(value * alpha / 255)))
    return Image.alpha_composite(image.convert("RGBA"), layer)


def add_subject_outline(
    image: Image.Image,
    mask_path: Path,
    palette: dict[str, str],
    width: float,
    high_contrast: bool,
) -> Image.Image:
    mask_image = Image.open(mask_path).convert("RGB")
    pixels = np.asarray(mask_image, dtype=np.int16)
    background = np.asarray(hex_rgb(palette["night_void"]), dtype=np.int16)
    difference = np.max(np.abs(pixels - background), axis=2)
    subject = Image.fromarray(
        np.where(difference > 16, 255, 0).astype(np.uint8),
        mode="L",
    )
    filter_size = max(3, int(round(width)) * 2 + 1)
    if filter_size % 2 == 0:
        filter_size += 1
    expanded = subject.filter(ImageFilter.MaxFilter(filter_size))
    ring = ImageChops.subtract(expanded, subject)
    if not high_contrast:
        ring = ring.filter(ImageFilter.GaussianBlur(0.35))
    alpha = 232 if high_contrast else 210
    layer = Image.new(
        "RGBA",
        image.size,
        (*hex_rgb(palette["night_void"]), 0),
    )
    layer.putalpha(ring.point(lambda value: int(value * alpha / 255)))
    return Image.alpha_composite(image.convert("RGBA"), layer)


def add_headlight(
    image: Image.Image,
    palette: dict[str, str],
    treatment: dict[str, Any],
    high_contrast: bool,
    anchor: list[float],
) -> Image.Image:
    width, height = image.size
    origin = (int(width * anchor[0]), int(height * anchor[1]))
    upper = (
        int(width * 1.03),
        max(0, int(origin[1] - height * 0.30)),
    )
    lower = (
        int(width * 1.03),
        min(height, int(origin[1] + height * 0.23)),
    )
    mask = Image.new("L", image.size, 0)
    draw = ImageDraw.Draw(mask)
    draw.polygon([origin, upper, lower], fill=255)
    feather = max(4.0, float(treatment["beam_feather"]) * width / 1280.0)
    mask = mask.filter(ImageFilter.GaussianBlur(feather))
    alpha_scale = float(treatment["beam_alpha"])
    if high_contrast:
        alpha_scale = min(0.52, alpha_scale * 1.18)
    x_coords = np.linspace(0.0, 1.0, width, dtype=np.float32)
    origin_ratio = origin[0] / max(1.0, float(width - 1))
    falloff = np.clip(
        1.0 - (x_coords - origin_ratio) / max(0.05, 1.0 - origin_ratio),
        0.16,
        1.0,
    )
    falloff = np.tile(falloff[None, :], (height, 1))
    mask_array = np.asarray(mask, dtype=np.float32) / 255.0
    alpha_array = np.clip(mask_array * falloff * alpha_scale * 255.0, 0, 255)
    beam = Image.new("RGBA", image.size, (*hex_rgb(palette["ember"]), 0))
    beam.putalpha(Image.fromarray(alpha_array.astype(np.uint8), mode="L"))
    result = Image.alpha_composite(image.convert("RGBA"), beam)
    inner_mask = Image.new("L", image.size, 0)
    inner_draw = ImageDraw.Draw(inner_mask)
    inner_draw.polygon(
        [
            origin,
            (upper[0], max(0, int(origin[1] - height * 0.17))),
            (lower[0], min(height, int(origin[1] + height * 0.13))),
        ],
        fill=190 if high_contrast else 150,
    )
    inner_mask = inner_mask.filter(
        ImageFilter.GaussianBlur(max(3.0, feather * 0.55))
    )
    inner = Image.new("RGBA", image.size, (*hex_rgb(palette["bone"]), 0))
    inner.putalpha(inner_mask.point(lambda value: int(value * 0.28)))
    result = Image.alpha_composite(result, inner)
    bloom = Image.new("RGBA", image.size, (*hex_rgb(palette["bone"]), 0))
    bloom_mask = Image.new("L", image.size, 0)
    bloom_draw = ImageDraw.Draw(bloom_mask)
    bloom_draw.ellipse(
        (
            origin[0] - int(width * 0.012),
            origin[1] - int(height * 0.026),
            origin[0] + int(width * 0.012),
            origin[1] + int(height * 0.026),
        ),
        fill=230 if high_contrast else 190,
    )
    bloom_mask = bloom_mask.filter(
        ImageFilter.GaussianBlur(max(2.0, width * 0.004))
    )
    bloom.putalpha(bloom_mask)
    return Image.alpha_composite(result, bloom)


def add_atmosphere(
    image: Image.Image,
    palette: dict[str, str],
    treatment: dict[str, Any],
    high_contrast: bool,
    seed: int,
    track_anchor: list[float],
) -> Image.Image:
    result = image.convert("RGBA")
    width, height = result.size
    horizon = int(height * track_anchor[1])
    haze = Image.new("L", result.size, 0)
    haze_array = np.zeros((height, width), dtype=np.float32)
    y_values = np.arange(height, dtype=np.float32)
    band = np.exp(
        -((y_values - float(horizon - height * 0.08)) ** 2)
        / max(1.0, 2.0 * (height * 0.15) ** 2)
    )
    strength = 14.0 + float(treatment["background_separation"]) * 28.0
    if high_contrast:
        strength *= 0.72
    haze_array[:] = band[:, None] * strength
    haze = Image.fromarray(
        np.clip(haze_array, 0, 255).astype(np.uint8),
        mode="L",
    ).filter(ImageFilter.GaussianBlur(max(2.0, height * 0.015)))
    haze_layer = Image.new(
        "RGBA",
        result.size,
        (*hex_rgb(palette["cold_signal"]), 0),
    )
    haze_layer.putalpha(haze)
    result = Image.alpha_composite(result, haze_layer)

    rng = np.random.default_rng(seed)
    ash = Image.new("RGBA", result.size, (0, 0, 0, 0))
    draw = ImageDraw.Draw(ash)
    count = max(16, int(width * height / 26000))
    for _ in range(count):
        x = int(rng.uniform(0, width))
        y = int(rng.uniform(height * 0.08, max(height * 0.12, horizon)))
        length = max(1, int(rng.uniform(1.0, 3.2) * width / 1280.0))
        alpha = int(rng.uniform(22, 58) * (0.75 if high_contrast else 1.0))
        draw.line(
            (x, y, x + length, y + max(1, length // 2)),
            fill=(*hex_rgb(palette["bone"]), alpha),
            width=1,
        )
    return Image.alpha_composite(result, ash)


def add_vignette(image: Image.Image, high_contrast: bool) -> Image.Image:
    width, height = image.size
    y, x = np.ogrid[-1.0:1.0:height * 1j, -1.0:1.0:width * 1j]
    radius = np.sqrt(x * x + y * y)
    strength = 0.22 if high_contrast else 0.16
    alpha = np.clip((radius - 0.48) * strength * 255.0, 0, 52)
    layer = Image.new("RGBA", image.size, (0, 0, 0, 0))
    layer.putalpha(Image.fromarray(alpha.astype(np.uint8), mode="L"))
    return Image.alpha_composite(image.convert("RGBA"), layer)


def add_grain(
    image: Image.Image,
    treatment: dict[str, Any],
    seed: int,
) -> Image.Image:
    alpha = float(treatment["grain_alpha"])
    if alpha <= 0.0:
        return image.convert("RGBA")
    rng = np.random.default_rng(seed)
    width, height = image.size
    noise = rng.normal(128.0, 28.0, (height, width)).clip(0, 255).astype(np.uint8)
    layer = Image.fromarray(noise, mode="L").convert("RGBA")
    layer.putalpha(int(alpha * 255.0))
    return Image.alpha_composite(image.convert("RGBA"), layer)


def add_hud(
    image: Image.Image,
    palette: dict[str, str],
    high_contrast: bool,
) -> Image.Image:
    result = image.convert("RGBA")
    width, height = result.size
    scale = min(width / 1280.0, height / 720.0)
    thumbnail_hud = width <= 400
    panel_width = (
        max(112, int(326 * scale))
        if thumbnail_hud
        else max(150, int(326 * scale))
    )
    panel_height = (
        max(40, int(104 * scale))
        if thumbnail_hud
        else max(58, int(104 * scale))
    )
    x0 = max(8, int(18 * scale))
    y0 = max(8, int(16 * scale))
    x1 = x0 + panel_width
    y1 = y0 + panel_height
    overlay = Image.new("RGBA", result.size, (0, 0, 0, 0))
    draw = ImageDraw.Draw(overlay)
    panel_alpha = 246 if high_contrast else 220
    draw.rounded_rectangle(
        (x0, y0, x1, y1),
        radius=max(4, int(8 * scale)),
        fill=(*hex_rgb(palette["coal"]), panel_alpha),
        outline=hex_rgb(
            palette["bone"] if high_contrast else palette["brass"]
        ),
        width=max(1, int((3 if high_contrast else 2) * scale)),
    )
    title_font = font(DISPLAY_FONT, int((14 if thumbnail_hud else 18) * scale))
    body_font = font(BOLD_FONT, int((10 if thumbnail_hud else 13) * scale))
    small_font = font(REGULAR_FONT, int(10 * scale))
    draw.text(
        (x0 + int(14 * scale), y0 + int(8 * scale)),
        "LANTERN LINE",
        font=title_font,
        fill=hex_rgb(palette["bone"]),
    )
    draw.text(
        (
            x0 + int(14 * scale),
            y0 + int((31 if thumbnail_hud else 37) * scale),
        ),
        "FOCUS" if thumbnail_hud else "FOCUS READY",
        font=body_font,
        fill=hex_rgb(palette["ember"]),
    )
    bar_x0 = x0 + int(14 * scale)
    bar_y0 = y0 + int((49 if thumbnail_hud else 60) * scale)
    bar_x1 = x1 - int(14 * scale)
    bar_y1 = bar_y0 + max(5, int(10 * scale))
    draw.rectangle(
        (bar_x0, bar_y0, bar_x1, bar_y1),
        fill=hex_rgb(palette["night_void"]),
        outline=hex_rgb(palette["slate"]),
        width=max(1, int(scale)),
    )
    fill_width = int((bar_x1 - bar_x0) * 0.78)
    draw.rectangle(
        (bar_x0 + 1, bar_y0 + 1, bar_x0 + fill_width, bar_y1 - 1),
        fill=hex_rgb(palette["brass"]),
    )
    if not thumbnail_hud:
        draw.text(
            (bar_x0, bar_y1 + int(3 * scale)),
            "DEFENSE // HEAVY CANNON",
            font=small_font,
            fill=hex_rgb(palette["bone"]),
        )
    return Image.alpha_composite(result, overlay)


def grade_frame(
    raw_path: Path,
    output_path: Path,
    palette: dict[str, str],
    treatment: dict[str, Any],
    variant: str,
    seed: int,
    anchors: dict[str, list[float]],
    subject_mask: Path,
) -> None:
    image = Image.open(raw_path).convert("RGBA")
    high_contrast = variant == "high_contrast"
    image = add_atmosphere(
        image,
        palette,
        treatment,
        high_contrast,
        seed + 113,
        anchors["track"],
    )
    image = add_subject_outline(
        image,
        subject_mask,
        palette,
        float(treatment["silhouette_outline_px"])
        * (1.2 if high_contrast else 1.0),
        high_contrast,
    )
    image = add_outline(
        image,
        palette,
        float(treatment["outline_px"]) * (1.25 if high_contrast else 1.0),
        high_contrast,
    )
    image = add_headlight(
        image,
        palette,
        treatment,
        high_contrast,
        anchors["headlight"],
    )
    image = add_vignette(image, high_contrast)
    image = add_grain(image, treatment, seed)
    image = add_hud(image, palette, high_contrast)
    stable_save(image, output_path)


def resize_frame(source: Path, output: Path, size: list[int]) -> None:
    image = Image.open(source).convert("RGBA")
    resized = image.resize((int(size[0]), int(size[1])), Image.Resampling.LANCZOS)
    stable_save(resized, output)


def normalize_pass(source: Path, output: Path) -> None:
    image = Image.open(source).convert("RGBA")
    stable_save(image, output)


def text_label(
    canvas: Image.Image,
    position: tuple[int, int],
    text: str,
    size: int,
    color: tuple[int, int, int],
    display: bool = False,
) -> None:
    draw = ImageDraw.Draw(canvas)
    draw.text(
        position,
        text,
        font=font(DISPLAY_FONT if display else BOLD_FONT, size),
        fill=color,
    )


def paste_fitted(
    canvas: Image.Image,
    source: Path,
    box: tuple[int, int, int, int],
) -> None:
    image = Image.open(source).convert("RGBA")
    target_width = box[2] - box[0]
    target_height = box[3] - box[1]
    image.thumbnail((target_width, target_height), Image.Resampling.LANCZOS)
    x = box[0] + (target_width - image.width) // 2
    y = box[1] + (target_height - image.height) // 2
    canvas.alpha_composite(image, (x, y))


def treatment_contact_sheet(
    treatment: dict[str, Any],
    output_root: Path,
    palette: dict[str, str],
) -> Path:
    treatment_id = treatment["id"]
    background = (*hex_rgb(palette["night_void"]), 255)
    foreground = hex_rgb(palette["bone"])
    accent = hex_rgb(palette["brass"])
    sheet = Image.new("RGBA", (1920, 1540), background)
    text_label(
        sheet,
        (42, 24),
        f"{treatment['display_name']} // M3A STYLE TREATMENT",
        30,
        foreground,
        True,
    )
    text_label(
        sheet,
        (44, 70),
        (
            f"pitch {treatment['camera_pitch_degrees']} deg  |  "
            f"outline {treatment['outline_px']}/"
            f"{treatment['silhouette_outline_px']} px  |  "
            f"metal {treatment['metallic_scale']:.2f}  |  "
            f"background {treatment['background_separation']:.2f}"
        ),
        18,
        accent,
    )
    boxes = {
        "default_desktop": (40, 112, 980, 642),
        "default_mobile": (1000, 112, 1880, 520),
        "default_compact": (1000, 540, 1640, 900),
        "default_thumbnail": (1660, 540, 1880, 664),
        "hc_desktop": (40, 686, 980, 1216),
        "hc_mobile": (1000, 922, 1880, 1328),
    }
    paths = output_root / treatment_id / "final"
    paste_fitted(sheet, paths / "default" / "desktop.png", boxes["default_desktop"])
    paste_fitted(sheet, paths / "default" / "mobile.png", boxes["default_mobile"])
    paste_fitted(sheet, paths / "default" / "compact.png", boxes["default_compact"])
    paste_fitted(
        sheet,
        paths / "default" / "thumbnail.png",
        boxes["default_thumbnail"],
    )
    paste_fitted(
        sheet,
        paths / "high_contrast" / "desktop.png",
        boxes["hc_desktop"],
    )
    paste_fitted(
        sheet,
        paths / "high_contrast" / "mobile.png",
        boxes["hc_mobile"],
    )
    text_label(sheet, (44, 1240), "PASS LIBRARY", 18, accent)
    pass_names = ["silhouette", "material", "normal", "part_mask", "subject_mask"]
    for index, pass_name in enumerate(pass_names):
        x0 = 40 + index * 370
        paste_fitted(
            sheet,
            output_root / treatment_id / "passes" / f"{pass_name}.png",
            (x0, 1280, x0 + 350, 1478),
        )
        text_label(
            sheet,
            (x0, 1490),
            pass_name.replace("_", " ").upper(),
            14,
            foreground,
        )
    output = output_root / treatment_id / f"{treatment_id}-contact-sheet.png"
    stable_save(sheet, output)
    return output


def comparison_sheet(
    treatments: list[dict[str, Any]],
    output_root: Path,
    palette: dict[str, str],
) -> Path:
    sheet = Image.new(
        "RGBA",
        (1920, 1260),
        (*hex_rgb(palette["night_void"]), 255),
    )
    text_label(
        sheet,
        (38, 22),
        "THE LANTERN LINE // M3A TREATMENT COMPARISON",
        32,
        hex_rgb(palette["bone"]),
        True,
    )
    row_specs = [
        ("DEFAULT 1280 x 720", "default", "desktop", 94, 330),
        ("DEFAULT 844 x 390", "default", "mobile", 486, 245),
        ("HIGH CONTRAST 1280 x 720", "high_contrast", "desktop", 808, 330),
    ]
    for title, variant, size_name, y0, height in row_specs:
        text_label(
            sheet,
            (40, y0 - 26),
            title,
            17,
            hex_rgb(palette["brass"]),
        )
        for index, treatment in enumerate(treatments):
            x0 = 30 + index * 630
            path = (
                output_root
                / treatment["id"]
                / "final"
                / variant
                / f"{size_name}.png"
            )
            paste_fitted(sheet, path, (x0, y0, x0 + 610, y0 + height))
            text_label(
                sheet,
                (x0 + 8, y0 + height + 4),
                treatment["display_name"].upper(),
                17,
                hex_rgb(palette["bone"]),
            )
    output = output_root / "m3a-treatment-comparison.png"
    stable_save(sheet, output)
    return output


def bbox_for_mask(mask: np.ndarray) -> tuple[int, int, int, int] | None:
    ys, xs = np.nonzero(mask)
    if len(xs) == 0:
        return None
    return int(xs.min()), int(ys.min()), int(xs.max()) + 1, int(ys.max()) + 1


def subject_metrics(mask_path: Path) -> dict[str, float]:
    image = np.asarray(Image.open(mask_path).convert("RGB"), dtype=np.int16)
    red = image[:, :, 0]
    green = image[:, :, 1]
    blue = image[:, :, 2]
    train = (red > 100) & (green > 75) & (blue < 150) & ((red - green) < 95)
    pursuer = (red > 85) & (red > green * 1.34) & (blue < 135)
    height, width, _ = image.shape
    train_box = bbox_for_mask(train)
    pursuer_box = bbox_for_mask(pursuer)

    def dimensions(box: tuple[int, int, int, int] | None) -> tuple[float, float]:
        if box is None:
            return 0.0, 0.0
        return (
            (box[2] - box[0]) / float(width) * 100.0,
            (box[3] - box[1]) / float(height) * 100.0,
        )

    train_width, train_height = dimensions(train_box)
    pursuer_width, pursuer_height = dimensions(pursuer_box)
    return {
        "train_width_percent": round(train_width, 3),
        "train_height_percent": round(train_height, 3),
        "pursuer_width_percent": round(pursuer_width, 3),
        "pursuer_height_percent": round(pursuer_height, 3),
    }


def image_metrics(path: Path) -> dict[str, float]:
    image = Image.open(path).convert("RGB")
    array = np.asarray(image, dtype=np.float32) / 255.0
    luminance = (
        array[:, :, 0] * 0.2126
        + array[:, :, 1] * 0.7152
        + array[:, :, 2] * 0.0722
    )
    p10 = float(np.percentile(luminance, 10))
    p90 = float(np.percentile(luminance, 90))
    contrast = (p90 + 0.05) / (p10 + 0.05)
    edges = image.convert("L").filter(ImageFilter.FIND_EDGES)
    edge_array = np.asarray(edges, dtype=np.uint8)
    edge_density = float(np.mean(edge_array > 30))
    return {
        "luminance_p10": round(p10, 4),
        "luminance_p90": round(p90, 4),
        "global_contrast_ratio": round(contrast, 3),
        "edge_density": round(edge_density, 4),
    }


def run_blender(
    blender: Path,
    config: Path,
    treatment_id: str,
    work_root: Path,
    engine: str,
) -> None:
    command = [
        str(blender),
        "--background",
        "--factory-startup",
        "--python",
        str(BLENDER_SCRIPT),
        "--",
        "--config",
        str(config),
        "--treatment",
        treatment_id,
        "--output-root",
        str(work_root),
        "--engine",
        engine,
    ]
    subprocess.run(command, cwd=REPO_ROOT, check=True)


def process_treatment(
    config: dict[str, Any],
    treatment: dict[str, Any],
    work_root: Path,
    review_root: Path,
    engine: str,
) -> dict[str, Any]:
    treatment_id = treatment["id"]
    raw_root = work_root / treatment_id / engine / "raw"
    final_root = review_root / treatment_id / "final"
    passes_root = review_root / treatment_id / "passes"
    metadata_path = work_root / treatment_id / engine / "metadata.json"
    metadata = load_json(metadata_path)
    for variant in ("default", "high_contrast"):
        desktop_raw = raw_root / variant / "desktop.png"
        mobile_raw = raw_root / variant / "mobile.png"
        desktop_final = final_root / variant / "desktop.png"
        mobile_final = final_root / variant / "mobile.png"
        grade_frame(
            desktop_raw,
            desktop_final,
            config["palette"],
            treatment,
            variant,
            int(config["seed"]) + sum(ord(char) for char in treatment_id + variant),
            metadata["screen_anchors"]["desktop"],
            raw_root / "passes" / "subject_mask.png",
        )
        grade_frame(
            mobile_raw,
            mobile_final,
            config["palette"],
            treatment,
            variant,
            int(config["seed"]) + sum(ord(char) for char in treatment_id + variant) + 1,
            metadata["screen_anchors"]["mobile"],
            raw_root / "passes" / "subject_mask_mobile.png",
        )
        resize_frame(
            desktop_final,
            final_root / variant / "compact.png",
            config["sizes"]["compact"],
        )
        resize_frame(
            desktop_final,
            final_root / variant / "thumbnail.png",
            config["sizes"]["thumbnail"],
        )

    pass_names = [
        "silhouette",
        "material",
        "normal",
        "part_mask",
        "subject_mask",
        "subject_mask_mobile",
    ]
    for pass_name in pass_names:
        normalize_pass(
            raw_root / "passes" / f"{pass_name}.png",
            passes_root / f"{pass_name}.png",
        )

    contact_sheet = treatment_contact_sheet(
        treatment,
        review_root,
        config["palette"],
    )
    metrics = {
        "desktop": image_metrics(final_root / "default" / "desktop.png"),
        "mobile": image_metrics(final_root / "default" / "mobile.png"),
        "thumbnail": image_metrics(final_root / "default" / "thumbnail.png"),
        "mobile_subjects": subject_metrics(
            passes_root / "subject_mask_mobile.png"
        ),
    }
    artifacts = []
    for path in sorted((review_root / treatment_id).rglob("*.png")):
        artifacts.append(
            {
                "path": path.relative_to(REPO_ROOT).as_posix(),
                "bytes": path.stat().st_size,
                "sha256": sha256_file(path),
                "pixel_sha256": pixel_sha256(path),
            }
        )
    return {
        "id": treatment_id,
        "display_name": treatment["display_name"],
        "parameters": treatment,
        "metrics": metrics,
        "blender_metadata": metadata,
        "contact_sheet": contact_sheet.relative_to(REPO_ROOT).as_posix(),
        "artifacts": artifacts,
    }


def artifact_record_map(payload: dict[str, Any]) -> dict[str, dict[str, Any]]:
    artifacts = {
        str(artifact["path"]): artifact
        for treatment in payload["treatments"]
        for artifact in treatment["artifacts"]
    }
    comparison = payload["comparison_sheet"]
    artifacts[str(comparison["path"])] = comparison
    return artifacts


def pixel_delta(left: Path, right: Path) -> dict[str, Any]:
    left_image = np.asarray(Image.open(left).convert("RGBA"), dtype=np.int16)
    right_image = np.asarray(Image.open(right).convert("RGBA"), dtype=np.int16)
    if left_image.shape != right_image.shape:
        return {
            "dimensions_match": False,
            "left_shape": list(left_image.shape),
            "right_shape": list(right_image.shape),
        }
    delta = np.abs(left_image - right_image)
    changed = np.any(delta != 0, axis=2)
    changed_pixels = int(changed.sum())
    total_pixels = int(changed.size)
    return {
        "dimensions_match": True,
        "changed_pixels": changed_pixels,
        "total_pixels": total_pixels,
        "changed_pixel_ratio": (
            float(changed_pixels / total_pixels)
            if total_pixels
            else 0.0
        ),
        "max_channel_delta": int(delta.max()) if delta.size else 0,
        "mean_abs_channel_delta": float(delta.mean()) if delta.size else 0.0,
    }


def preview_delta_allowed(delta: dict[str, Any]) -> bool:
    return (
        bool(delta.get("dimensions_match", False))
        and int(delta["changed_pixels"]) <= PREVIEW_REPLAY_MAX_CHANGED_PIXELS
        and float(delta["changed_pixel_ratio"])
        <= PREVIEW_REPLAY_MAX_CHANGED_RATIO
        and int(delta["max_channel_delta"])
        <= PREVIEW_REPLAY_MAX_CHANNEL_DELTA
        and float(delta["mean_abs_channel_delta"])
        <= PREVIEW_REPLAY_MAX_MEAN_ABS_DELTA
    )


def verify_replay_artifacts(
    primary: dict[str, Any],
    replay: dict[str, Any],
    engine: str,
    primary_review_root: Path,
    replay_review_root: Path,
) -> dict[str, Any]:
    primary_records = artifact_record_map(primary)
    replay_records = artifact_record_map(replay)
    primary_prefix = primary_review_root.relative_to(REPO_ROOT).as_posix()
    replay_prefix = replay_review_root.relative_to(REPO_ROOT).as_posix()
    normalized_replay: dict[str, tuple[dict[str, Any], Path]] = {}
    for path, record in replay_records.items():
        logical_path = path.replace(replay_prefix, primary_prefix, 1)
        normalized_replay[logical_path] = (record, REPO_ROOT / path)

    failures = []
    tolerated = []
    exact_count = 0
    for path in sorted(primary_records.keys() | normalized_replay.keys()):
        primary_record = primary_records.get(path)
        replay_entry = normalized_replay.get(path)
        if primary_record is None:
            failures.append(f"unexpected {path}")
            continue
        if replay_entry is None:
            failures.append(f"missing {path}")
            continue
        replay_record, replay_path = replay_entry
        primary_hash = str(primary_record["pixel_sha256"])
        replay_hash = str(replay_record["pixel_sha256"])
        if primary_hash == replay_hash:
            exact_count += 1
            continue
        delta = pixel_delta(REPO_ROOT / path, replay_path)
        if engine == "preview" and preview_delta_allowed(delta):
            tolerated.append(
                {
                    "path": path,
                    "primary_pixel_sha256": primary_hash,
                    "replay_pixel_sha256": replay_hash,
                    "delta": delta,
                }
            )
            continue
        failures.append(
            f"changed {path}: primary {primary_hash}, "
            f"replay {replay_hash}, delta {json.dumps(delta, sort_keys=True)}"
        )

    if failures:
        raise RuntimeError(
            "Style-lock replay pixels did not match:\n"
            + "\n".join(failures)
        )
    verification = {
        "mode": "exact" if not tolerated else "strict_preview_tolerance",
        "artifact_count": len(primary_records),
        "exact_artifacts": exact_count,
        "tolerated_artifacts": tolerated,
    }
    if engine == "preview":
        verification["tolerance"] = {
            "max_changed_pixels": PREVIEW_REPLAY_MAX_CHANGED_PIXELS,
            "max_changed_pixel_ratio": PREVIEW_REPLAY_MAX_CHANGED_RATIO,
            "max_channel_delta": PREVIEW_REPLAY_MAX_CHANNEL_DELTA,
            "max_mean_abs_channel_delta": (
                PREVIEW_REPLAY_MAX_MEAN_ABS_DELTA
            ),
        }
    else:
        verification["tolerance"] = None
    return verification


def build(
    args: argparse.Namespace,
    config_path: Path,
    work_root: Path,
    review_root: Path,
    receipt_path: Path,
) -> dict[str, Any]:
    config = load_json(config_path)
    requested = set(args.treatment)
    treatments = [
        item
        for item in config["treatments"]
        if not requested or item["id"] in requested
    ]
    if requested.difference(item["id"] for item in treatments):
        raise ValueError("Unknown treatment requested.")
    blender = find_blender(args.blender)
    if not args.skip_blender:
        for treatment in treatments:
            run_blender(
                blender,
                config_path,
                treatment["id"],
                work_root,
                args.engine,
            )
    review_root.mkdir(parents=True, exist_ok=True)
    (review_root / ".gdignore").write_text("", encoding="utf-8")
    treatment_payloads = [
        process_treatment(
            config,
            treatment,
            work_root,
            review_root,
            args.engine,
        )
        for treatment in treatments
    ]
    comparison = comparison_sheet(treatments, review_root, config["palette"])
    comparison_artifact = {
        "path": comparison.relative_to(REPO_ROOT).as_posix(),
        "bytes": comparison.stat().st_size,
        "sha256": sha256_file(comparison),
        "pixel_sha256": pixel_sha256(comparison),
    }
    payload = {
        "schema_version": 1,
        "milestone": config["milestone"],
        "generated_at_utc": datetime.now(timezone.utc).isoformat(),
        "git_head": git_head(),
        "config": config_path.relative_to(REPO_ROOT).as_posix(),
        "config_sha256": sha256_file(config_path),
        "blender": {
            "executable": str(blender),
            "version": subprocess.run(
                [str(blender), "--version"],
                check=True,
                capture_output=True,
                text=True,
                encoding="utf-8",
            ).stdout.splitlines()[0],
        },
        "engine": args.engine,
        "selected_treatment": config.get("selected_treatment", ""),
        "comparison_sheet": comparison_artifact,
        "treatments": treatment_payloads,
    }
    receipt_path.parent.mkdir(parents=True, exist_ok=True)
    receipt_path.write_text(
        json.dumps(payload, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    return payload


def main() -> int:
    args = parse_args()
    config_path = args.config.resolve()
    work_root, review_root, receipt_path = output_paths(args)
    if args.clean:
        for target in (work_root, review_root):
            if target.exists():
                shutil.rmtree(target)
    payload = build(args, config_path, work_root, review_root, receipt_path)
    if args.verify_replay:
        (REPO_ROOT / "build").mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(
            prefix="lantern-m3a-replay-",
            dir=REPO_ROOT / "build",
        ) as temp:
            temp_root = Path(temp)
            replay_args = argparse.Namespace(**vars(args))
            replay_args.work_root = temp_root / "work"
            replay_args.review_root = temp_root / "review"
            replay_args.receipt = temp_root / "receipt.json"
            replay_args.clean = False
            replay_args.verify_replay = False
            replay = build(
                replay_args,
                config_path,
                replay_args.work_root,
                replay_args.review_root,
                replay_args.receipt,
            )
            verification = verify_replay_artifacts(
                payload,
                replay,
                args.engine,
                review_root,
                replay_args.review_root,
            )
            payload["replay_verified"] = True
            payload["replay_verification"] = verification
            receipt_path.write_text(
                json.dumps(payload, indent=2, sort_keys=True) + "\n",
                encoding="utf-8",
            )
    print(
        "[style-lock] "
        f"treatments={len(payload['treatments'])} "
        f"engine={payload['engine']} receipt={receipt_path}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
