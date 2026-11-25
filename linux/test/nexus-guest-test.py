#!/usr/bin/env python3
"""Ephemeral in-guest graphical, memory, ZRAM, network, and preflight validator.
Runs ONLY inside test VMs when QEMU attaches /dev/virtio-ports/org.nexus.test.0.
"""
import json
import os
from pathlib import Path
import pwd
import shutil
import signal
import subprocess
import sys
import time

VSERIAL_PATH = "/dev/virtio-ports/org.nexus.test.0"
PROBE_SH = "/usr/local/libexec/nexus-test/guest-mem-probe.sh"
ZRAM_SH = "/usr/local/libexec/nexus-test/test-zram-pressure.sh"


def send_event(port, event_type, payload=None):
    msg = {"event": event_type, "ts_utc": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())}
    if payload is not None:
        msg["data"] = payload
    line = (json.dumps(msg, separators=(",", ":")) + "\n").encode("utf-8")
    os.write(port, line)


def wait_for_cmd(port_file, expected_cmd, timeout=30):
    deadline = time.time() + timeout
    while time.time() < deadline:
        line = port_file.readline()
        if line:
            try:
                obj = json.loads(line.strip())
                if not expected_cmd or obj.get("cmd") == expected_cmd:
                    return obj
            except json.JSONDecodeError:
                pass
        else:
            time.sleep(0.2)
    return {}


def detect_edition():
    rel = Path("/etc/nexus-os-release")
    if rel.is_file():
        txt = rel.read_text(encoding="utf-8", errors="replace")
        if 'NEXUS_EDITION="lite"' in txt or "openbox" in txt.lower():
            return "lite"
        if "cinnamon" in txt.lower():
            return "cinnamon"
    if shutil.which("cinnamon-session"):
        return "cinnamon"
    if shutil.which("openbox") and not shutil.which("xfce4-session"):
        return "lite"
    return "xfce"


def find_session_proc(targets):
    for proc_dir in Path("/proc").iterdir():
        if not proc_dir.name.isdigit():
            continue
        try:
            comm = (proc_dir / "comm").read_text(encoding="utf-8", errors="replace").strip()
            if comm not in targets:
                continue
            status = (proc_dir / "status").read_text(encoding="utf-8", errors="replace")
            uid = None
            for line in status.splitlines():
                if line.startswith("Uid:"):
                    uid = int(line.split()[1])
                    break
            env_raw = (proc_dir / "environ").read_bytes().split(b"\x00")
            env = {}
            for item in env_raw:
                if b"=" in item:
                    k, v = item.split(b"=", 1)
                    env[k.decode("utf-8", "replace")] = v.decode("utf-8", "replace")
            if uid is not None and uid >= 1000 and env.get("DISPLAY"):
                return {
                    "pid": int(proc_dir.name),
                    "comm": comm,
                    "uid": uid,
                    "user": pwd.getpwuid(uid).pw_name,
                    "display": env["DISPLAY"],
                    "xauthority": env.get("XAUTHORITY", f"/home/{pwd.getpwuid(uid).pw_name}/.Xauthority"),
                    "dbus": env.get("DBUS_SESSION_BUS_ADDRESS", ""),
                }
        except Exception:
            continue
    return None


def x_env(sess):
    env = dict(os.environ)
    env["DISPLAY"] = sess["display"]
    env["XAUTHORITY"] = sess["xauthority"]
    if sess.get("dbus"):
        env["DBUS_SESSION_BUS_ADDRESS"] = sess["dbus"]
    return env


def run_as_user(sess, cmd_list):
    def preexec():
        pw = pwd.getpwuid(sess["uid"])
        os.setgid(pw.pw_gid)
        os.setuid(pw.pw_uid)

    return subprocess.Popen(
        cmd_list,
        env=x_env(sess),
        preexec_fn=preexec,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
    )


def x11_windows(sess):
    if not shutil.which("xwininfo"):
        return []
    res = subprocess.run(
        ["xwininfo", "-root", "-tree"],
        env=x_env(sess),
        capture_output=True,
        text=True,
        timeout=10,
    )
    wins = []
    for line in res.stdout.splitlines():
        s = line.strip()
        if s.startswith("0x") and '"' in s:
            wins.append(s)
    return wins


def x11_resolution(sess):
    if not shutil.which("xdpyinfo"):
        return None
    res = subprocess.run(["xdpyinfo"], env=x_env(sess), capture_output=True, text=True, timeout=10)
    for line in res.stdout.splitlines():
        if "dimensions:" in line:
            return line.strip()
    return None


def run_probe(stage):
    res = subprocess.run(["bash", PROBE_SH, "--stage", stage], capture_output=True, text=True, timeout=30)
    if res.returncode == 0 and res.stdout.strip():
        return json.loads(res.stdout)
    return {"stage": stage, "error": res.stderr.strip()}


def read_proc_names():
    res = subprocess.run(["ps", "-eo", "comm"], capture_output=True, text=True)
    return set(res.stdout.splitlines())


def main():
    if not Path(VSERIAL_PATH).exists():
        print("Virtio-serial test port not present; exiting cleanly.", file=sys.stderr)
        return 0

    port_fd = os.open(VSERIAL_PATH, os.O_RDWR)
    port_file = os.fdopen(os.dup(port_fd), "r", encoding="utf-8", errors="replace", buffering=1)

    edition = detect_edition()
    send_event(port_fd, "agent_started", {"edition": edition})
    cfg = wait_for_cmd(port_file, "run_suite", timeout=30)
    idle_seconds = int(cfg.get("idle_seconds", 30))

    wm_targets = {
        "lite": {"openbox"},
        "cinnamon": {"cinnamon", "cinnamon-sessio", "cinnamon-session"},
        "xfce": {"xfwm4", "xfce4-session"},
    }.get(edition, {"openbox", "cinnamon", "xfwm4"})

    sess = None
    for _ in range(90):
        sess = find_session_proc(wm_targets)
        if sess:
            break
        time.sleep(2)

    procs = read_proc_names()
    lightdm_active = "lightdm" in procs
    if not sess:
        send_event(port_fd, "desktop_failed", {
            "edition": edition,
            "lightdm_active": lightdm_active,
            "mem": run_probe("desktop_timeout"),
            "procs_sample": sorted(procs)[:40],
        })
        return 1

    # Give panel/background 6 seconds to finish mapping after WM starts
    time.sleep(6)
    procs = read_proc_names()
    panel_expected = {"lite": "tint2", "cinnamon": "cinnamon", "xfce": "xfce4-panel"}.get(edition)
    desktop_info = {
        "edition": edition,
        "user": sess["user"],
        "wm": sess["comm"],
        "lightdm_active": lightdm_active,
        "panel_running": panel_expected in procs,
        "panel_name": panel_expected,
        "resolution": x11_resolution(sess),
        "initial_windows": len(x11_windows(sess)),
    }
    send_event(port_fd, "desktop_ready", desktop_info)
    wait_for_cmd(port_file, "ack", timeout=15)

    stages = {}
    stages["1_post_login"] = run_probe("post_login")
    send_event(port_fd, "stage_mem", stages["1_post_login"])

    time.sleep(max(1, idle_seconds))
    stages["2_idle"] = run_probe(f"idle_{idle_seconds}s")
    send_event(port_fd, "stage_mem", stages["2_idle"])

    app_map = {
        "lite": {
            "file_manager": (["pcmanfm"], ("pcmanfm",)),
            "terminal": (["lxterminal"], ("lxterminal", "terminal")),
            "settings": (["obconf"], ("obconf", "openbox")),
            "extra": (["mousepad"], ("mousepad",)),
        },
        "cinnamon": {
            "file_manager": (["nemo"], ("nemo",)),
            "terminal": (["gnome-terminal"], ("gnome-terminal", "terminal")),
            "settings": (["cinnamon-settings"], ("cinnamon-settings", "settings")),
            "extra": (["xed"], ("xed",)),
        },
        "xfce": {
            "file_manager": (["thunar"], ("thunar",)),
            "terminal": (["xfce4-terminal"], ("xfce4-terminal", "terminal")),
            "settings": (["xfce4-settings-manager"], ("xfce4-settings", "settings")),
            "extra": (["mousepad"], ("mousepad",)),
        },
    }[edition]

    opened_procs = []
    app_results = {}

    def open_and_verify(key, stage_name, capture_event):
        cmd, keywords = app_map[key]
        if not shutil.which(cmd[0]):
            app_results[key] = {"launched": False, "reason": f"{cmd[0]}_missing"}
            return
        before = set(x11_windows(sess))
        p = run_as_user(sess, cmd)
        opened_procs.append(p)
        matched = []
        for _ in range(20):
            time.sleep(0.5)
            after = x11_windows(sess)
            new_wins = [w for w in after if w not in before]
            matched = [w for w in new_wins if any(k in w.lower() for k in keywords)]
            if matched or (p.poll() is None and new_wins):
                if not matched:
                    matched = new_wins
                break
        app_results[key] = {
            "cmd": cmd[0],
            "launched": p.poll() is None,
            "window_verified": len(matched) > 0,
            "windows": matched[:4],
        }
        send_event(port_fd, capture_event, app_results[key])
        wait_for_cmd(port_file, "ack", timeout=15)
        if stage_name:
            stages[stage_name] = run_probe(stage_name)
            send_event(port_fd, "stage_mem", stages[stage_name])

    open_and_verify("file_manager", "3_file_manager", "app_file_manager")
    open_and_verify("terminal", "4_terminal", "app_terminal")
    open_and_verify("settings", None, "app_settings")
    open_and_verify("extra", "5_multi_apps", "app_multi_apps")

    # Ask host to send Alt+F4 key event to verify keyboard + WM window close
    before_close = len(x11_windows(sess))
    send_event(port_fd, "test_alt_f4", {"windows_before": before_close})
    wait_for_cmd(port_file, "ack", timeout=15)
    time.sleep(2)
    after_alt_f4 = len(x11_windows(sess))
    app_results["keyboard_alt_f4_closed"] = after_alt_f4 < before_close

    for p in opened_procs:
        if p.poll() is None:
            try:
                os.killpg(os.getpgid(p.pid), signal.SIGTERM)
            except Exception:
                pass
    time.sleep(3)
    after_cleanup = len(x11_windows(sess))
    app_results["windows_closed_cleanup"] = after_cleanup <= desktop_info["initial_windows"] + 1
    stages["6_post_close"] = run_probe("post_close")
    send_event(port_fd, "stage_mem", stages["6_post_close"])

    # Network check
    net_info = {"nmcli_state": "missing", "ipv4": []}
    if shutil.which("nmcli"):
        net_info["nmcli_state"] = subprocess.run(["nmcli", "-t", "-f", "STATE", "general"], capture_output=True, text=True).stdout.strip()
    net_info["ipv4"] = subprocess.run(["ip", "-4", "-br", "addr"], capture_output=True, text=True).stdout.strip().splitlines()

    # ZRAM check + pressure test (only allocate bounded pressure if /dev/zram0 exists)
    zram_status = subprocess.run(["nexus-configure-zram", "status"], capture_output=True, text=True).stdout if shutil.which("nexus-configure-zram") else "{}"
    zram_pressure = {"skipped": True}
    if Path("/sys/block/zram0").exists() and Path(ZRAM_SH).is_file():
        total_mib = stages["1_post_login"].get("ram_total_mib", 512)
        p_mb = "64" if total_mib < 700 else "96"
        zres = subprocess.run(["bash", ZRAM_SH, "--pressure-mb", p_mb], capture_output=True, text=True, timeout=60)
        try:
            zram_pressure = json.loads(zres.stdout)
        except Exception:
            zram_pressure = {"returncode": zres.returncode, "stdout": zres.stdout, "stderr": zres.stderr}
        zram_pressure["post_recovery_mem"] = run_probe("post_zram_recovery")

    # Disposable-disk & installer preflight check (non-destructive)
    preflight = {}
    if shutil.which("nexus-install-preflight"):
        pres = subprocess.run(["nexus-install-preflight", "--json"], capture_output=True, text=True, timeout=20)
        try:
            preflight = json.loads(pres.stdout)
        except Exception:
            preflight = {"raw": pres.stdout}
    lsblk_out = subprocess.run(["lsblk", "-J", "-o", "NAME,SIZE,TYPE,TRAN"], capture_output=True, text=True).stdout
    ubiquity_present = bool(shutil.which("ubiquity"))

    send_event(port_fd, "complete", {
        "edition": edition,
        "desktop": desktop_info,
        "apps": app_results,
        "stages": stages,
        "network": net_info,
        "zram_status": json.loads(zram_status) if zram_status.strip().startswith("{") else {},
        "zram_pressure": zram_pressure,
        "installer_preflight": preflight,
        "ubiquity_present": ubiquity_present,
        "lsblk_vda_present": '"vda"' in lsblk_out,
    })
    return 0


if __name__ == "__main__":
    sys.exit(main())
