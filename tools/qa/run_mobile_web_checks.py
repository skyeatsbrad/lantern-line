from __future__ import annotations

import argparse
import http.server
import json
import socket
import threading
from contextlib import contextmanager
from pathlib import Path
from typing import Any, Iterator
from urllib.request import urlopen

from playwright.sync_api import Browser, Page, sync_playwright


REPO_ROOT = Path(__file__).resolve().parents[2]


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


def attach_error_capture(page: Page) -> tuple[list[str], list[str]]:
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
    return console_errors, page_errors


def require(condition: bool, message: str) -> None:
    if not condition:
        raise RuntimeError(message)


def capture_title_overlays(page: Page, receipt_dir: Path) -> dict[str, str]:
    page.keyboard.press("Escape")
    page.wait_for_timeout(350)
    settings_path = receipt_dir / "settings-844x390.png"
    page.screenshot(path=str(settings_path), full_page=True)
    page.keyboard.press("Escape")
    page.wait_for_timeout(250)

    page.keyboard.press("h")
    page.wait_for_timeout(350)
    guide_path = receipt_dir / "guide-844x390.png"
    page.screenshot(path=str(guide_path), full_page=True)
    page.keyboard.press("Escape")
    page.wait_for_timeout(250)
    return {
        "settings": str(settings_path),
        "guide": str(guide_path),
    }


def check_landscape_launch(
    browser: Browser,
    base_url: str,
    receipt_dir: Path,
) -> dict[str, Any]:
    context = browser.new_context(
        viewport={"width": 844, "height": 390},
        device_scale_factor=1,
        has_touch=True,
    )
    page = context.new_page()
    console_errors, page_errors = attach_error_capture(page)
    page.goto(f"{base_url}/index.html", wait_until="load")
    launch_button = page.locator("#launch-button")
    require(launch_button.is_visible(), "touch launch action was not visible")
    bounds = launch_button.bounding_box()
    require(bounds is not None, "touch launch action had no hit region")
    require(bounds["height"] >= 48, "touch launch action was below 48 CSS pixels")
    viewport_meta = page.locator('meta[name="viewport"]').get_attribute("content") or ""
    require("viewport-fit=cover" in viewport_meta, "viewport-fit=cover was missing")
    bridge = page.evaluate(
        """() => ({
          present: Boolean(window.LanternPlatform),
          safe: window.LanternPlatform?.safeInsets?.(),
          viewport: window.LanternPlatform?.viewportSize?.(),
        })"""
    )
    require(bridge.get("present", False), "WebPlatformBridge shell API was missing")
    require(
        set((bridge.get("safe") or {}).keys()) == {"left", "top", "right", "bottom"},
        "safe-area bridge did not expose four insets",
    )
    receipt_dir.mkdir(parents=True, exist_ok=True)
    page.screenshot(path=str(receipt_dir / "launch-844x390.png"), full_page=True)
    launch_button.click()
    page.wait_for_selector("#status", state="detached", timeout=60000)
    page.wait_for_timeout(500)
    rotate_display = page.locator("#rotate").evaluate(
        "(element) => getComputedStyle(element).display"
    )
    require(rotate_display == "none", "landscape viewport showed rotate overlay")
    canvas = page.locator("#canvas").bounding_box()
    require(canvas is not None, "game canvas was not visible after launch")
    require(canvas["width"] >= 840 and canvas["height"] >= 386, "canvas did not fill viewport")
    page.screenshot(path=str(receipt_dir / "game-844x390.png"), full_page=True)
    overlays = capture_title_overlays(page, receipt_dir)
    page.evaluate(
        "() => navigator.serviceWorker.ready.then(() => true)"
    )
    page.reload(wait_until="load")
    page.wait_for_function(
        "() => Boolean(navigator.serviceWorker.controller)",
        timeout=15000,
    )
    page.locator("#launch-button").click()
    page.wait_for_selector("#status", state="detached", timeout=60000)
    context.set_offline(True)
    page.reload(wait_until="domcontentloaded")
    require(
        page.locator("#launch-button").is_visible(),
        "cached launch shell was unavailable offline",
    )
    page.locator("#launch-button").click()
    page.wait_for_selector("#status", state="detached", timeout=60000)
    page.screenshot(
        path=str(receipt_dir / "offline-game-844x390.png"),
        full_page=True,
    )
    context.set_offline(False)
    context.close()
    require(not page_errors, f"landscape page errors: {page_errors}")
    require(not console_errors, f"landscape console errors: {console_errors}")
    return {
        "launch_target": bounds,
        "bridge": bridge,
        "canvas": canvas,
        "overlays": overlays,
        "offline_cached_start": True,
        "page_errors": page_errors,
        "console_errors": console_errors,
    }


def check_portrait_overlay(
    browser: Browser,
    base_url: str,
    receipt_dir: Path,
) -> dict[str, Any]:
    context = browser.new_context(
        viewport={"width": 390, "height": 844},
        device_scale_factor=1,
        has_touch=True,
    )
    page = context.new_page()
    console_errors, page_errors = attach_error_capture(page)
    page.goto(f"{base_url}/index.html?autostart=1", wait_until="load")
    page.wait_for_timeout(500)
    rotate_display = page.locator("#rotate").evaluate(
        "(element) => getComputedStyle(element).display"
    )
    require(rotate_display == "flex", "portrait touch viewport lacked rotate overlay")
    page.screenshot(path=str(receipt_dir / "rotate-390x844.png"), full_page=True)
    context.close()
    require(not page_errors, f"portrait page errors: {page_errors}")
    require(not console_errors, f"portrait console errors: {console_errors}")
    return {
        "rotate_display": rotate_display,
        "page_errors": page_errors,
        "console_errors": console_errors,
    }


def check_pwa_files(base_url: str) -> dict[str, Any]:
    with urlopen(f"{base_url}/index.manifest.json", timeout=10) as response:
        manifest = json.loads(response.read().decode("utf-8"))
    require(manifest.get("orientation") == "landscape", "PWA orientation was not landscape")
    require(manifest.get("display") == "standalone", "PWA display was not standalone")
    icon_sizes = {icon.get("sizes") for icon in manifest.get("icons", [])}
    require(
        {"144x144", "180x180", "512x512"}.issubset(icon_sizes),
        "PWA icon set was incomplete",
    )
    for path in ("index.service.worker.js", "index.offline.html"):
        with urlopen(f"{base_url}/{path}", timeout=10) as response:
            require(response.status == 200, f"{path} was not served")
    return {
        "orientation": manifest.get("orientation"),
        "display": manifest.get("display"),
        "icon_sizes": sorted(icon_sizes),
    }


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Validate the Lantern Line touch Web shell and PWA."
    )
    parser.add_argument("--browser", type=Path, required=True)
    parser.add_argument(
        "--web-root",
        type=Path,
        default=REPO_ROOT / "build" / "web",
    )
    parser.add_argument(
        "--output",
        type=Path,
        default=REPO_ROOT / "design" / "audits" / "v0.8-m1-web-mobile.json",
    )
    parser.add_argument(
        "--receipt-dir",
        type=Path,
        default=REPO_ROOT / "design" / "receipts" / "v0.8-m1",
    )
    args = parser.parse_args()
    require(args.browser.exists(), f"browser not found: {args.browser}")
    require((args.web_root / "index.html").exists(), "production Web export missing")
    with serve(args.web_root) as base_url:
        with sync_playwright() as playwright:
            browser = playwright.chromium.launch(
                executable_path=str(args.browser),
                headless=True,
            )
            try:
                record = {
                    "landscape": check_landscape_launch(
                        browser,
                        base_url,
                        args.receipt_dir,
                    ),
                    "portrait": check_portrait_overlay(
                        browser,
                        base_url,
                        args.receipt_dir,
                    ),
                    "pwa": check_pwa_files(base_url),
                }
            finally:
                browser.close()
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(record, indent=2) + "\n", encoding="utf-8")
    print(f"[mobile-web] wrote {args.output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
