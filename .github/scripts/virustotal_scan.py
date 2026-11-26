#!/usr/bin/env python3
"""Submit release binaries to VirusTotal (Public API v3) and summarize reports.

Reads VIRUSTOTAL_API_KEY from environment without exposing it in command lines
or logs. Files already indexed in VirusTotal are fetched by SHA-256 without
re-uploading; new files up to 650 MiB use the official /files/upload_url flow
and respect the free Public API limit (4 requests/minute).
"""

from __future__ import annotations

import hashlib
import json
import os
import shutil
import subprocess
import sys
import time
from pathlib import Path
from typing import Any

VT_BASE = "https://www.virustotal.com/api/v3"
DIRECT_UPLOAD_LIMIT = 32 * 1024 * 1024
MAX_FILE_SIZE = 650 * 1024 * 1024
RATE_INTERVAL_SECONDS = 16.0  # stays strictly under 4 requests/minute

_last_request_at = 0.0
_CURL_BIN = shutil.which("curl.exe") or shutil.which("curl") or "curl"


def _throttle() -> None:
    global _last_request_at
    now = time.monotonic()
    wait = RATE_INTERVAL_SECONDS - (now - _last_request_at)
    if _last_request_at > 0.0 and wait > 0.0:
        time.sleep(wait)
    _last_request_at = time.monotonic()


def _curl_json(
    method: str,
    url: str,
    api_key: str,
    form_file: Path | None = None,
    count_rate: bool = True,
) -> tuple[int, dict[str, Any]]:
    for attempt in range(2):
        if count_rate:
            _throttle()

        config_lines = [
            f'header = "x-apikey: {api_key}"',
            'header = "Accept: application/json"',
        ]
        cmd = [
            _CURL_BIN,
            "-sS",
            "--connect-timeout",
            "20",
            "--max-time",
            "600",
            "-K",
            "-",
            "-X",
            method,
            "-w",
            "\n%{http_code}",
        ]
        if form_file is not None:
            cmd.extend(["-F", f"file=@{form_file}"])
        cmd.append(url)

        proc = subprocess.run(
            cmd,
            input="\n".join(config_lines) + "\n",
            text=True,
            capture_output=True,
            check=False,
        )
        if proc.returncode != 0:
            if attempt == 0:
                time.sleep(10)
                continue
            return 0, {"error": {"message": proc.stderr.strip() or f"curl exit {proc.returncode}"}}

        raw = proc.stdout.rstrip("\n")
        if "\n" in raw:
            body_text, code_str = raw.rsplit("\n", 1)
        else:
            body_text, code_str = "", raw

        try:
            status = int(code_str.strip())
        except ValueError:
            status = 0

        try:
            payload = json.loads(body_text) if body_text.strip() else {}
        except json.JSONDecodeError:
            payload = {}

        if status == 429 and attempt == 0:
            time.sleep(65)
            continue

        return status, payload

    return 0, {}


def _sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as fh:
        while True:
            chunk = fh.read(1024 * 1024)
            if not chunk:
                break
            h.update(chunk)
    return h.hexdigest()


def _format_stats(payload: dict[str, Any]) -> str:
    attrs = (payload.get("data") or {}).get("attributes") or {}
    stats = attrs.get("last_analysis_stats") or {}
    if not isinstance(stats, dict) or not stats:
        return "Queued / Analyzing"
    malicious = int(stats.get("malicious", 0))
    suspicious = int(stats.get("suspicious", 0))
    undetected = int(stats.get("undetected", 0))
    harmless = int(stats.get("harmless", 0))
    total = malicious + suspicious + undetected + harmless
    flagged = malicious + suspicious
    if total <= 0:
        return "Queued / Analyzing"
    return f"{flagged} / {total}"


def _write_summary(markdown: str) -> None:
    print(markdown)
    summary_path = os.environ.get("GITHUB_STEP_SUMMARY", "").strip()
    if summary_path:
        with open(summary_path, "a", encoding="utf-8") as fh:
            fh.write(markdown + "\n")


def scan_file(path: Path, api_key: str) -> dict[str, str]:
    size = path.stat().st_size
    size_mb = f"{size / (1024 * 1024):.2f} MB"
    sha256 = _sha256_file(path)
    report_url = f"https://www.virustotal.com/gui/file/{sha256}"

    if size <= 0 or size > MAX_FILE_SIZE:
        return {
            "name": path.name,
            "size": size_mb,
            "sha256": sha256,
            "status": f"Skipped (size {size_mb} exceeds 650 MB limit)",
            "url": report_url,
        }

    code, data = _curl_json("GET", f"{VT_BASE}/files/{sha256}", api_key)
    if code == 200:
        return {
            "name": path.name,
            "size": size_mb,
            "sha256": sha256,
            "status": _format_stats(data),
            "url": report_url,
        }

    if code in (401, 403):
        return {
            "name": path.name,
            "size": size_mb,
            "sha256": sha256,
            "status": f"API error HTTP {code}",
            "url": report_url,
        }

    if code == 404:
        if size <= DIRECT_UPLOAD_LIMIT:
            up_code, up_data = _curl_json("POST", f"{VT_BASE}/files", api_key, form_file=path)
        else:
            url_code, url_data = _curl_json("GET", f"{VT_BASE}/files/upload_url", api_key)
            upload_url = str(url_data.get("data") or "").strip() if url_code == 200 else ""
            if not upload_url:
                return {
                    "name": path.name,
                    "size": size_mb,
                    "sha256": sha256,
                    "status": f"Upload URL error HTTP {url_code}",
                    "url": report_url,
                }
            up_code, up_data = _curl_json("POST", upload_url, api_key, form_file=path)

        if 200 <= up_code < 300:
            return {
                "name": path.name,
                "size": size_mb,
                "sha256": sha256,
                "status": "Submitted (scanning)",
                "url": report_url,
            }

        return {
            "name": path.name,
            "size": size_mb,
            "sha256": sha256,
            "status": f"Upload failed HTTP {up_code}",
            "url": report_url,
        }

    return {
        "name": path.name,
        "size": size_mb,
        "sha256": sha256,
        "status": f"Lookup HTTP {code}",
        "url": report_url,
    }


def main(argv: list[str]) -> int:
    api_key = os.environ.get("VIRUSTOTAL_API_KEY", "").strip()
    if not api_key:
        print("::notice::VIRUSTOTAL_API_KEY secret is not set; skipping VirusTotal upload.")
        _write_summary("## VirusTotal Scan\n\nSkipped because `VIRUSTOTAL_API_KEY` secret is not configured.")
        return 0

    files: list[Path] = []
    seen: set[Path] = set()
    for arg in argv:
        p = Path(arg)
        if p.is_file():
            resolved = p.resolve()
            if resolved not in seen:
                seen.add(resolved)
                files.append(p)

    if not files:
        print("::notice::No release files passed to virustotal_scan.py.")
        return 0

    rows: list[dict[str, str]] = []
    for path in files:
        rows.append(scan_file(path, api_key))

    # Give newly submitted files a moment, then refresh status once if needed.
    pending = [r for r in rows if r["status"] == "Submitted (scanning)"]
    if pending:
        time.sleep(20)
        for row in pending:
            code, data = _curl_json("GET", f"{VT_BASE}/files/{row['sha256']}", api_key)
            if code == 200:
                row["status"] = _format_stats(data)

    lines = [
        "## VirusTotal Release Scan",
        "",
        "| File | Size | SHA-256 | Detections | VirusTotal Report |",
        "| --- | --- | --- | --- | --- |",
    ]
    for row in rows:
        lines.append(
            f"| `{row['name']}` | {row['size']} | `{row['sha256']}` | **{row['status']}** | [View Report]({row['url']}) |"
        )
    _write_summary("\n".join(lines))
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
