from __future__ import annotations

import argparse
import hashlib
import json
import subprocess
import sys
from pathlib import Path
from typing import Any


PIPELINE_VERSION = "0.2.1"
REPO_ROOT = Path(__file__).resolve().parents[2]
SOURCE_ROOT = REPO_ROOT / "assets" / "source"
OUTPUT_ROOT = REPO_ROOT / "assets" / "generated" / "visual" / "v08"
METADATA_ROOT = OUTPUT_ROOT / "metadata"
RECEIPT_PATH = METADATA_ROOT / "build_receipt.json"
HASH_PATH = OUTPUT_ROOT / "BUILD_HASH.txt"
REVIEW_PATH = REPO_ROOT / "design" / "receipts" / "v0.8-assets.md"
STYLE_RECEIPT_PATH = (
    REPO_ROOT / "design" / "receipts" / "v0.8-m3a" / "style-lock.json"
)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--all", action="store_true")
    parser.add_argument("--category", action="append", default=[])
    parser.add_argument("--verify", action="store_true")
    parser.add_argument("--review", action="store_true")
    parser.add_argument("--blender", type=Path)
    parser.add_argument(
        "--engine",
        choices=["preview"],
        default="preview",
        help=(
            "Accepted asset-factory output. Canonical verification must use "
            "build_style_lock.py with explicit isolated output paths."
        ),
    )
    parser.add_argument("--clean", action="store_true")
    parser.add_argument("--verify-replay", action="store_true")
    return parser.parse_args()


def canonical_json(value: Any) -> str:
    return json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=True)


def sha256_bytes(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def hash_inputs() -> str:
    digest = hashlib.sha256()
    roots = [
        SOURCE_ROOT,
        REPO_ROOT / "tools" / "art",
    ]
    files: list[Path] = []
    for root in roots:
        if not root.exists():
            continue
        files.extend(
            path
            for path in root.rglob("*")
            if path.is_file() and "__pycache__" not in path.parts
        )
    for path in sorted(files, key=lambda item: item.as_posix()):
        relative = path.relative_to(REPO_ROOT).as_posix().encode("utf-8")
        digest.update(relative)
        digest.update(b"\0")
        digest.update(path.read_bytes())
        digest.update(b"\0")
    return digest.hexdigest()


def load_manifest() -> dict[str, Any]:
    path = SOURCE_ROOT / "manifest.json"
    manifest = json.loads(path.read_text(encoding="utf-8"))
    required = {"schema_version", "pipeline_version", "toolchain", "categories"}
    missing = sorted(required.difference(manifest))
    if missing:
        raise ValueError(f"Manifest is missing keys: {', '.join(missing)}")
    if manifest["schema_version"] != 1:
        raise ValueError("Unsupported asset manifest schema.")
    if manifest["pipeline_version"] != PIPELINE_VERSION:
        raise ValueError("Asset manifest and builder pipeline versions differ.")
    category_ids = [str(category.get("id", "")) for category in manifest["categories"]]
    if len(category_ids) != len(set(category_ids)) or "" in category_ids:
        raise ValueError("Asset category IDs must be non-empty and unique.")
    return manifest


def selected_categories(
    manifest: dict[str, Any],
    requested: list[str],
) -> list[str]:
    available = [str(category["id"]) for category in manifest["categories"]]
    if not requested:
        return available
    unknown = sorted(set(requested).difference(available))
    if unknown:
        raise ValueError(f"Unknown asset categories: {', '.join(unknown)}")
    return sorted(set(requested))


def category_map(manifest: dict[str, Any]) -> dict[str, dict[str, Any]]:
    return {
        str(category["id"]): category
        for category in manifest["categories"]
    }


def run_generators(
    manifest: dict[str, Any],
    categories: list[str],
    args: argparse.Namespace,
) -> None:
    entries = category_map(manifest)
    for category_id in categories:
        category = entries[category_id]
        generator = (REPO_ROOT / str(category["generator"])).resolve()
        if not generator.is_file():
            raise FileNotFoundError(generator)
        command = [
            sys.executable,
            str(generator),
            "--engine",
            args.engine,
        ]
        if args.blender is not None:
            command.extend(["--blender", str(args.blender.resolve())])
        if args.clean:
            command.append("--clean")
        if args.verify_replay:
            command.append("--verify-replay")
        subprocess.run(command, cwd=REPO_ROOT, check=True)


def verified_artifact(
    item: dict[str, Any],
    category: str,
) -> dict[str, Any]:
    relative = str(item["path"])
    path = REPO_ROOT / relative
    if not path.is_file():
        raise FileNotFoundError(f"Generated artifact is missing: {relative}")
    actual_hash = sha256_file(path)
    expected_hash = str(item["sha256"])
    if actual_hash != expected_hash:
        raise RuntimeError(
            f"Generated artifact hash differs from category receipt: {relative}"
        )
    actual_bytes = path.stat().st_size
    expected_bytes = int(item["bytes"])
    if actual_bytes != expected_bytes:
        raise RuntimeError(
            f"Generated artifact size differs from category receipt: {relative}"
        )
    artifact = {
        "path": relative,
        "bytes": actual_bytes,
        "sha256": actual_hash,
        "category": category,
        "purpose": "review",
    }
    if "pixel_sha256" in item:
        artifact["pixel_sha256"] = str(item["pixel_sha256"])
    return artifact


def collect_style_artifacts() -> tuple[list[dict[str, Any]], dict[str, Any]]:
    if not STYLE_RECEIPT_PATH.is_file():
        raise FileNotFoundError(
            f"Style generator receipt is missing: {STYLE_RECEIPT_PATH}"
        )
    payload = json.loads(STYLE_RECEIPT_PATH.read_text(encoding="utf-8"))
    artifacts = [
        verified_artifact(payload["comparison_sheet"], "style")
    ]
    for treatment in payload["treatments"]:
        artifacts.extend(
            verified_artifact(item, "style")
            for item in treatment["artifacts"]
        )
    metadata = {
        "receipt": STYLE_RECEIPT_PATH.relative_to(REPO_ROOT).as_posix(),
        "engine": str(payload["engine"]),
        "selected_treatment": str(payload.get("selected_treatment", "")),
        "treatment_count": len(payload["treatments"]),
        "comparison_sheet": str(payload["comparison_sheet"]["path"]),
        "replay_verified": bool(payload.get("replay_verified", False)),
        "replay_mode": str(
            payload.get("replay_verification", {}).get("mode", "not_run")
        ),
    }
    return artifacts, metadata


def collect_artifacts(
    categories: list[str],
) -> tuple[list[dict[str, Any]], dict[str, Any]]:
    artifacts: list[dict[str, Any]] = []
    category_receipts: dict[str, Any] = {}
    for category in categories:
        if category == "style":
            category_artifacts, metadata = collect_style_artifacts()
            artifacts.extend(category_artifacts)
            category_receipts[category] = metadata
            continue
        raise ValueError(f"No generator integration exists for category: {category}")
    artifacts.sort(key=lambda item: str(item["path"]))
    return artifacts, category_receipts


def expected_outputs(
    manifest: dict[str, Any],
    categories: list[str],
    artifacts: list[dict[str, Any]],
    category_receipts: dict[str, Any],
) -> tuple[dict[str, Any], str, str]:
    receipt_without_hash = {
        "schema_version": 1,
        "pipeline_version": PIPELINE_VERSION,
        "source_hash": hash_inputs(),
        "toolchain": manifest["toolchain"],
        "categories": categories,
        "category_receipts": category_receipts,
        "artifacts": artifacts,
    }
    build_hash = sha256_bytes(canonical_json(receipt_without_hash).encode("utf-8"))
    receipt = dict(receipt_without_hash)
    receipt["build_hash"] = build_hash
    receipt_text = json.dumps(receipt, indent=2, sort_keys=True) + "\n"
    artifact_bytes = sum(int(item["bytes"]) for item in artifacts)
    production_count = sum(
        1 for item in artifacts if item["purpose"] == "production"
    )
    selected = str(
        category_receipts.get("style", {}).get("selected_treatment", "")
    )
    review_text = (
        "# v0.8 Asset Build Receipt\n\n"
        f"- Pipeline: `{PIPELINE_VERSION}`\n"
        f"- Source hash: `{receipt['source_hash']}`\n"
        f"- Build hash: `{build_hash}`\n"
        f"- Categories: `{', '.join(categories) if categories else 'none'}`\n"
        f"- Selected style treatment: `{selected or 'none'}`\n"
        f"- Generated artifacts: `{len(artifacts)}`\n"
        f"- Generated artifact bytes: `{artifact_bytes}`\n"
        f"- Production package artifacts: `{production_count}`\n"
        "- M3A style evidence remains under a `.gdignore` review directory and "
        "does not enter the Godot package.\n"
    )
    return receipt, receipt_text, review_text


def verify_text(path: Path, expected: str) -> None:
    if not path.is_file():
        raise FileNotFoundError(f"Required generated file is missing: {path}")
    actual = path.read_text(encoding="utf-8")
    if actual != expected:
        raise RuntimeError(f"Generated file is stale: {path}")


def main() -> int:
    args = parse_args()
    manifest = load_manifest()
    categories = selected_categories(manifest, args.category)
    if not args.verify:
        run_generators(manifest, categories, args)
    artifacts, category_receipts = collect_artifacts(categories)
    receipt, receipt_text, review_text = expected_outputs(
        manifest,
        categories,
        artifacts,
        category_receipts,
    )
    hash_text = f"{receipt['build_hash']}\n"

    if args.verify:
        verify_text(RECEIPT_PATH, receipt_text)
        verify_text(HASH_PATH, hash_text)
        if args.review:
            verify_text(REVIEW_PATH, review_text)
        print(f"[assets] verified build_hash={receipt['build_hash']}")
        return 0

    METADATA_ROOT.mkdir(parents=True, exist_ok=True)
    RECEIPT_PATH.write_text(receipt_text, encoding="utf-8")
    HASH_PATH.write_text(hash_text, encoding="utf-8")
    if args.review:
        REVIEW_PATH.parent.mkdir(parents=True, exist_ok=True)
        REVIEW_PATH.write_text(review_text, encoding="utf-8")
    print(f"[assets] built build_hash={receipt['build_hash']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
