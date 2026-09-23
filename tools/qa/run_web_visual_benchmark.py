from __future__ import annotations

import argparse
import http.server
import json
import socket
import statistics
import threading
from contextlib import contextmanager
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Iterator
from urllib.parse import urlencode

from playwright.sync_api import Browser, Page, sync_playwright

from source_fingerprint import source_fingerprint


REPO_ROOT = Path(__file__).resolve().parents[2]
WEB_ROOT = REPO_ROOT / "build" / "web-benchmark"
MODES = ["sprite", "hybrid", "runtime_3d"]
VIEWPORTS = [
    ("desktop", 1280, 720),
    ("mobile_landscape", 844, 390),
]
REQUIRED_METRICS = [
    "fps",
    "frame_p95_ms",
    "frame_p99_ms",
    "draw_calls_p95",
    "draw_calls_max",
    "video_memory_mib",
    "texture_memory_mib",
]


class QuietHandler(http.server.SimpleHTTPRequestHandler):
    def log_message(self, _format: str, *args: object) -> None:
        return


def free_port() -> int:
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as server:
        server.bind(("127.0.0.1", 0))
        return int(server.getsockname()[1])


@contextmanager
def serve(directory: Path) -> Iterator[str]:
    port = free_port()
    handler = lambda *args, **kwargs: QuietHandler(  # noqa: E731
        *args,
        directory=str(directory),
        **kwargs,
    )
    server = http.server.ThreadingHTTPServer(("127.0.0.1", port), handler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    try:
        yield f"http://127.0.0.1:{port}"
    finally:
        server.shutdown()
        thread.join(timeout=5.0)
        server.server_close()


def inspect_webgl(page: Page) -> dict[str, Any]:
    return page.evaluate(
        """
        () => {
          const canvas = document.createElement("canvas");
          const gl = canvas.getContext("webgl2");
          if (!gl) return {webgl2: false};
          const debug = gl.getExtension("WEBGL_debug_renderer_info");
          const gameCanvas = document.querySelector("canvas");
          const bounds = gameCanvas ? gameCanvas.getBoundingClientRect() : null;
          return {
            webgl2: true,
            vendor: debug ? gl.getParameter(debug.UNMASKED_VENDOR_WEBGL) : gl.getParameter(gl.VENDOR),
            renderer: debug ? gl.getParameter(debug.UNMASKED_RENDERER_WEBGL) : gl.getParameter(gl.RENDERER),
            version: gl.getParameter(gl.VERSION),
            shading_language: gl.getParameter(gl.SHADING_LANGUAGE_VERSION),
            device_pixel_ratio: window.devicePixelRatio,
            canvas_css_width: bounds ? bounds.width : 0,
            canvas_css_height: bounds ? bounds.height : 0,
            canvas_width: gameCanvas ? gameCanvas.width : 0,
            canvas_height: gameCanvas ? gameCanvas.height : 0,
            user_agent: navigator.userAgent,
          };
        }
        """
    )


def run_case(
    browser: Browser,
    base_url: str,
    viewport_name: str,
    width: int,
    height: int,
    mode: str,
    duration_seconds: float,
    warmup_seconds: float,
    receipt_dir: Path,
) -> dict[str, Any]:
    context = browser.new_context(
        viewport={"width": width, "height": height},
        device_scale_factor=1,
        reduced_motion="no-preference",
    )
    page = context.new_page()
    console_errors: list[str] = []
    page_errors: list[str] = []
    page.on(
        "console",
        lambda message: (
            console_errors.append(message.text)
            if message.type == "error"
            else None
        ),
    )
    page.on("pageerror", lambda error: page_errors.append(str(error)))
    query = urlencode(
        {
            "benchmark": mode,
            "benchmark_enemies": 12,
            "benchmark_boss": 0,
            "benchmark_seconds": duration_seconds,
        }
    )
    page.goto(f"{base_url}/index.html?{query}", wait_until="load")
    page.wait_for_function(
        "() => window.__lanternBenchmarkResult !== undefined",
        timeout=(duration_seconds + 45.0) * 1000.0,
    )
    record = page.evaluate("() => window.__lanternBenchmarkResult")
    webgl = inspect_webgl(page)
    receipt_dir.mkdir(parents=True, exist_ok=True)
    page.screenshot(
        path=str(receipt_dir / f"{viewport_name}-{mode}.png"),
        full_page=True,
    )
    context.close()
    if page_errors:
        raise RuntimeError(
            f"{viewport_name}/{mode} page errors: {page_errors}"
        )
    metrics = record.get("metrics") if isinstance(record, dict) else None
    if not isinstance(metrics, dict):
        raise RuntimeError(f"{viewport_name}/{mode} emitted no metrics")
    if metrics.get("warming_up", False):
        raise RuntimeError(f"{viewport_name}/{mode} remained in warm-up")
    missing = [field for field in REQUIRED_METRICS if field not in metrics]
    if missing:
        raise RuntimeError(
            f"{viewport_name}/{mode} omitted metrics: {missing}"
        )
    if not webgl.get("webgl2", False):
        raise RuntimeError(f"{viewport_name}/{mode} lacked WebGL 2")
    record["viewport"] = viewport_name
    record["viewport_width"] = width
    record["viewport_height"] = height
    record["webgl"] = webgl
    record["console_errors"] = console_errors
    return record


def verify_production_gate(
    browser: Browser,
    base_url: str,
    receipt_dir: Path,
) -> dict[str, Any]:
    context = browser.new_context(
        viewport={"width": 1280, "height": 720},
        device_scale_factor=1,
    )
    page = context.new_page()
    console_messages: list[str] = []
    page_errors: list[str] = []
    page.on("console", lambda message: console_messages.append(message.text))
    page.on("pageerror", lambda error: page_errors.append(str(error)))
    query = urlencode(
        {
            "benchmark": "sprite",
            "benchmark_enemies": 12,
            "benchmark_seconds": 4,
        }
    )
    page.goto(f"{base_url}/index.html?{query}", wait_until="load")
    page.wait_for_timeout(2500)
    result_exists = page.evaluate(
        "() => window.__lanternBenchmarkResult !== undefined"
    )
    receipt_dir.mkdir(parents=True, exist_ok=True)
    page.screenshot(
        path=str(receipt_dir / "production-query-gate.png"),
        full_page=True,
    )
    context.close()
    if page_errors:
        raise RuntimeError(f"Production Web page errors: {page_errors}")
    if result_exists or any(
        "[main] running runtime probe" in message
        for message in console_messages
    ):
        raise RuntimeError(
            "Production Web export accepted the visual benchmark query"
        )
    return {
        "blocked": True,
        "console_messages": console_messages,
        "page_errors": page_errors,
    }


def summaries(records: list[dict[str, Any]]) -> list[dict[str, Any]]:
    output: list[dict[str, Any]] = []
    for viewport_name, _, _ in VIEWPORTS:
        for mode in MODES:
            group = [
                record
                for record in records
                if record["viewport"] == viewport_name
                and record["mode"] == mode
            ]
            if not group:
                continue
            metrics = group[0]["metrics"]
            output.append(
                {
                    "viewport": viewport_name,
                    "mode": mode,
                    "runs": len(group),
                    "fps": statistics.median(
                        float(record["metrics"]["fps"])
                        for record in group
                    ),
                    "frame_p95_ms": statistics.median(
                        float(record["metrics"]["frame_p95_ms"])
                        for record in group
                    ),
                    "frame_p99_ms": statistics.median(
                        float(record["metrics"]["frame_p99_ms"])
                        for record in group
                    ),
                    "draw_calls_p95": statistics.median(
                        float(record["metrics"]["draw_calls_p95"])
                        for record in group
                    ),
                    "draw_calls_max": statistics.median(
                        float(record["metrics"]["draw_calls_max"])
                        for record in group
                    ),
                    "video_memory_mib": statistics.median(
                        float(record["metrics"]["video_memory_mib"])
                        for record in group
                    ),
                    "texture_memory_mib": statistics.median(
                        float(record["metrics"]["texture_memory_mib"])
                        for record in group
                    ),
                    "canvas": (
                        f"{int(group[0]['webgl']['canvas_width'])}x"
                        f"{int(group[0]['webgl']['canvas_height'])}"
                    ),
                    "renderer": group[0]["webgl"]["renderer"],
                    "console_errors": sum(
                        len(record["console_errors"]) for record in group
                    ),
                    "measurement_seconds": float(
                        metrics.get("measurement_seconds", 0.0)
                    ),
                }
            )
    return output


def markdown_report(payload: dict[str, Any]) -> str:
    lines = [
        "# v0.8 WebGL 2 Visual Benchmark",
        "",
        f"- Generated: `{payload['generated_at_utc']}`",
        f"- Browser: `{payload['browser']}`",
        f"- WebGL renderer: `{payload['webgl_renderer']}`",
        f"- Git HEAD: `{payload['git_head']}`",
        f"- Source fingerprint: `{payload['source_fingerprint']}`",
        "- Production query gate: benchmark query blocked",
        (
            "- Measurement: "
            f"{payload['measure_seconds']:.0f}s after "
            f"{payload['warmup_seconds']:.0f}s warm-up"
        ),
        "",
        "| Viewport | Canvas | Mode | FPS | Frame p95 | Frame p99 | Draw p95 | Draw max | Video MiB | Errors |",
        "|---|---:|---|---:|---:|---:|---:|---:|---:|---:|",
    ]
    for row in payload["summaries"]:
        lines.append(
            "| {viewport} | {canvas} | {mode} | {fps:.1f} | "
            "{frame_p95_ms:.2f} ms | {frame_p99_ms:.2f} ms | "
            "{draw_calls_p95:.1f} | {draw_calls_max:.0f} | "
            "{video_memory_mib:.1f} | {console_errors} |".format(**row)
        )
    lines.extend(
        [
            "",
            "The browser run is a WebGL 2 compatibility and responsive-layout gate. "
            "Browser animation scheduling is vsync-bound, so the uncapped native matrix "
            "remains the architecture cost comparison.",
            "",
        ]
    )
    return "\n".join(lines)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--browser", type=Path, required=True)
    parser.add_argument("--web-root", type=Path, default=WEB_ROOT)
    parser.add_argument(
        "--production-web-root",
        type=Path,
        default=REPO_ROOT / "build" / "web",
    )
    parser.add_argument("--measure-seconds", type=float, default=10.0)
    parser.add_argument("--warmup-seconds", type=float, default=2.0)
    parser.add_argument("--runs", type=int, default=1)
    parser.add_argument("--refresh-metadata-only", action="store_true")
    parser.add_argument(
        "--output-json",
        type=Path,
        default=REPO_ROOT
        / "design"
        / "audits"
        / "v0.8-web-visual-benchmark.json",
    )
    parser.add_argument(
        "--output-markdown",
        type=Path,
        default=REPO_ROOT
        / "design"
        / "audits"
        / "v0.8-web-visual-benchmark.md",
    )
    parser.add_argument(
        "--receipt-dir",
        type=Path,
        default=REPO_ROOT / "design" / "receipts" / "v0.8-web-benchmark",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    if not args.browser.is_file():
        raise FileNotFoundError(args.browser)
    if args.refresh_metadata_only:
        if not args.output_json.is_file():
            raise FileNotFoundError(args.output_json)
        payload = json.loads(args.output_json.read_text(encoding="utf-8"))
        git_head, fingerprint = source_fingerprint(REPO_ROOT)
        payload["git_head"] = git_head
        payload["source_fingerprint"] = fingerprint
        args.output_json.write_text(
            json.dumps(payload, indent=2, sort_keys=True) + "\n",
            encoding="utf-8",
        )
        args.output_markdown.write_text(
            markdown_report(payload),
            encoding="utf-8",
        )
        print(
            "[web-visual-benchmark] refreshed source fingerprint "
            f"{fingerprint}"
        )
        return 0
    web_root = args.web_root.resolve()
    production_web_root = args.production_web_root.resolve()
    if not (web_root / "index.html").is_file():
        raise FileNotFoundError(
            "Export the Web Benchmark preset before running the browser benchmark"
        )
    if not (production_web_root / "index.html").is_file():
        raise FileNotFoundError(
            "Export the production Web preset before running the browser benchmark"
        )
    duration_seconds = args.measure_seconds + args.warmup_seconds
    records: list[dict[str, Any]] = []
    with sync_playwright() as playwright:
        browser = playwright.chromium.launch(
            executable_path=str(args.browser),
            headless=True,
            args=[
                "--enable-gpu",
                "--enable-webgl",
                "--ignore-gpu-blocklist",
                "--use-angle=d3d11",
            ],
        )
        try:
            with serve(production_web_root) as production_url:
                production_gate = verify_production_gate(
                    browser,
                    production_url,
                    args.receipt_dir,
                )
            with serve(web_root) as base_url:
                for run_index in range(max(1, args.runs)):
                    for viewport_name, width, height in VIEWPORTS:
                        rotation = (
                            run_index
                            + (1 if viewport_name == "mobile_landscape" else 0)
                        ) % len(MODES)
                        mode_order = MODES[rotation:] + MODES[:rotation]
                        for mode in mode_order:
                            record = run_case(
                                browser,
                                base_url,
                                viewport_name,
                                width,
                                height,
                                mode,
                                duration_seconds,
                                args.warmup_seconds,
                                args.receipt_dir,
                            )
                            record["run"] = run_index + 1
                            records.append(record)
                            metrics = record["metrics"]
                            print(
                                "[web-visual-benchmark] "
                                f"{viewport_name}/{mode} "
                                f"p95={float(metrics['frame_p95_ms']):.2f}ms "
                                f"draws={float(metrics['draw_calls_p95']):.1f}"
                            )
        finally:
            browser.close()
    result_summaries = summaries(records)
    git_head, fingerprint = source_fingerprint(REPO_ROOT)
    payload = {
        "schema": 1,
        "generated_at_utc": datetime.now(timezone.utc).isoformat(),
        "browser": records[0]["webgl"]["user_agent"],
        "webgl_renderer": records[0]["webgl"]["renderer"],
        "git_head": git_head,
        "source_fingerprint": fingerprint,
        "measure_seconds": args.measure_seconds,
        "warmup_seconds": args.warmup_seconds,
        "production_query_gate": production_gate,
        "records": records,
        "summaries": result_summaries,
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
    print(f"[web-visual-benchmark] wrote {args.output_markdown}")
    print(f"[web-visual-benchmark] wrote {args.output_json}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
