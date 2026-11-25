#!/usr/bin/env python3
"""Integration tests for linux/mint/nexus-system-bridge.py.

Verifies real /proc + statvfs telemetry, allowlisted tool detection, real GNU
Bash PTY session lifecycle, and loopback-only token-authenticated HTTP API.
"""

from __future__ import annotations

import json
from pathlib import Path
import subprocess
import sys
import time
import urllib.error
import urllib.request

REPO_ROOT = Path(__file__).resolve().parents[1]
BRIDGE = REPO_ROOT / "linux" / "mint" / "nexus-system-bridge.py"


def run_cli(*args: str) -> dict:
    proc = subprocess.run(
        [sys.executable, str(BRIDGE), *args],
        cwd=REPO_ROOT,
        capture_output=True,
        text=True,
        check=True,
    )
    return json.loads(proc.stdout)


def main() -> None:
    telemetry = run_cli("--telemetry")
    for key in ("processor", "memory", "storage", "processes", "network", "battery", "temperature"):
        assert key in telemetry, f"Missing telemetry section: {key}"
    assert telemetry["memory"]["summary"] != "Unavailable", "Expected real /proc/meminfo on Linux"
    assert telemetry["storage"]["summary"] != "Unavailable", "Expected real statvfs on /"
    assert len(telemetry["processes"]["items"]) >= 1, "Expected real running processes from /proc"

    tools = run_cli("--tools")
    for key in ("files", "browser", "terminal", "monitor", "display", "sound", "network", "bluetooth", "power", "accounts", "privacy-security", "packages"):
        assert key in tools and "available" in tools[key]

    bash_probe = run_cli("--bash-check")
    assert bash_probe["ok"] is True
    assert "BASH_OK:" in bash_probe["bash_output_sample"]

    proc = subprocess.Popen(
        [sys.executable, str(BRIDGE), "--serve", "--port", "0"],
        cwd=REPO_ROOT,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    try:
        assert proc.stdout is not None
        ready = json.loads(proc.stdout.readline())
        base_url = ready["url"]
        token = ready["token"]

        # Unauthorized request must be rejected with 401
        try:
            urllib.request.urlopen(f"{base_url}/api/telemetry", timeout=3)
            raise AssertionError("Expected 401 for unauthenticated request")
        except urllib.error.HTTPError as err:
            assert err.code == 401

        def api(path: str, payload: dict | None = None) -> dict:
            data = json.dumps(payload).encode("utf-8") if payload is not None else None
            req = urllib.request.Request(
                f"{base_url}{path}",
                data=data,
                headers={"X-Nexus-Token": token, "Content-Type": "application/json"},
                method="POST" if data is not None else "GET",
            )
            with urllib.request.urlopen(req, timeout=5) as resp:
                return json.loads(resp.read().decode("utf-8"))

        opened = api("/api/terminal/open", {"cols": 90, "rows": 25})
        sid = opened["sessionId"]
        api("/api/terminal/write", {"sessionId": sid, "data": "printf 'HTTP_PTY_PASS\\n'\n"})

        output = ""
        deadline = time.monotonic() + 3.0
        while time.monotonic() < deadline:
            res = api(f"/api/terminal/read?sessionId={sid}")
            output += res["output"]
            if any(line.strip() == "HTTP_PTY_PASS" for line in output.splitlines()):
                break
            time.sleep(0.05)
        assert any(line.strip() == "HTTP_PTY_PASS" for line in output.splitlines()), (
            f"Expected Bash PTY HTTP output, got: {output!r}"
        )
        api("/api/terminal/close", {"sessionId": sid})

        sec_status = api("/api/security/status")
        for key in ("firewall", "secure_boot", "disk_encryption", "security_updates", "account", "startup_apps"):
            assert key in sec_status, f"Missing security status key: {key}"

        gaming_status = api("/api/gaming/status")
        for key in ("steam", "graphics", "hardware", "controllers", "performance"):
            assert key in gaming_status, f"Missing gaming status key: {key}"
    finally:
        proc.terminate()
        proc.wait(timeout=5)

    print("PASS Linux Mint system bridge telemetry, real GNU Bash PTY, and authenticated HTTP API tests")


if __name__ == "__main__":
    main()
