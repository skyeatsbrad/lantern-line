from __future__ import annotations

import argparse
import json
import os
import subprocess
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from source_fingerprint import source_fingerprint


REPO_ROOT = Path(__file__).resolve().parents[2]
PROFILES = ["high", "medium", "low", "vector_fallback"]
MARKER = "[probe] presentation_json "


def run_profile(godot: Path, profile: str) -> dict[str, Any]:
    env = os.environ.copy()
    env["LANTERN_PROBE"] = "1"
    env["LANTERN_METRICS_WARMUP"] = "2"
    env["LANTERN_PRESENTATION_PROFILE"] = profile
    for name in [
        "LANTERN_PROBE_DENSE_COMBAT",
        "LANTERN_PROBE_AUDIO",
        "LANTERN_VISUAL_BENCHMARK",
    ]:
        env.pop(name, None)
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
        timeout=35.0,
    )
    output = "\n".join(part for part in [result.stdout, result.stderr] if part)
    if result.returncode != 0:
        raise RuntimeError(f"{profile} probe failed:\n{output}")
    for line in output.splitlines():
        if not line.startswith(MARKER):
            continue
        metrics = json.loads(line[len(MARKER) :])
        if metrics.get("warming_up", False):
            raise RuntimeError(f"{profile} probe remained in warm-up")
        if metrics.get("profile") != profile:
            raise RuntimeError(
                f"{profile} resolved as {metrics.get('profile')}"
            )
        return metrics
    raise RuntimeError(f"{profile} probe emitted no metrics")


def markdown_report(payload: dict[str, Any]) -> str:
    lines = [
        "# v0.8 Presentation Profile Matrix",
        "",
        f"- Generated: `{payload['generated_at_utc']}`",
        f"- Git HEAD: `{payload['git_head']}`",
        f"- Source fingerprint: `{payload['source_fingerprint']}`",
        "- Scenario: normal real-renderer gameplay probe after a two-second warm-up",
        "",
        "| Profile | FPS | Frame p95 | Frame p99 | Draw p95 | Draw max | Video MiB | Texture MiB |",
        "|---|---:|---:|---:|---:|---:|---:|---:|",
    ]
    for record in payload["records"]:
        metrics = record["metrics"]
        lines.append(
            "| {profile} | {fps:.1f} | {frame_p95_ms:.2f} ms | "
            "{frame_p99_ms:.2f} ms | {draw_calls_p95:.1f} | "
            "{draw_calls_max:.0f} | {video_memory_mib:.1f} | "
            "{texture_memory_mib:.1f} |".format(
                profile=record["profile"],
                fps=float(metrics["fps"]),
                frame_p95_ms=float(metrics["frame_p95_ms"]),
                frame_p99_ms=float(metrics["frame_p99_ms"]),
                draw_calls_p95=float(metrics["draw_calls_p95"]),
                draw_calls_max=float(metrics["draw_calls_max"]),
                video_memory_mib=float(metrics["video_memory_mib"]),
                texture_memory_mib=float(metrics["texture_memory_mib"]),
            )
        )
    lines.extend(
        [
            "",
            "The renderer remains the v0.7 vector implementation during M0, so "
            "matching cost is expected. This gate proves explicit profile "
            "selection, persistence normalization, scene boot, and metrics "
            "reporting before profile-specific views are introduced.",
            "",
        ]
    )
    return "\n".join(lines)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--godot", type=Path, required=True)
    parser.add_argument(
        "--output-json",
        type=Path,
        default=REPO_ROOT
        / "design"
        / "audits"
        / "v0.8-profile-matrix.json",
    )
    parser.add_argument(
        "--output-markdown",
        type=Path,
        default=REPO_ROOT
        / "design"
        / "audits"
        / "v0.8-profile-matrix.md",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    if not args.godot.is_file():
        raise FileNotFoundError(args.godot)
    records = []
    for profile in PROFILES:
        metrics = run_profile(args.godot, profile)
        records.append({"profile": profile, "metrics": metrics})
        print(
            "[profile-matrix] "
            f"{profile} p95={float(metrics['frame_p95_ms']):.2f}ms "
            f"draws={float(metrics['draw_calls_p95']):.1f}"
        )
    git_head, fingerprint = source_fingerprint(REPO_ROOT)
    payload = {
        "schema": 1,
        "generated_at_utc": datetime.now(timezone.utc).isoformat(),
        "git_head": git_head,
        "source_fingerprint": fingerprint,
        "records": records,
    }
    args.output_json.parent.mkdir(parents=True, exist_ok=True)
    args.output_json.write_text(
        json.dumps(payload, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    args.output_markdown.write_text(
        markdown_report(payload),
        encoding="utf-8",
    )
    print(f"[profile-matrix] wrote {args.output_markdown}")
    print(f"[profile-matrix] wrote {args.output_json}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
