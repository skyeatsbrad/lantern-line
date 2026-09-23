from __future__ import annotations

import argparse
import json
import os
import platform
import re
import statistics
import subprocess
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from source_fingerprint import source_fingerprint


REPO_ROOT = Path(__file__).resolve().parents[2]
MARKER = "[probe] visual_benchmark_json "
MODES = ["sprite", "hybrid", "runtime_3d"]
METRIC_FIELDS = [
    "fps",
    "average_frame_ms",
    "frame_p95_ms",
    "frame_p99_ms",
    "worst_frame_ms",
    "draw_calls_average",
    "draw_calls_p95",
    "draw_calls_max",
    "render_objects",
    "primitives",
    "nodes",
    "static_memory_mib",
    "video_memory_mib",
    "texture_memory_mib",
]


def run_text(command: list[str]) -> str:
    result = subprocess.run(
        command,
        cwd=REPO_ROOT,
        check=True,
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
    )
    return result.stdout.strip()


def parse_record(output: str) -> dict[str, Any]:
    for line in output.splitlines():
        if line.startswith(MARKER):
            return json.loads(line[len(MARKER) :])
    raise RuntimeError("Visual benchmark JSON marker was not emitted")


def benchmark_run(
    godot: Path,
    mode: str,
    scenario: str,
    enemy_count: int,
    boss_active: bool,
    duration_seconds: float,
    warmup_seconds: float,
    capture_path: Path | None,
) -> dict[str, Any]:
    env = os.environ.copy()
    env["LANTERN_VISUAL_BENCHMARK"] = mode
    env["LANTERN_VISUAL_BENCHMARK_ENEMIES"] = str(enemy_count)
    env["LANTERN_VISUAL_BENCHMARK_BOSS"] = "1" if boss_active else "0"
    env["LANTERN_VISUAL_BENCHMARK_SECONDS"] = str(duration_seconds)
    env["LANTERN_METRICS_WARMUP"] = str(warmup_seconds)
    if capture_path is not None:
        capture_path.parent.mkdir(parents=True, exist_ok=True)
        env["LANTERN_VISUAL_BENCHMARK_CAPTURE"] = str(capture_path)
    else:
        env.pop("LANTERN_VISUAL_BENCHMARK_CAPTURE", None)
    command = [
        str(godot),
        "--path",
        str(REPO_ROOT),
        "--rendering-method",
        "gl_compatibility",
        "--disable-vsync",
        "--display-driver",
        "windows",
        "--audio-driver",
        "Dummy",
    ]
    result = subprocess.run(
        command,
        cwd=REPO_ROOT,
        env=env,
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
        timeout=duration_seconds + 25.0,
    )
    output = "\n".join(part for part in [result.stdout, result.stderr] if part)
    if result.returncode != 0:
        raise RuntimeError(
            f"{mode}/{scenario} exited {result.returncode}\n{output}"
        )
    record = parse_record(output)
    metrics = record.get("metrics")
    if not isinstance(metrics, dict):
        raise RuntimeError(f"{mode}/{scenario} emitted no metrics object")
    if metrics.get("warming_up", False):
        raise RuntimeError(
            f"{mode}/{scenario} ended before metrics completed warm-up"
        )
    missing_fields = [
        field for field in METRIC_FIELDS if field not in metrics
    ]
    if missing_fields:
        raise RuntimeError(
            f"{mode}/{scenario} omitted metrics: {missing_fields}"
        )
    record["scenario"] = scenario
    gpu_match = re.search(
        r"OpenGL API .+?Using Device: (?P<gpu>.+)",
        output,
    )
    record["gpu"] = gpu_match.group("gpu").strip() if gpu_match else "unknown"
    return record


def summarize(records: list[dict[str, Any]]) -> list[dict[str, Any]]:
    summaries: list[dict[str, Any]] = []
    keys = sorted({(item["scenario"], item["mode"]) for item in records})
    for scenario, mode in keys:
        group = [
            item
            for item in records
            if item["scenario"] == scenario and item["mode"] == mode
        ]
        summary: dict[str, Any] = {
            "scenario": scenario,
            "mode": mode,
            "runs": len(group),
            "enemy_count": group[0]["enemy_count"],
            "boss_active": group[0]["boss_active"],
        }
        for field in METRIC_FIELDS:
            values = [
                float(item["metrics"].get(field, 0.0))
                for item in group
            ]
            summary[field] = statistics.median(values)
        summaries.append(summary)
    return summaries


def markdown_report(payload: dict[str, Any]) -> str:
    lines = [
        "# v0.8 Visual Architecture Benchmark",
        "",
        f"- Generated: `{payload['generated_at_utc']}`",
        f"- Godot: `{payload['godot_version']}`",
        f"- GPU: `{payload['gpu']}`",
        f"- Git HEAD: `{payload['git_head']}`",
        f"- Source fingerprint: `{payload['source_fingerprint']}`",
        (
            "- Measurement: "
            f"{payload['measure_seconds']:.0f}s after "
            f"{payload['warmup_seconds']:.0f}s warm-up"
        ),
        "",
        "| Scenario | Mode | Runs | FPS | Frame p95 | Frame p99 | Worst | Draw p95 | Draw max | Video MiB | Texture MiB |",
        "|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|",
    ]
    for row in payload["summaries"]:
        lines.append(
            "| {scenario} | {mode} | {runs} | {fps:.1f} | "
            "{frame_p95_ms:.2f} ms | {frame_p99_ms:.2f} ms | "
            "{worst_frame_ms:.2f} ms | {draw_calls_p95:.1f} | "
            "{draw_calls_max:.0f} | {video_memory_mib:.1f} | "
            "{texture_memory_mib:.1f} |".format(**row)
        )
    lines.extend(
        [
            "",
            "## Interpretation",
            "",
            "This synthetic scene compares rendering architecture cost, not final-art quality. "
            "All modes use the same five-car HUD, effects overlay, threat count, timing, "
            "Compatibility renderer, and presentation profile.",
            "",
            "- `sprite`: layered baked-sprite proxy with 2D lights.",
            "- `hybrid`: layered sprite entities over a half-resolution live-3D environment; the boss is live 3D.",
            "- `runtime_3d`: live 3D environment, train, threats, lights, and shadows.",
            "",
        ]
    )
    return "\n".join(lines)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--godot", type=Path, required=True)
    parser.add_argument("--measure-seconds", type=float, default=30.0)
    parser.add_argument("--warmup-seconds", type=float, default=2.0)
    parser.add_argument("--pressure-runs", type=int, default=3)
    parser.add_argument("--headroom-runs", type=int, default=1)
    parser.add_argument("--boss-runs", type=int, default=1)
    parser.add_argument("--retries", type=int, default=1)
    parser.add_argument("--resume", action="store_true")
    parser.add_argument("--refresh-metadata-only", action="store_true")
    parser.add_argument(
        "--output-json",
        type=Path,
        default=REPO_ROOT / "design" / "audits" / "v0.8-visual-benchmark.json",
    )
    parser.add_argument(
        "--output-markdown",
        type=Path,
        default=REPO_ROOT / "design" / "audits" / "v0.8-visual-benchmark.md",
    )
    parser.add_argument(
        "--receipt-dir",
        type=Path,
        default=REPO_ROOT / "design" / "receipts" / "v0.8-benchmark",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    if not args.godot.is_file():
        raise FileNotFoundError(args.godot)
    if args.measure_seconds <= 0.0 or args.warmup_seconds < 0.0:
        raise ValueError("Benchmark durations must be positive")
    if args.refresh_metadata_only:
        if not args.output_json.is_file():
            raise FileNotFoundError(args.output_json)
        payload = json.loads(args.output_json.read_text(encoding="utf-8"))
        git_head, fingerprint = source_fingerprint(REPO_ROOT)
        payload["git_head"] = git_head
        payload["source_fingerprint"] = fingerprint
        payload.pop("working_tree_fingerprint", None)
        args.output_json.write_text(
            json.dumps(payload, indent=2, sort_keys=True) + "\n",
            encoding="utf-8",
        )
        args.output_markdown.write_text(
            markdown_report(payload),
            encoding="utf-8",
        )
        print(
            "[visual-benchmark] refreshed source fingerprint "
            f"{fingerprint}"
        )
        return 0
    scenarios = [
        ("pressure12", 12, False, max(0, args.pressure_runs)),
        ("headroom16", 16, False, max(0, args.headroom_runs)),
        ("boss", 0, True, max(0, args.boss_runs)),
    ]
    duration_seconds = args.measure_seconds + args.warmup_seconds
    partial_path = args.output_json.with_suffix(args.output_json.suffix + ".partial")
    records: list[dict[str, Any]] = []
    if args.resume and partial_path.is_file():
        partial = json.loads(partial_path.read_text(encoding="utf-8"))
        records = list(partial.get("records", []))
        print(
            f"[visual-benchmark] resumed records={len(records)} "
            f"from {partial_path}"
        )
    completed = {
        (item["scenario"], item["mode"], int(item["run"]))
        for item in records
    }
    for scenario_index, scenario_spec in enumerate(scenarios):
        scenario, enemy_count, boss_active, run_count = scenario_spec
        for run_index in range(run_count):
            rotation = (scenario_index + run_index) % len(MODES)
            mode_order = MODES[rotation:] + MODES[:rotation]
            for mode in mode_order:
                run_number = run_index + 1
                if (scenario, mode, run_number) in completed:
                    continue
                capture_path = (
                    args.receipt_dir / f"{scenario}-{mode}.png"
                    if run_index == 0
                    else None
                )
                record: dict[str, Any] | None = None
                for attempt in range(max(0, args.retries) + 1):
                    try:
                        record = benchmark_run(
                            args.godot,
                            mode,
                            scenario,
                            enemy_count,
                            boss_active,
                            duration_seconds,
                            args.warmup_seconds,
                            capture_path,
                        )
                        break
                    except (RuntimeError, subprocess.TimeoutExpired) as error:
                        if attempt >= max(0, args.retries):
                            raise
                        print(
                            "[visual-benchmark] retry "
                            f"{scenario}/{mode} run={run_number} "
                            f"after {type(error).__name__}"
                        )
                if record is None:
                    raise RuntimeError(
                        f"{scenario}/{mode} produced no benchmark record"
                    )
                record["run"] = run_number
                records.append(record)
                completed.add((scenario, mode, run_number))
                partial_path.parent.mkdir(parents=True, exist_ok=True)
                partial_path.write_text(
                    json.dumps(
                        {
                            "measure_seconds": args.measure_seconds,
                            "warmup_seconds": args.warmup_seconds,
                            "records": records,
                        },
                        indent=2,
                        sort_keys=True,
                    )
                    + "\n",
                    encoding="utf-8",
                )
                metrics = record["metrics"]
                print(
                    "[visual-benchmark] "
                    f"{scenario}/{mode} run={run_number} "
                    f"p95={float(metrics['frame_p95_ms']):.2f}ms "
                    f"draws={float(metrics['draw_calls_p95']):.1f} "
                    f"video={float(metrics['video_memory_mib']):.1f}MiB"
                )
    if not records:
        raise RuntimeError("No benchmark runs were requested")
    git_head, fingerprint = source_fingerprint(REPO_ROOT)
    payload = {
        "schema": 1,
        "generated_at_utc": datetime.now(timezone.utc).isoformat(),
        "platform": platform.platform(),
        "godot_version": run_text([str(args.godot), "--version"]),
        "gpu": records[0]["gpu"],
        "git_head": git_head,
        "source_fingerprint": fingerprint,
        "measure_seconds": args.measure_seconds,
        "warmup_seconds": args.warmup_seconds,
        "records": records,
        "summaries": summarize(records),
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
    print(f"[visual-benchmark] wrote {args.output_markdown}")
    print(f"[visual-benchmark] wrote {args.output_json}")
    if partial_path.is_file():
        partial_path.unlink()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
