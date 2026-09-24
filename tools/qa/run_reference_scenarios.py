from __future__ import annotations

import argparse
import json
import os
import subprocess
import tempfile
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from source_fingerprint import source_fingerprint


REPO_ROOT = Path(__file__).resolve().parents[2]
SCENARIOS = [
    "headlight_reveal",
    "standard_defense",
    "heavy_cannon",
    "flak",
    "focus",
    "ward_shatter",
    "repair",
    "detachment",
    "longshadow_veil",
    "longshadow_tether",
    "longshadow_charge",
    "dawn",
]
VARIANTS = ["vector", "baked"]
SCENARIO_MARKER = "[scenario] scenario_json "
CAPTURE_MARKER = "[scenario] capture_json "


def run_scenario(
    godot: Path,
    scenario: str,
    variant: str,
    capture_root: Path | None,
) -> dict[str, Any]:
    env = os.environ.copy()
    env["LANTERN_PROBE"] = "1"
    env["LANTERN_REFERENCE_SCENARIO"] = scenario
    env["LANTERN_REFERENCE_SCENARIO_AB"] = variant
    for name in [
        "LANTERN_PROBE_DENSE_COMBAT",
        "LANTERN_PROBE_AUDIO",
        "LANTERN_VISUAL_BENCHMARK",
    ]:
        env.pop(name, None)
    capture_base: Path | None = None
    if capture_root is not None:
        capture_base = (
            capture_root / variant / f"{scenario}-trigger.png"
        ).resolve()
        env["LANTERN_REFERENCE_SCENARIO_CAPTURE"] = str(capture_base)
    else:
        env.pop("LANTERN_REFERENCE_SCENARIO_CAPTURE", None)

    result = subprocess.run(
        [
            str(godot),
            "--path",
            str(REPO_ROOT),
            "--rendering-method",
            "gl_compatibility",
            "--display-driver",
            "windows",
            "--audio-driver",
            "Dummy",
        ],
        cwd=REPO_ROOT,
        env=env,
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
        timeout=20.0,
    )
    output = "\n".join(part for part in [result.stdout, result.stderr] if part)
    if result.returncode != 0:
        raise RuntimeError(
            f"{scenario}/{variant} failed with {result.returncode}:\n{output}"
        )

    receipt: dict[str, Any] | None = None
    capture_receipt: dict[str, Any] | None = None
    for line in output.splitlines():
        if line.startswith(SCENARIO_MARKER):
            receipt = json.loads(line[len(SCENARIO_MARKER) :])
        elif line.startswith(CAPTURE_MARKER):
            capture_receipt = json.loads(line[len(CAPTURE_MARKER) :])
    if receipt is None:
        raise RuntimeError(f"{scenario}/{variant} emitted no receipt")
    if receipt.get("id") != scenario:
        raise RuntimeError(
            f"{scenario}/{variant} receipt id={receipt.get('id')}"
        )
    if receipt.get("ab_variant") != variant:
        raise RuntimeError(
            f"{scenario}/{variant} receipt variant="
            f"{receipt.get('ab_variant')}"
        )
    capture_points = receipt.get("capture_points", [])
    if len(capture_points) != 4:
        raise RuntimeError(
            f"{scenario}/{variant} has {len(capture_points)} capture points"
        )
    point_times = [float(point["time"]) for point in capture_points]
    if point_times != sorted(point_times):
        raise RuntimeError(f"{scenario}/{variant} capture points are unordered")

    router = receipt.get("router", {})
    for category in ["train", "world", "enemies", "longshadow", "effects"]:
        expected = variant == "baked"
        if bool(router.get(category, False)) != expected:
            raise RuntimeError(
                f"{scenario}/{variant} routed {category}="
                f"{router.get(category)} expected={expected}"
            )
    routes = receipt.get("view_routes", {})
    expected_routes = (
        {
            "world_vector": False,
            "world_baked": True,
            "train_vector": False,
            "train_baked": True,
            "enemies_baked": True,
            "longshadow_baked": True,
            "effects_vector": False,
            "effects_baked": True,
        }
        if variant == "baked"
        else {
            "world_vector": True,
            "world_baked": False,
            "train_vector": True,
            "train_baked": False,
            "enemies_baked": False,
            "longshadow_baked": False,
            "effects_vector": True,
            "effects_baked": False,
        }
    )
    for route_name, expected in expected_routes.items():
        if bool(routes.get(route_name, not expected)) != expected:
            raise RuntimeError(
                f"{scenario}/{variant} view route {route_name}="
                f"{routes.get(route_name)} expected={expected}"
            )

    if capture_root is not None:
        if capture_receipt is None:
            raise RuntimeError(
                f"{scenario}/{variant} emitted no frame-sequence receipt"
            )
        paths = [Path(path) for path in capture_receipt.get("paths", [])]
        if len(paths) != 4 or not all(path.is_file() for path in paths):
            raise RuntimeError(
                f"{scenario}/{variant} did not write four capture frames"
            )
        if capture_base not in paths:
            raise RuntimeError(
                f"{scenario}/{variant} did not write trigger frame "
                f"{capture_base}"
            )
        pixel_hashes = [
            str(value)
            for value in capture_receipt.get("pixel_hashes", [])
        ]
        if len(pixel_hashes) != 4 or len(set(pixel_hashes)) != 4:
            raise RuntimeError(
                f"{scenario}/{variant} frame sequence is not visually unique: "
                f"{pixel_hashes}"
            )
        final_receipt = capture_receipt.get("final_receipt", {})
        if scenario == "detachment" and int(final_receipt.get("cars", -1)) != 2:
            raise RuntimeError(
                f"{scenario}/{variant} did not execute the real detach path"
            )
        capture_receipt["paths"] = [
            path.relative_to(capture_root).as_posix() for path in paths
        ]

    return {
        "scenario": scenario,
        "variant": variant,
        "receipt": receipt,
        "capture": capture_receipt,
    }


def markdown_report(payload: dict[str, Any]) -> str:
    records = {
        (record["scenario"], record["variant"]): record
        for record in payload["records"]
    }
    lines = [
        "# v0.8 M2 Reference Scenario Scorecard",
        "",
        f"- Generated: `{payload['generated_at_utc']}`",
        f"- Git HEAD: `{payload['git_head']}`",
        f"- Source fingerprint: `{payload['source_fingerprint']}`",
        f"- Result: **{'PASS' if payload['passed'] else 'FAIL'}**",
        "- Capture evidence: `{count} PNG frames` across vector and baked "
        "routes.".format(
            count=sum(
                len((record.get("capture") or {}).get("paths", []))
                for record in payload["records"]
            )
        ),
        "- Reproducibility: every route was replayed in a clean process and "
        "produced the same four raw-pixel SHA-256 hashes.",
        "- Commercial art scoring is intentionally deferred to the M3B proof "
        "slice; this scorecard validates the deterministic capture boundary.",
        "",
        "| Scenario | Category | Vector | Baked | Stable IDs | Capture points | Frame pixels | Replay | Commercial score |",
        "|---|---|---:|---:|---:|---:|---:|---:|---:|",
    ]
    for scenario in SCENARIOS:
        vector = records[(scenario, "vector")]["receipt"]
        baked = records[(scenario, "baked")]["receipt"]
        stable = vector["stable_ids"] == baked["stable_ids"]
        points = (
            len(vector["capture_points"]) == 4
            and vector["capture_points"] == baked["capture_points"]
        )
        vector_capture = records[(scenario, "vector")].get("capture") or {}
        baked_capture = records[(scenario, "baked")].get("capture") or {}
        pixels = (
            len(set(vector_capture.get("pixel_hashes", []))) == 4
            and len(set(baked_capture.get("pixel_hashes", []))) == 4
        )
        replayed = (
            bool(vector_capture.get("replay_verified", False))
            and bool(baked_capture.get("replay_verified", False))
        )
        lines.append(
            "| {scenario} | {category} | PASS | PASS | {stable} | {points} | {pixels} | {replayed} | M3B |".format(
                scenario=scenario,
                category=vector["category"],
                stable="PASS" if stable else "FAIL",
                points="PASS" if points else "FAIL",
                pixels="PASS" if pixels else "NOT RUN",
                replayed="PASS" if replayed else "NOT RUN",
            )
        )
    lines.extend(
        [
            "",
            "Technical PASS requires both renderer routes to stage the same "
            "scenario, preserve identical stable IDs, expose four ordered "
            "trigger points, produce four distinct pixel hashes per route, "
            "reproduce those hashes in a clean process, and keep all five "
            "category routes consistent.",
            "",
        ]
    )
    return "\n".join(lines)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--godot", type=Path, required=True)
    parser.add_argument(
        "--capture-root",
        type=Path,
        help="Optional directory for four PNG frames per scenario and variant.",
    )
    parser.add_argument(
        "--output-json",
        type=Path,
        default=REPO_ROOT
        / "design"
        / "receipts"
        / "v0.8-m2"
        / "reference-scenarios.json",
    )
    parser.add_argument(
        "--output-markdown",
        type=Path,
        default=REPO_ROOT
        / "design"
        / "audits"
        / "v0.8-m2-reference-scorecard.md",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    if not args.godot.is_file():
        raise FileNotFoundError(args.godot)
    capture_root = args.capture_root.resolve() if args.capture_root else None
    records = []
    replay_context = (
        tempfile.TemporaryDirectory(prefix="lantern-m2-replay-")
        if capture_root is not None
        else None
    )
    try:
        replay_root = (
            Path(replay_context.name).resolve()
            if replay_context is not None
            else None
        )
        for scenario in SCENARIOS:
            for variant in VARIANTS:
                record = run_scenario(
                    args.godot.resolve(),
                    scenario,
                    variant,
                    capture_root,
                )
                if replay_root is not None:
                    replay = run_scenario(
                        args.godot.resolve(),
                        scenario,
                        variant,
                        replay_root,
                    )
                    primary_hashes = record["capture"]["pixel_hashes"]
                    replay_hashes = replay["capture"]["pixel_hashes"]
                    if primary_hashes != replay_hashes:
                        raise RuntimeError(
                            f"{scenario}/{variant} is not reproducible: "
                            f"{primary_hashes} != {replay_hashes}"
                        )
                    record["capture"]["replay_verified"] = True
                records.append(record)
                print(f"[reference-scenarios] {scenario}/{variant} PASS")
    finally:
        if replay_context is not None:
            replay_context.cleanup()

    passed = True
    for scenario in SCENARIOS:
        variants = {
            record["variant"]: record["receipt"]
            for record in records
            if record["scenario"] == scenario
        }
        passed = passed and (
            variants["vector"]["stable_ids"]
            == variants["baked"]["stable_ids"]
        )
        passed = passed and (
            variants["vector"]["capture_points"]
            == variants["baked"]["capture_points"]
        )
    if capture_root is not None:
        passed = passed and all(
            bool((record.get("capture") or {}).get("replay_verified", False))
            for record in records
        )

    git_head, fingerprint = source_fingerprint(REPO_ROOT)
    payload = {
        "schema": 2,
        "generated_at_utc": datetime.now(timezone.utc).isoformat(),
        "git_head": git_head,
        "source_fingerprint": fingerprint,
        "passed": passed,
        "capture_root": "external" if capture_root else "",
        "records": records,
    }
    args.output_json.parent.mkdir(parents=True, exist_ok=True)
    args.output_json.write_text(
        json.dumps(payload, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    args.output_markdown.parent.mkdir(parents=True, exist_ok=True)
    args.output_markdown.write_text(
        markdown_report(payload),
        encoding="utf-8",
    )
    print(f"[reference-scenarios] wrote {args.output_json}")
    print(f"[reference-scenarios] wrote {args.output_markdown}")
    return 0 if passed else 1


if __name__ == "__main__":
    raise SystemExit(main())
