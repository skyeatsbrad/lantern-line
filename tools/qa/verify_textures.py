from __future__ import annotations

from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]
PROJECT_PATH = REPO_ROOT / "project.godot"
GENERATED_ROOT = REPO_ROOT / "assets" / "generated" / "visual" / "v08"
PROBE_PATH = REPO_ROOT / "tools" / "qa" / "fixtures" / "compression_probe.png"
SETTING = "textures/vram_compression/import_etc2_astc=true"


def main() -> int:
    project_text = PROJECT_PATH.read_text(encoding="utf-8")
    if SETTING not in project_text:
        raise RuntimeError("ETC2/ASTC project import setting is not enabled.")
    texture_paths = [PROBE_PATH]
    for profile in ["high", "low"]:
        root = GENERATED_ROOT / profile
        if root.exists():
            texture_paths.extend(root.rglob("*.png"))
    checked = 0
    for texture_path in sorted(path for path in texture_paths if path.is_file()):
        import_path = texture_path.with_suffix(texture_path.suffix + ".import")
        if not import_path.is_file():
            raise RuntimeError(f"Generated texture is not imported: {texture_path}")
        import_text = import_path.read_text(encoding="utf-8")
        if "compress/mode=2" not in import_text:
            raise RuntimeError(
                f"Generated texture is not configured for VRAM compression: {texture_path}"
            )
        if '"vram_texture": true' not in import_text:
            raise RuntimeError(
                f"Generated texture was not imported as a VRAM texture: {texture_path}"
            )
        if ".etc2." not in import_text and "path.etc2" not in import_text:
            raise RuntimeError(
                f"Generated texture lacks an ETC2 import artifact: {texture_path}"
            )
        checked += 1
    print(f"[textures] ETC2/ASTC enabled generated_textures={checked}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
