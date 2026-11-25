#!/usr/bin/env python3
"""Host-side QEMU QMP + virtio-serial graphical desktop & telemetry orchestrator.
Captures synchronized PPM->PNG screenshots, injects safe QMP input events, and
records separated boot, login, graphical session, app, memory, ZRAM, and preflight results.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import socket
import struct
import subprocess
import sys
import time
import zlib


def ppm_to_png_and_stats(ppm_path: Path, png_path: Path):
    raw = ppm_path.read_bytes()
    pos = 0
    tokens = []
    while len(tokens) < 4 and pos < len(raw):
        while pos < len(raw) and raw[pos] in b" \t\r\n":
            pos += 1
        if pos < len(raw) and raw[pos:pos + 1] == b"#":
            nl = raw.find(b"\n", pos)
            pos = len(raw) if nl == -1 else nl + 1
            continue
        end = pos
        while end < len(raw) and raw[end] not in b" \t\r\n":
            end += 1
        tokens.append(raw[pos:end].decode("ascii", "replace"))
        pos = end + 1
    if len(tokens) < 4 or tokens[0] != "P6":
        return {"width": 0, "height": 0, "non_black_pct": 0.0, "png": None}
    w, h, _maxv = int(tokens[1]), int(tokens[2]), int(tokens[3])
    rgb = raw[pos:pos + w * h * 3]
    stride = w * 3
    if len(rgb) < h * stride:
        return {"width": w, "height": h, "non_black_pct": 0.0, "png": None}

    sample = rgb[::30]
    non_black = sum(1 for b in sample if b > 8)
    non_black_pct = round((non_black / max(1, len(sample))) * 100.0, 2)

    scanlines = bytearray()
    for y in range(h):
        scanlines.append(0)
        scanlines.extend(rgb[y * stride:(y + 1) * stride])

    def chunk(tag, data):
        return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)

    png_bytes = (
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0))
        + chunk(b"IDAT", zlib.compress(bytes(scanlines), 6))
        + chunk(b"IEND", b"")
    )
    png_path.write_bytes(png_bytes)
    ppm_path.unlink(missing_ok=True)
    return {
        "width": w,
        "height": h,
        "non_black_pct": non_black_pct,
        "png": str(png_path),
        "png_sha256": hashlib.sha256(png_bytes).hexdigest()[:16],
    }


class QmpClient:
    def __init__(self, sock_path: Path):
        self.sock_path = sock_path
        self.sock = None

    def connect(self, timeout=20):
        deadline = time.time() + timeout
        while time.time() < deadline:
            if self.sock_path.exists():
                try:
                    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
                    s.settimeout(5)
                    s.connect(str(self.sock_path))
                    s.recv(4096)
                    s.sendall(b'{"execute":"qmp_capabilities"}\n')
                    s.recv(4096)
                    self.sock = s
                    return True
                except OSError:
                    time.sleep(0.3)
            else:
                time.sleep(0.3)
        return False

    def cmd(self, payload):
        if not self.sock:
            return {}
        try:
            self.sock.sendall((json.dumps(payload) + "\n").encode("utf-8"))
            data = self.sock.recv(8192)
            for line in data.decode("utf-8", "replace").splitlines():
                if line.strip().startswith("{"):
                    obj = json.loads(line)
                    if "return" in obj or "error" in obj:
                        return obj
        except Exception:
            pass
        return {}

    def screendump(self, out_dir: Path, name: str):
        ppm = out_dir / f"{name}.ppm"
        png = out_dir / f"{name}.png"
        self.cmd({"execute": "screendump", "arguments": {"filename": str(ppm)}})
        time.sleep(0.4)
        if ppm.is_file():
            stats = ppm_to_png_and_stats(ppm, png)
            stats["name"] = name
            return stats
        return {"name": name, "png": None, "non_black_pct": 0.0}

    def send_alt_f4(self):
        return self.cmd({
            "execute": "send-key",
            "arguments": {"keys": [{"type": "qcode", "data": "alt"}, {"type": "qcode", "data": "f4"}]},
        })

    def nudge_mouse(self):
        return self.cmd({
            "execute": "input-send-event",
            "arguments": {"events": [
                {"type": "rel", "data": {"axis": "x", "value": 24}},
                {"type": "rel", "data": {"axis": "y", "value": 16}},
            ]},
        })

    def quit(self):
        self.cmd({"execute": "quit"})
        if self.sock:
            try:
                self.sock.close()
            except Exception:
                pass


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--qemu-cmd-json", required=True)
    ap.add_argument("--qmp-sock", required=True)
    ap.add_argument("--vserial-sock", required=True)
    ap.add_argument("--out-dir", required=True)
    ap.add_argument("--idle-seconds", type=int, default=30)
    ap.add_argument("--timeout-seconds", type=int, default=600)
    args = ap.parse_args()

    out_dir = Path(args.out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    qemu_cmd = json.loads(args.qemu_cmd_json)
    proc = subprocess.Popen(qemu_cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

    qmp = QmpClient(Path(args.qmp_sock))
    qmp_ok = qmp.connect(timeout=25)

    vserial_path = Path(args.vserial_sock)
    vs = None
    deadline = time.time() + args.timeout_seconds
    while time.time() < deadline and not vserial_path.exists():
        time.sleep(0.3)
    if vserial_path.exists():
        for _ in range(30):
            try:
                vs = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
                vs.settimeout(2)
                vs.connect(str(vserial_path))
                break
            except OSError:
                time.sleep(0.3)

    screenshots = []
    events = []
    complete_data = None
    failure_data = None
    boot_shot_taken = False
    start_t = time.time()
    buf = ""

    try:
        while time.time() < deadline:
            if proc.poll() is not None:
                break
            if qmp_ok and not boot_shot_taken and (time.time() - start_t) >= 30:
                screenshots.append(qmp.screendump(out_dir, "00_boot_progress"))
                boot_shot_taken = True

            if vs:
                try:
                    chunk = vs.recv(65536)
                    if chunk:
                        buf += chunk.decode("utf-8", "replace")
                        while "\n" in buf:
                            line, buf = buf.split("\n", 1)
                            line = line.strip()
                            if not line:
                                continue
                            try:
                                ev = json.loads(line)
                            except json.JSONDecodeError:
                                continue
                            events.append(ev)
                            et = ev.get("event")
                            if et == "agent_started":
                                vs.sendall((json.dumps({"cmd": "run_suite", "idle_seconds": args.idle_seconds}) + "\n").encode("utf-8"))
                            elif et == "desktop_ready":
                                if qmp_ok:
                                    qmp.nudge_mouse()
                                    screenshots.append(qmp.screendump(out_dir, "01_desktop_initial"))
                                vs.sendall(b'{"cmd":"ack"}\n')
                            elif et in ("app_file_manager", "app_terminal", "app_settings", "app_multi_apps"):
                                if qmp_ok:
                                    screenshots.append(qmp.screendump(out_dir, f"02_{et}"))
                                vs.sendall(b'{"cmd":"ack"}\n')
                            elif et == "test_alt_f4":
                                if qmp_ok:
                                    qmp.send_alt_f4()
                                vs.sendall(b'{"cmd":"ack"}\n')
                            elif et == "desktop_failed":
                                failure_data = ev.get("data")
                                if qmp_ok:
                                    screenshots.append(qmp.screendump(out_dir, "99_desktop_failed"))
                                break
                            elif et == "complete":
                                complete_data = ev.get("data")
                                if qmp_ok:
                                    screenshots.append(qmp.screendump(out_dir, "06_post_close"))
                                break
                except socket.timeout:
                    pass
                if complete_data or failure_data:
                    break
            else:
                time.sleep(0.5)
    finally:
        if qmp_ok:
            if not screenshots:
                screenshots.append(qmp.screendump(out_dir, "98_timeout_screen"))
            qmp.quit()
        if vs:
            try:
                vs.close()
            except Exception:
                pass
        try:
            proc.wait(timeout=8)
        except subprocess.TimeoutExpired:
            proc.kill()
            proc.wait(timeout=5)

    result = {
        "vm_exited_cleanly": proc.returncode == 0,
        "qmp_connected": qmp_ok,
        "screenshots": screenshots,
        "desktop_failed": failure_data,
        "guest_report": complete_data,
        "events_count": len(events),
    }
    print(json.dumps(result, indent=2))
    return 0 if complete_data else 1


if __name__ == "__main__":
    sys.exit(main())
