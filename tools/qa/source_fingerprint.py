from __future__ import annotations

import argparse
import hashlib
import json
import subprocess
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]
EXCLUDED_PREFIXES = (
    "assets/generated/",
    "build/",
    "design/receipts/",
)
EXCLUDED_FILES = {
    "design/audits/v0.8-baseline.md",
    "design/audits/v0.8-m0-audit.md",
    "design/audits/v0.8-package-budget.md",
    "design/audits/v0.8-profile-matrix.json",
    "design/audits/v0.8-profile-matrix.md",
    "design/audits/v0.8-visual-benchmark.json",
    "design/audits/v0.8-visual-benchmark.md",
    "design/audits/v0.8-web-visual-benchmark.json",
    "design/audits/v0.8-web-visual-benchmark.md",
}


def run_text(command: list[str], repo_root: Path) -> str:
    result = subprocess.run(
        command,
        cwd=repo_root,
        check=True,
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
    )
    return result.stdout.strip()


def included(relative_path: str) -> bool:
    normalized = relative_path.replace("\\", "/")
    if normalized in EXCLUDED_FILES:
        return False
    return not normalized.startswith(EXCLUDED_PREFIXES)


def source_fingerprint(repo_root: Path = REPO_ROOT) -> tuple[str, str]:
    head = run_text(["git", "rev-parse", "HEAD"], repo_root)
    tracked_changes = run_text(
        [
            "git",
            "diff",
            "--name-only",
            "--no-ext-diff",
            "HEAD",
            "--",
        ],
        repo_root,
    ).splitlines()
    untracked_changes = run_text(
        ["git", "ls-files", "--others", "--exclude-standard"],
        repo_root,
    ).splitlines()
    changed_paths = tracked_changes + untracked_changes
    digest = hashlib.sha256()
    for relative_path in sorted(
        {path for path in changed_paths if path and included(path)}
    ):
        normalized = relative_path.replace("\\", "/")
        digest.update(normalized.encode("utf-8"))
        digest.update(b"\0")
        path = repo_root / relative_path
        if path.is_file():
            digest.update(path.read_bytes())
        else:
            digest.update(b"<deleted>")
        digest.update(b"\0")
    return head, digest.hexdigest()


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo", type=Path, default=REPO_ROOT)
    args = parser.parse_args()
    head, fingerprint = source_fingerprint(args.repo.resolve())
    print(
        json.dumps(
            {
                "git_head": head,
                "source_fingerprint": fingerprint,
            },
            sort_keys=True,
        )
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
