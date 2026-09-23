from __future__ import annotations

import re
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]
PROBE_PATH = REPO_ROOT / "tools" / "qa" / "fixtures" / "compression_probe.png"
GENERATED_ROOTS = [
    REPO_ROOT / "assets" / "generated" / "visual" / "v08" / "high",
    REPO_ROOT / "assets" / "generated" / "visual" / "v08" / "low",
]


def texture_paths() -> list[Path]:
    paths = [PROBE_PATH]
    for root in GENERATED_ROOTS:
        if root.exists():
            paths.extend(root.rglob("*.png"))
    return sorted(path for path in paths if path.is_file())


def main() -> int:
    configured = 0
    for texture_path in texture_paths():
        import_path = texture_path.with_suffix(texture_path.suffix + ".import")
        if not import_path.is_file():
            raise FileNotFoundError(
                f"Import metadata is missing; run a Godot import first: {texture_path}"
            )
        text = import_path.read_text(encoding="utf-8")
        updated, count = re.subn(
            r"(?m)^compress/mode=\d+$",
            "compress/mode=2",
            text,
            count=1,
        )
        if count != 1:
            raise RuntimeError(f"Could not set VRAM compression: {import_path}")
        import_path.write_text(updated, encoding="utf-8")
        configured += 1
    print(f"[textures] configured VRAM imports={configured}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
