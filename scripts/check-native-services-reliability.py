#!/usr/bin/env python3
"""Phase 14 reliability tests for native Linux services, CLI helpers, and bridge error handling.

Uses temporary directories, synthetic /proc + /sys trees, and mocked command
stubs so host packages, disks, and system configuration are never modified.
"""

from __future__ import annotations

import importlib.util
import json
import os
from pathlib import Path
import shutil
import stat
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.request

REPO_ROOT = Path(__file__).resolve().parents[1]
BRIDGE_PATH = REPO_ROOT / "linux" / "mint" / "nexus-system-bridge.py"
STORE_CLI = REPO_ROOT / "linux" / "mint" / "nexus-store-cli.sh"
GAMING_CLI = REPO_ROOT / "linux" / "mint" / "nexus-gaming-cli.sh"
SECURITY_CLI = REPO_ROOT / "linux" / "mint" / "nexus-security-cli.sh"
AUDIT_CLI = REPO_ROOT / "linux" / "security" / "nexus-security-audit.sh"


def load_bridge_module():
    spec = importlib.util.spec_from_file_location("nexus_system_bridge", BRIDGE_PATH)
    assert spec and spec.loader
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def make_stub(bin_dir: Path, name: str, script_body: str) -> Path:
    target = bin_dir / name
    target.write_text("#!/usr/bin/env bash\nset -euo pipefail\n" + script_body + "\n", encoding="utf-8")
    target.chmod(0o755)
    return target


def test_telemetry_missing_and_restricted_permissions(bridge) -> None:
    with tempfile.TemporaryDirectory() as td:
        tmp = Path(td)
        proc_dir = tmp / "proc"
        sys_dir = tmp / "sys"
        proc_dir.mkdir()
        sys_dir.mkdir()

        # 1. Completely missing /proc files & /sys thermal/battery sensors
        snap = bridge.collect_telemetry_snapshot(proc_root=proc_dir, sys_root=sys_dir, sample_seconds=0.0)
        assert snap["processor"]["summary"] == "Unavailable"
        assert snap["memory"]["summary"] == "Unavailable"
        assert snap["network"]["summary"] == "Unavailable"
        assert snap["battery"]["summary"] == "Unavailable"
        assert snap["temperature"]["summary"] == "Unavailable"
        assert snap["processes"]["summary"] == "Unavailable"

        # 2. Malformed /proc/stat & /proc/meminfo & unreadable thermal sensor
        (proc_dir / "stat").write_text("cpu bad data\n", encoding="utf-8")
        (proc_dir / "meminfo").write_text("MemTotal: invalid kB\n", encoding="utf-8")
        thermal = sys_dir / "class" / "thermal" / "thermal_zone0"
        thermal.mkdir(parents=True)
        temp_file = thermal / "temp"
        temp_file.write_text("45000\n", encoding="utf-8")
        temp_file.chmod(0o000)
        try:
            snap2 = bridge.collect_telemetry_snapshot(proc_root=proc_dir, sys_root=sys_dir, sample_seconds=0.0)
            assert snap2["processor"]["summary"] == "Unavailable"
            assert snap2["memory"]["summary"] == "Unavailable"
            if os.geteuid() != 0:
                assert snap2["temperature"]["summary"] == "Unavailable"
        finally:
            temp_file.chmod(0o644)

        # 3. Valid synthetic sensor & memory files
        (proc_dir / "meminfo").write_text("MemTotal: 4096000 kB\nMemAvailable: 2048000 kB\n", encoding="utf-8")
        (thermal / "temp").write_text("48500\n", encoding="utf-8")
        (thermal / "type").write_text("x86_pkg_temp\n", encoding="utf-8")
        snap3 = bridge.collect_telemetry_snapshot(proc_root=proc_dir, sys_root=sys_dir, sample_seconds=0.0)
        assert "4000 MiB" in snap3["memory"]["summary"]
        assert snap3["temperature"]["summary"] == "48.5 °C"
        assert snap3["temperature"]["detail"] == "x86_pkg_temp"
    print("PASS telemetry handles missing /proc, /sys sensors, malformed data, and permission restrictions")


def test_tool_launching_boundaries(bridge) -> None:
    # Unknown category must fail cleanly
    res_unknown = bridge.launch_allowlisted_tool("does-not-exist")
    assert res_unknown["ok"] is False

    # Headless (no DISPLAY/WAYLAND_DISPLAY) must refuse GUI launch rather than claiming success
    orig_display = os.environ.pop("DISPLAY", None)
    orig_wayland = os.environ.pop("WAYLAND_DISPLAY", None)
    try:
        with tempfile.TemporaryDirectory() as td:
            bin_dir = Path(td)
            make_stub(bin_dir, "nemo", "exit 0")
            orig_path = os.environ.get("PATH", "")
            os.environ["PATH"] = f"{bin_dir}:{orig_path}"
            try:
                res_headless = bridge.launch_allowlisted_tool("files")
                assert res_headless["ok"] is False
                assert "display session" in res_headless["message"].lower()
            finally:
                os.environ["PATH"] = orig_path
    finally:
        if orig_display is not None:
            os.environ["DISPLAY"] = orig_display
        if orig_wayland is not None:
            os.environ["WAYLAND_DISPLAY"] = orig_wayland
    print("PASS tool launcher refuses unknown categories and headless GUI claims")


def test_pty_disconnect_exit_and_http_error_handling(bridge) -> None:
    # 1. Manager unit tests: exited session reap + errors on closed session
    mgr = bridge.TerminalSessionManager(max_sessions=2)
    sid = mgr.open_session()
    mgr.write(sid, "exit 0\n")
    deadline = time.monotonic() + 3.0
    exited = False
    while time.monotonic() < deadline:
        _, code = mgr.read(sid, timeout=0.05)
        if code is not None:
            exited = True
            break
    assert exited, "Expected bash PTY session to exit"
    # Second read drains and reaps session from active map
    try:
        mgr.read(sid, timeout=0.01)
    except KeyError:
        pass
    assert sid not in mgr.active_session_ids()
    mgr.close_all()

    # 2. Live loopback HTTP API tests for malformed JSON, disconnected PTY, and helper timeout
    with tempfile.TemporaryDirectory() as td:
        fake_repo = Path(td)
        (fake_repo / "linux" / "mint").mkdir(parents=True)
        (fake_repo / "linux" / "installer").mkdir(parents=True)
        # Copy real bridge script into fake repo structure to test helper error/timeout cleanly
        shutil.copy2(BRIDGE_PATH, fake_repo / "linux" / "mint" / "nexus-system-bridge.py")
        # Slow security CLI (triggers timeout) & malformed gaming CLI (triggers 502)
        make_stub(fake_repo / "linux" / "mint", "nexus-security-cli.sh", "sleep 2")
        make_stub(fake_repo / "linux" / "mint", "nexus-gaming-cli.sh", "printf 'not-json'")
        make_stub(fake_repo / "linux" / "installer", "nexus-install-preflight.sh", "exit 1")

        # Run bridge subprocess with shortened timeout by invoking helper directly via python -c
        code = """
import sys
sys.path.insert(0, %r)
import importlib.util
spec = importlib.util.spec_from_file_location("b", %r)
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)
# Patch subprocess timeout via wrapper for fast test
orig_run = mod.subprocess.run
def fast_run(cmd, **kw):
    if "timeout" in kw and kw["timeout"] >= 5.0:
        kw["timeout"] = 0.25
    return orig_run(cmd, **kw)
mod.subprocess.run = fast_run
mod.serve_loopback(0)
""" % (str(fake_repo / "linux" / "mint"), str(fake_repo / "linux" / "mint" / "nexus-system-bridge.py"))

        proc = subprocess.Popen(
            [sys.executable, "-c", code],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        try:
            ready = json.loads(proc.stdout.readline())
            base_url = ready["url"]
            token = ready["token"]

            def raw_req(path: str, data: bytes | None = None, method: str = "GET") -> tuple[int, dict]:
                req = urllib.request.Request(
                    f"{base_url}{path}",
                    data=data,
                    headers={"X-Nexus-Token": token, "Content-Type": "application/json"},
                    method=method,
                )
                try:
                    with urllib.request.urlopen(req, timeout=4) as resp:
                        return resp.status, json.loads(resp.read().decode("utf-8"))
                except urllib.error.HTTPError as err:
                    return err.code, json.loads(err.read().decode("utf-8"))

            # Malformed JSON -> 400
            st, body = raw_req("/api/terminal/open", b"{bad-json", "POST")
            assert st == 400 and "error" in body

            # Invalid write on unknown session -> 404
            st, body = raw_req("/api/terminal/write", json.dumps({"sessionId": "missing", "data": "x\n"}).encode(), "POST")
            assert st == 404

            # Open + close -> write/resize/interrupt return 404 cleanly
            st, opened = raw_req("/api/terminal/open", b"{}", "POST")
            assert st == 200
            sid2 = opened["sessionId"]
            st, _ = raw_req("/api/terminal/close", json.dumps({"sessionId": sid2}).encode(), "POST")
            assert st == 200
            for ep, payload in (
                ("/api/terminal/write", {"sessionId": sid2, "data": "ls\n"}),
                ("/api/terminal/resize", {"sessionId": sid2, "cols": 80, "rows": 24}),
                ("/api/terminal/interrupt", {"sessionId": sid2}),
            ):
                st, _ = raw_req(ep, json.dumps(payload).encode(), "POST")
                assert st == 404, f"Expected 404 on closed session {ep}, got {st}"

            # Helper timeout -> 504
            st, body = raw_req("/api/security/status")
            assert st == 504, f"Expected 504 on timeout, got {st}: {body}"

            # Helper malformed JSON -> 502
            st, body = raw_req("/api/gaming/status")
            assert st == 502, f"Expected 502 on malformed JSON, got {st}: {body}"

            # Helper non-zero exit -> 502
            st, body = raw_req("/api/installer/preflight")
            assert st == 502, f"Expected 502 on helper failure, got {st}: {body}"
        finally:
            proc.terminate()
            proc.wait(timeout=5)
    print("PASS PTY disconnect/reap, malformed JSON, and helper timeout/error HTTP handling")


def test_store_cli_boundaries() -> None:
    with tempfile.TemporaryDirectory() as td:
        bin_dir = Path(td)
        # Stub minimal bash/core tools + apt-get WITHOUT pkexec
        for tool in ("bash", "cat", "grep", "head", "printf", "rm", "env"):
            found = shutil.which(tool)
            if found:
                os.symlink(found, bin_dir / tool)
        make_stub(bin_dir, "apt-get", "exit 0")
        make_stub(bin_dir, "apt-cache", "exit 0")

        env = {"PATH": str(bin_dir), "HOME": td}
        # sources must report pkexec=false when pkexec is absent
        res = subprocess.run(["bash", str(STORE_CLI), "sources"], env=env, capture_output=True, text=True, check=True)
        src = json.loads(res.stdout)
        assert src["apt"] is True and src["pkexec"] is False and src["flatpak"] is False

        # install without pkexec must refuse cleanly
        fail_install = subprocess.run(["bash", str(STORE_CLI), "install", "apt", "gimp"], env=env, capture_output=True, text=True)
        assert fail_install.returncode != 0 and "pkexec" in fail_install.stderr

        # Protected Lite / LXQt packages must be refused even with --dry-run
        for pkg in ("openbox", "lxqt-session", "network-manager", "lightdm", "pcmanfm-qt", "systemd", "ufw"):
            prot = subprocess.run(["bash", str(STORE_CLI), "--dry-run", "remove", "apt", pkg], capture_output=True, text=True)
            assert prot.returncode != 0 and "Refusing to remove protected" in prot.stderr, f"Expected protection for {pkg}"

        # Invalid package IDs & blank search must be rejected
        for bad_args in (
            ["--dry-run", "install", "apt", "-rf"],
            ["--dry-run", "install", "flatpak", "nodot"],
            ["search", "   "],
        ):
            bad = subprocess.run(["bash", str(STORE_CLI), *bad_args], capture_output=True, text=True)
            assert bad.returncode == 2, f"Expected exit 2 for {bad_args}, got {bad.returncode}"

        # Failed pkexec / apt-get operation surfaces failure
        make_stub(bin_dir, "pkexec", "echo 'Authorization failed' >&2; exit 126")
        fail_pk = subprocess.run(["bash", str(STORE_CLI), "install", "apt", "gimp"], env=env, capture_output=True, text=True)
        assert fail_pk.returncode == 126 and "Authorization failed" in fail_pk.stderr
    print("PASS NEXUS Store CLI authorization, protected packages, invalid IDs, and failed-op tests")


def test_gaming_and_security_cli_boundaries() -> None:
    with tempfile.TemporaryDirectory() as td:
        tmp = Path(td)
        bin_dir = tmp / "bin"
        bin_dir.mkdir()
        home_dir = tmp / "home"
        steamapps = home_dir / ".local" / "share" / "Steam" / "steamapps"
        steamapps.mkdir(parents=True)
        (steamapps / "appmanifest_620.acf").write_text('"appid" "620"\n"name" "Portal 2"\n', encoding="utf-8")
        (steamapps / "appmanifest_1493710.acf").write_text('"appid" "1493710"\n"name" "Proton Experimental"\n', encoding="utf-8")
        lutris_fp = home_dir / ".local" / "share" / "flatpak" / "app" / "net.lutris.Lutris"
        lutris_fp.mkdir(parents=True)

        env = dict(os.environ, HOME=str(home_dir), XDG_CONFIG_HOME=str(home_dir / ".config"))
        res = subprocess.run(["bash", str(GAMING_CLI), "status"], env=env, capture_output=True, text=True, check=True)
        st = json.loads(res.stdout)
        assert st["steam"]["installed"] is True
        assert any(g["appid"] == "620" and g["name"] == "Portal 2" for g in st["steam"]["installed_games"])
        assert "Proton Experimental" in st["steam"]["proton_versions"]
        assert st["launchers"]["lutris"]["installed"] is True
        assert st["launchers"]["heroic"]["installed"] is False

        # Gaming mode state persistence in isolated XDG_CONFIG_HOME
        subprocess.run(["bash", str(GAMING_CLI), "gaming-mode", "enable"], env=env, capture_output=True, text=True, check=True)
        gm = subprocess.run(["bash", str(GAMING_CLI), "gaming-mode", "status"], env=env, capture_output=True, text=True, check=True)
        assert "gaming_mode=enabled" in gm.stdout
        subprocess.run(["bash", str(GAMING_CLI), "gaming-mode", "disable"], env=env, capture_output=True, text=True, check=True)
        gm2 = subprocess.run(["bash", str(GAMING_CLI), "gaming-mode", "status"], env=env, capture_output=True, text=True, check=True)
        assert "gaming_mode=disabled" in gm2.stdout

        # Missing steam binary refuses launch clearly
        minimal_env = {"PATH": f"{bin_dir}:/usr/bin:/bin", "HOME": str(home_dir)}
        # Use restricted PATH without steam
        if not shutil.which("steam"):
            launch_fail = subprocess.run(["bash", str(GAMING_CLI), "steam", "launch"], env=env, capture_output=True, text=True)
            assert launch_fail.returncode != 0 and "Steam is not installed" in launch_fail.stderr

        # Security CLI refuses firewall enable cleanly when ufw/pkexec are absent
        for tool in ("bash", "python3", "grep", "id"):
            found = shutil.which(tool)
            if found:
                os.symlink(found, bin_dir / tool)
        sec_env = {"PATH": str(bin_dir), "HOME": str(home_dir)}
        sec_fail = subprocess.run(["bash", str(SECURITY_CLI), "firewall", "enable"], env=sec_env, capture_output=True, text=True)
        assert sec_fail.returncode != 0 and "ufw" in sec_fail.stderr.lower()

        # Security Audit flags test-agent contamination when present in a non-root dir
        bad_root = tmp / "contaminated-root"
        (bad_root / "etc" / "systemd" / "system").mkdir(parents=True)
        (bad_root / "etc" / "systemd" / "system" / "nexus-test-agent.service").write_text("[Unit]\n", encoding="utf-8")
        audit_fail = subprocess.run(["bash", str(AUDIT_CLI), "--root", str(bad_root), "--strict"], capture_output=True, text=True)
        assert audit_fail.returncode != 0
    print("PASS Gaming Hub (Steam/Proton/Lutris/Heroic) & Security CLI boundary tests")


def main() -> None:
    bridge = load_bridge_module()
    test_telemetry_missing_and_restricted_permissions(bridge)
    test_tool_launching_boundaries(bridge)
    test_pty_disconnect_exit_and_http_error_handling(bridge)
    test_store_cli_boundaries()
    test_gaming_and_security_cli_boundaries()


if __name__ == "__main__":
    main()
