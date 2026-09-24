"""Validate controlled `.blend` source drift for a v0.8 milestone.

Milestones without controlled scene-first sources must succeed with zero
manifests. Once controlled `.blend` sources land, the same script emits a
machine-readable receipt describing which blends were verified, allowing later
stages to detect drift by diffing receipts across builds.

The script wraps `tools/qa/validate_blend.py` so it can be run as a stand-alone
QA gate without a Blender install when no manifest exists. When Blender IS
available and there is at least one manifest, it delegates to the strict
validator.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import subprocess
import sys
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]
SOURCE_ROOT = REPO_ROOT / "assets" / "source"
DEFAULT_RECEIPT = (
    REPO_ROOT
    / "design"
    / "receipts"
    / "v0.8-m2"
    / "blend-drift-receipt.json"
)
VALIDATE_BLEND = REPO_ROOT / "tools" / "qa" / "validate_blend.py"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--milestone",
        default="v0.8-m2",
        help="Milestone identifier recorded in the receipt.",
    )
    parser.add_argument(
        "--blender",
        help=(
            "Path to Blender. Required only when there is at least one "
            "controlled .blend manifest."
        ),
    )
    parser.add_argument(
        "--receipt",
        default=str(DEFAULT_RECEIPT),
        help="Path to write the drift receipt JSON.",
    )
    return parser.parse_args()


def discover_manifests() -> list[Path]:
    if not SOURCE_ROOT.exists():
        return []
    results: list[Path] = []
    for path in SOURCE_ROOT.rglob("*.json"):
        try:
            data = json.loads(path.read_text(encoding="utf-8"))
        except json.JSONDecodeError:
            continue
        if data.get("source_type") == "blend":
            results.append(path)
    return sorted(results)


def sha256_bytes(text: str) -> str:
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


def build_receipt(
    manifests: list[Path],
    run_result: int,
    milestone: str,
) -> dict:
    entries: list[dict] = []
    for manifest_path in manifests:
        try:
            manifest_body = manifest_path.read_text(encoding="utf-8")
            manifest_data = json.loads(manifest_body)
        except (json.JSONDecodeError, OSError) as error:
            raise RuntimeError(
                f"Manifest {manifest_path} could not be read: {error}"
            ) from error
        entries.append(
            {
                "manifest_path": manifest_path.relative_to(REPO_ROOT).as_posix(),
                "manifest_sha256": sha256_bytes(manifest_body),
                "blend_file": str(manifest_data.get("blend_file", "")),
                "collections": manifest_data.get("collections", []),
                "materials": manifest_data.get("materials", []),
                "actions": [
                    str(action.get("name", ""))
                    for action in manifest_data.get("actions", [])
                ],
                "socket_names": [
                    str(socket.get("name", ""))
                    for socket in manifest_data.get("sockets", [])
                ],
            }
        )
    return {
        "milestone": milestone,
        "manifest_count": len(manifests),
        "manifests": entries,
        "validate_blend_exit_code": run_result,
    }


def main() -> int:
    args = parse_args()
    manifests = discover_manifests()
    run_result = 0
    if manifests:
        if not args.blender:
            print(
                "[blend-drift] manifests exist but --blender was not "
                "provided; strict validation cannot run."
            )
            run_result = 2
            receipt = build_receipt(
                manifests,
                run_result,
                args.milestone,
            )
            _write_receipt(receipt, Path(args.receipt))
            return run_result
        else:
            command = [
                sys.executable,
                str(VALIDATE_BLEND),
                "--blender",
                str(args.blender),
            ]
            result = subprocess.run(command, check=False)
            run_result = result.returncode
            if result.returncode != 0:
                print(
                    "[blend-drift] validate_blend.py failed with exit "
                    f"{result.returncode}; drift detected."
                )
                receipt = build_receipt(
                    manifests,
                    run_result,
                    args.milestone,
                )
                _write_receipt(receipt, Path(args.receipt))
                return result.returncode
    receipt = build_receipt(
        manifests,
        run_result,
        args.milestone,
    )
    _write_receipt(receipt, Path(args.receipt))
    if not manifests:
        print(
            "[blend-drift] no controlled .blend manifests "
            f"({args.milestone}; receipt written)."
        )
    else:
        print(
            f"[blend-drift] verified manifests={len(manifests)} receipt="
            f"{args.receipt}"
        )
    return 0


def _write_receipt(receipt: dict, output: Path) -> None:
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(
        json.dumps(receipt, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )


if __name__ == "__main__":
    raise SystemExit(main())
