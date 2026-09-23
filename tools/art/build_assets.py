from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
from typing import Any


PIPELINE_VERSION = "0.1.0"
REPO_ROOT = Path(__file__).resolve().parents[2]
SOURCE_ROOT = REPO_ROOT / "assets" / "source"
OUTPUT_ROOT = REPO_ROOT / "assets" / "generated" / "visual" / "v08"
METADATA_ROOT = OUTPUT_ROOT / "metadata"
RECEIPT_PATH = METADATA_ROOT / "build_receipt.json"
HASH_PATH = OUTPUT_ROOT / "BUILD_HASH.txt"
REVIEW_PATH = REPO_ROOT / "design" / "receipts" / "v0.8-assets.md"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--all", action="store_true")
    parser.add_argument("--category", action="append", default=[])
    parser.add_argument("--verify", action="store_true")
    parser.add_argument("--review", action="store_true")
    return parser.parse_args()


def canonical_json(value: Any) -> str:
    return json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=True)


def sha256_bytes(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


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


def expected_outputs(
    manifest: dict[str, Any],
    categories: list[str],
) -> tuple[dict[str, Any], str, str]:
    receipt_without_hash = {
        "schema_version": 1,
        "pipeline_version": PIPELINE_VERSION,
        "source_hash": hash_inputs(),
        "toolchain": manifest["toolchain"],
        "categories": categories,
        "artifacts": [],
    }
    build_hash = sha256_bytes(canonical_json(receipt_without_hash).encode("utf-8"))
    receipt = dict(receipt_without_hash)
    receipt["build_hash"] = build_hash
    receipt_text = json.dumps(receipt, indent=2, sort_keys=True) + "\n"
    review_text = (
        "# v0.8 Asset Build Receipt\n\n"
        f"- Pipeline: `{PIPELINE_VERSION}`\n"
        f"- Source hash: `{receipt['source_hash']}`\n"
        f"- Build hash: `{build_hash}`\n"
        f"- Categories: `{', '.join(categories) if categories else 'none (M0 scaffold)'}`\n"
        "- Generated artifacts: `0`\n"
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
    receipt, receipt_text, review_text = expected_outputs(manifest, categories)
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
