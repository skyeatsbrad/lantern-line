from __future__ import annotations

import hashlib
import json
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]
OUTPUT_ROOT = REPO_ROOT / "assets" / "generated" / "visual" / "v08"
RECEIPT_PATH = OUTPUT_ROOT / "metadata" / "build_receipt.json"
ARTIFACT_ROOTS = [
    OUTPUT_ROOT / "high",
    OUTPUT_ROOT / "low",
    OUTPUT_ROOT / "resources",
]


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def main() -> int:
    if not RECEIPT_PATH.is_file():
        raise FileNotFoundError(f"Missing build receipt: {RECEIPT_PATH}")
    receipt = json.loads(RECEIPT_PATH.read_text(encoding="utf-8"))
    declared: dict[str, str] = {}
    for item in receipt.get("artifacts", []):
        relative = str(item["path"])
        if relative in declared:
            raise RuntimeError(f"Duplicate artifact provenance: {relative}")
        declared[relative] = str(item["sha256"])
        path = REPO_ROOT / relative
        if not path.is_file():
            raise RuntimeError(f"Receipt references missing artifact: {relative}")
        actual_hash = sha256_file(path)
        if actual_hash != declared[relative]:
            raise RuntimeError(
                f"Generated artifact hash differs from receipt: {relative}"
            )
    production_files: set[str] = set()
    for root in ARTIFACT_ROOTS:
        if not root.exists():
            continue
        for path in sorted(item for item in root.rglob("*") if item.is_file()):
            relative = path.relative_to(REPO_ROOT).as_posix()
            production_files.add(relative)
            if relative not in declared:
                raise RuntimeError(f"Generated artifact lacks provenance: {relative}")
    print(
        "[provenance] "
        f"verified artifacts={len(declared)} "
        f"production_artifacts={len(production_files)}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
