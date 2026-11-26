#!/usr/bin/env python3
"""Ephemeral in-guest graphical, installation, persistence, memory, and ZRAM validator.
Runs ONLY inside test VMs when QEMU attaches /dev/virtio-ports/org.nexus.test.0.
Supports both live ISO testing/installation and installed-disk multi-reboot testing.
"""
import json
import os
from pathlib import Path
import pwd
import secrets
import shutil
import signal
import subprocess
import sys
import time

VSERIAL_PATH = "/dev/virtio-ports/org.nexus.test.0"
PROBE_SH = "/usr/local/libexec/nexus-test/guest-mem-probe.sh"
ZRAM_SH = "/usr/local/libexec/nexus-test/test-zram-pressure.sh"
BOOT_COUNTER_FILE = Path("/var/lib/nexus-test/boot_counter")


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
        if 'NEXUS_EDITION="lite-lxqt"' in txt or 'NEXUS_DESKTOP="lxqt"' in txt:
            return "lite-lxqt"
        if 'NEXUS_EDITION="lite"' in txt or "openbox" in txt.lower():
            return "lite"
        if "cinnamon" in txt.lower():
            return "cinnamon"
    if shutil.which("cinnamon-session"):
        return "cinnamon"
    if shutil.which("lxqt-session"):
        return "lite-lxqt"
    if shutil.which("openbox") and not shutil.which("xfce4-session"):
        return "lite"
    return "xfce"


def detect_mode():
    if Path("/rofs").is_dir() or Path("/cdrom/casper/filesystem.squashfs").is_file():
        return "live"
    return "installed"


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
                    "home": pwd.getpwuid(uid).pw_dir,
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


def win_id_of(line):
    return line.split(None, 1)[0] if line else ""


def x11_resolution(sess):
    if not shutil.which("xdpyinfo"):
        return None
    res = subprocess.run(["xdpyinfo"], env=x_env(sess), capture_output=True, text=True, timeout=10)
    for line in res.stdout.splitlines():
        if "dimensions:" in line:
            return line.strip()
    return None


def collect_glx_diag(sess):
    diag = {}
    if shutil.which("glxinfo"):
        res = subprocess.run(["glxinfo", "-B"], env=x_env(sess), capture_output=True, text=True, timeout=10)
        diag["glxinfo"] = res.stdout.strip().splitlines()[:12]
    xs_err = Path(sess["home"]) / ".xsession-errors"
    if xs_err.is_file():
        lines = xs_err.read_text(encoding="utf-8", errors="replace").splitlines()
        diag["xsession_errors_tail"] = lines[-20:]
    return diag


def run_probe(stage):
    res = subprocess.run(["bash", PROBE_SH, "--stage", stage], capture_output=True, text=True, timeout=30)
    if res.returncode == 0 and res.stdout.strip():
        return json.loads(res.stdout)
    return {"stage": stage, "error": res.stderr.strip()}


def read_proc_names():
    res = subprocess.run(["ps", "-eo", "comm"], capture_output=True, text=True)
    return set(res.stdout.splitlines())


def verify_persistence(sess, boot_num, edition):
    home = Path(sess["home"])
    cfg_dir = home / ".config" / "nexus-os"
    docs_dir = home / "Documents"
    marker = cfg_dir / "persist-marker.json"
    doc_file = docs_dir / "nexus-reboot-check.txt"
    pw = pwd.getpwuid(sess["uid"])

    if boot_num <= 1:
        cfg_dir.mkdir(parents=True, exist_ok=True)
        docs_dir.mkdir(parents=True, exist_ok=True)
        payload = {"created_boot": boot_num, "edition": edition, "theme_pref": "nexus-obsidian", "ts": time.time()}
        marker.write_text(json.dumps(payload), encoding="utf-8")
        doc_file.write_text(f"nexus-persist-ok-boot-{boot_num}\n", encoding="utf-8")
        for p in (cfg_dir, marker, docs_dir, doc_file):
            os.chown(p, pw.pw_uid, pw.pw_gid)
        return {"written_on_boot": boot_num, "persistence_verified": None}

    ok_marker = False
    ok_doc = False
    marker_data = None
    if marker.is_file():
        try:
            marker_data = json.loads(marker.read_text(encoding="utf-8"))
            ok_marker = marker_data.get("created_boot") == 1 and marker_data.get("theme_pref") == "nexus-obsidian"
        except Exception:
            pass
    if doc_file.is_file():
        ok_doc = "nexus-persist-ok-boot-1" in doc_file.read_text(encoding="utf-8", errors="replace")
    return {
        "boot_num": boot_num,
        "marker_ok": ok_marker,
        "doc_ok": ok_doc,
        "marker_data": marker_data,
        "persistence_verified": bool(ok_marker and ok_doc),
    }


def perform_install_and_stage_test_agent(edition, port_fd, port_file, sess):
    disk_inst = shutil.which("nexus-disk-install") or "/usr/local/bin/nexus-disk-install"
    if not Path(disk_inst).is_file():
        return {"install_success": False, "reason": "nexus-disk-install_missing"}

    # Generate ephemeral runtime password (never hardcoded or logged)
    pw_file = Path("/tmp/.nexus-ephemeral-install-pw")
    pw_file.write_text(secrets.token_urlsafe(18) + "\n", encoding="utf-8")
    os.chmod(pw_file, 0o600)

    t0 = time.time()
    cmd = [
        "bash", disk_inst,
        "--disk", "/dev/vda",
        "--hostname", f"nexus-{edition}",
        "--user", "nexus",
        "--password-file", str(pw_file),
        "--autologin",
        "--edition", edition,
        "--yes-erase-disk",
    ]
    res = subprocess.run(cmd, capture_output=True, text=True, timeout=2400)
    pw_file.unlink(missing_ok=True)
    elapsed = round(time.time() - t0, 1)

    if res.returncode != 0:
        return {
            "install_success": False,
            "install_method": "nexus-disk-install",
            "elapsed_sec": elapsed,
            "returncode": res.returncode,
            "stderr_tail": res.stderr.splitlines()[-15:],
            "stdout_tail": res.stdout.splitlines()[-15:],
        }

    # Verify target disk partitions, EFI bootloader, kernel, initrd, and install test-only hook on disposable vda2
    parted_out = subprocess.run(["parted", "-s", "/dev/vda", "print"], capture_output=True, text=True).stdout
    blkid_out = subprocess.run(["blkid", "/dev/vda1", "/dev/vda2"], capture_output=True, text=True).stdout

    mnt = Path("/mnt/nexus-verify-target")
    mnt.mkdir(parents=True, exist_ok=True)
    subprocess.run(["mount", "/dev/vda2", str(mnt)], check=True)
    subprocess.run(["mount", "/dev/vda1", str(mnt / "boot" / "efi")], check=True)
    try:
        efi_ok = (mnt / "boot/efi/EFI/BOOT/BOOTX64.EFI").is_file()
        grub_cfg_ok = (mnt / "boot/grub/grub.cfg").is_file()
        vmlinuz_ok = any((mnt / "boot").glob("vmlinuz-*"))
        initrd_ok = any((mnt / "boot").glob("initrd.img-*"))
        meta_ok = (mnt / "etc/nexus-installed.json").is_file()
        efi_dir_files = sorted(str(p.relative_to(mnt / "boot/efi")) for p in (mnt / "boot/efi").rglob("*") if p.is_file())

        # Enable ttyS0 serial console inside disposable test disk grub.cfg for CI diagnostics
        grub_def = mnt / "etc/default/grub"
        if grub_def.is_file():
            gtxt = grub_def.read_text(encoding="utf-8", errors="replace")
            if "console=ttyS0" not in gtxt:
                gtxt += '\nGRUB_CMDLINE_LINUX="$GRUB_CMDLINE_LINUX console=ttyS0,115200"\n'
                grub_def.write_text(gtxt, encoding="utf-8")
                for mp in ("dev", "proc", "sys"):
                    subprocess.run(["mount", "--bind", f"/{mp}", str(mnt / mp)], check=False)
                subprocess.run(["chroot", str(mnt), "/usr/sbin/update-grub"], capture_output=True, check=False)
                for mp in ("dev", "proc", "sys"):
                    subprocess.run(["umount", "-lf", str(mnt / mp)], check=False)

        # Install ephemeral virtio-serial agent ONLY onto disposable QEMU test disk (/dev/vda2)
        test_dir = mnt / "usr/local/libexec/nexus-test"
        test_dir.mkdir(parents=True, exist_ok=True)
        for fn in ("guest-mem-probe.sh", "test-zram-pressure.sh", "nexus-guest-test.py"):
            src = Path("/usr/local/libexec/nexus-test") / fn
            if src.is_file():
                shutil.copy2(src, test_dir / fn)
                os.chmod(test_dir / fn, 0o755)
        unit = mnt / "etc/systemd/system/nexus-test-agent.service"
        unit.write_text(
            "[Unit]\n"
            "Description=NEXUS Ephemeral QEMU Test Telemetry Agent (Test Channel Only)\n"
            "ConditionPathExists=/dev/virtio-ports/org.nexus.test.0\n"
            "After=systemd-user-sessions.service lightdm.service NetworkManager.service\n\n"
            "[Service]\n"
            "Type=simple\n"
            "ExecStart=/usr/bin/python3 /usr/local/libexec/nexus-test/nexus-guest-test.py\n"
            "StandardOutput=journal\n"
            "StandardError=journal\n\n"
            "[Install]\n"
            "WantedBy=multi-user.target\n",
            encoding="utf-8",
        )
        wants = mnt / "etc/systemd/system/multi-user.target.wants"
        wants.mkdir(parents=True, exist_ok=True)
        link = wants / "nexus-test-agent.service"
        if not link.exists():
            os.symlink("../nexus-test-agent.service", link)
        state_dir = mnt / "var/lib/nexus-test"
        state_dir.mkdir(parents=True, exist_ok=True)
        (state_dir / "boot_counter").write_text("0\n", encoding="utf-8")
    finally:
        subprocess.run(["sync"], check=False)
        subprocess.run(["umount", str(mnt / "boot" / "efi")], check=False)
        subprocess.run(["umount", str(mnt)], check=False)

    return {
        "install_success": bool(efi_ok and grub_cfg_ok and vmlinuz_ok and initrd_ok and meta_ok),
        "install_method": "nexus-disk-install",
        "elapsed_sec": elapsed,
        "bootloader_efi_ok": efi_ok,
        "grub_cfg_ok": grub_cfg_ok,
        "vmlinuz_ok": vmlinuz_ok,
        "initrd_ok": initrd_ok,
        "installed_meta_ok": meta_ok,
        "efi_files": efi_dir_files[:20],
        "parted_lines": parted_out.splitlines()[:12],
        "blkid_lines": blkid_out.splitlines(),
    }


def main():
    if not Path(VSERIAL_PATH).exists():
        print("Virtio-serial test port not present; exiting cleanly.", file=sys.stderr)
        return 0

    port_fd = os.open(VSERIAL_PATH, os.O_RDWR)
    port_file = os.fdopen(os.dup(port_fd), "r", encoding="utf-8", errors="replace", buffering=1)

    t_boot_start = time.time()
    edition = detect_edition()
    mode = detect_mode()
    boot_num = 0
    if mode == "installed":
        BOOT_COUNTER_FILE.parent.mkdir(parents=True, exist_ok=True)
        if BOOT_COUNTER_FILE.is_file():
            txt = BOOT_COUNTER_FILE.read_text(encoding="utf-8").strip()
            boot_num = int(txt) + 1 if txt.isdigit() else 1
        else:
            boot_num = 1
        BOOT_COUNTER_FILE.write_text(f"{boot_num}\n", encoding="utf-8")

    send_event(port_fd, "agent_started", {"edition": edition, "mode": mode, "boot_num": boot_num})
    cfg = wait_for_cmd(port_file, "run_suite", timeout=30)
    idle_seconds = int(cfg.get("idle_seconds", 30))
    do_install = bool(cfg.get("do_install", False))
    check_ubiquity_ui = bool(cfg.get("check_ubiquity_ui", mode == "live"))
    panel_wait_sec = int(cfg.get("panel_wait_sec", 90))

    wm_targets = {
        "lite": {"openbox"},
        "lite-lxqt": {"openbox"},
        "cinnamon": {"cinnamon", "cinnamon-sessio", "cinnamon-session"},
        "xfce": {"xfwm4", "xfce4-session"},
    }.get(edition, {"openbox", "cinnamon", "xfwm4"})

    sess = None
    for _ in range(90):
        sess = find_session_proc(wm_targets)
        if sess:
            break
        time.sleep(2)
    wm_ready_sec = round(time.time() - t_boot_start, 1)

    procs = read_proc_names()
    lightdm_active = "lightdm" in procs
    if not sess:
        send_event(port_fd, "desktop_failed", {
            "edition": edition,
            "mode": mode,
            "boot_num": boot_num,
            "lightdm_active": lightdm_active,
            "mem": run_probe("desktop_timeout"),
            "procs_sample": sorted(procs)[:40],
        })
        return 1

    stages = {}
    stages["1_post_login"] = run_probe("post_login")
    send_event(port_fd, "stage_mem", stages["1_post_login"])
    if shutil.which("xset"):
        try:
            subprocess.run(
                ["su", "-s", "/bin/sh", sess["user"], "-c", f"DISPLAY={sess['display']} xset s off -dpms"],
                env={**os.environ, "DISPLAY": sess["display"], "XAUTHORITY": sess["xauthority"]},
                capture_output=True,
                timeout=5,
            )
        except Exception:
            pass

    # Wait up to panel_wait_sec for panel + desktop window to actually map in X11
    panel_expected = {"lite": "tint2", "lite-lxqt": "lxqt-panel", "cinnamon": "cinnamon", "xfce": "xfce4-panel"}.get(edition)
    panel_seen = False
    panel_win_mapped = False
    max_iters = max(4, panel_wait_sec // 2)
    for i in range(max_iters):
        procs = read_proc_names()
        wins = x11_windows(sess)
        win_txt = "\n".join(wins).lower()
        if edition == "lite":
            panel_win_mapped = ("tint2" in win_txt) or (panel_expected in procs and len(wins) >= 1)
        elif edition == "lite-lxqt":
            panel_win_mapped = ("lxqt-panel" in win_txt and "pcmanfm-qt" in win_txt) or (
                i >= 15 and ("lxqt-panel" in win_txt or (panel_expected in procs and len(wins) >= 1))
            )
        elif edition == "cinnamon":
            panel_win_mapped = ("desktop" in win_txt or "muffin" in win_txt or "cinnamon" in win_txt) and len(wins) >= 2
        else:
            panel_win_mapped = ("xfce4-panel" in win_txt or "xfdesktop" in win_txt) and len(wins) >= 2
        if panel_expected in procs:
            panel_seen = True
            if panel_win_mapped and i >= 4:
                break
        time.sleep(2)
    panel_ready_sec = round(time.time() - t_boot_start, 1)

    procs = read_proc_names()
    panel_rss_mib = None
    if panel_expected:
        ps_panel = subprocess.run(["ps", "-C", panel_expected, "-o", "rss="], capture_output=True, text=True)
        rss_vals = [int(x) for x in ps_panel.stdout.split() if x.isdigit()]
        if rss_vals:
            panel_rss_mib = round(sum(rss_vals) / 1024.0, 2)

    desktop_info = {
        "edition": edition,
        "mode": mode,
        "boot_num": boot_num,
        "user": sess["user"],
        "wm": sess["comm"],
        "wm_ready_sec": wm_ready_sec,
        "panel_ready_sec": panel_ready_sec,
        "lightdm_active": lightdm_active,
        "panel_running": panel_seen or (panel_expected in procs),
        "panel_win_mapped": panel_win_mapped,
        "panel_name": panel_expected,
        "panel_rss_mib": panel_rss_mib,
        "resolution": x11_resolution(sess),
        "initial_windows": len(x11_windows(sess)),
        "glx_diag": collect_glx_diag(sess) if edition == "cinnamon" else {},
    }
    send_event(port_fd, "desktop_ready", desktop_info)
    wait_for_cmd(port_file, "ack", timeout=15)

    stages["2_post_session_init"] = run_probe("post_session_init")
    send_event(port_fd, "stage_mem", stages["2_post_session_init"])

    time.sleep(max(1, idle_seconds))
    stages["3_idle"] = run_probe(f"idle_{idle_seconds}s")
    send_event(port_fd, "stage_mem", stages["3_idle"])

    app_map = {
        "lite": {
            "file_manager": (["pcmanfm"], ("pcmanfm",)),
            "terminal": (["lxterminal"], ("lxterminal", "terminal")),
            "settings": (["obconf"], ("obconf", "openbox")),
            "extra": (["mousepad", "xed", "lxtask"], ("mousepad", "xed", "lxtask")),
        },
        "lite-lxqt": {
            "file_manager": (["pcmanfm-qt"], ("pcmanfm-qt", "pcmanfm")),
            "terminal": (["qterminal"], ("qterminal", "terminal")),
            "settings": (["lxqt-config", "obconf-qt"], ("lxqt-config", "configuration", "obconf")),
            "extra": (["featherpad", "qps", "lxqt-archiver"], ("featherpad", "qps", "lxqt-archiver")),
        },
        "cinnamon": {
            "file_manager": (["nemo"], ("nemo",)),
            "terminal": (["gnome-terminal"], ("gnome-terminal", "terminal")),
            "settings": (["cinnamon-settings"], ("cinnamon-settings", "settings")),
            "extra": (["xed", "galculator"], ("xed", "galculator")),
        },
        "xfce": {
            "file_manager": (["thunar"], ("thunar",)),
            "terminal": (["xfce4-terminal"], ("xfce4-terminal", "terminal")),
            "settings": (["xfce4-settings-manager"], ("xfce4-settings", "settings")),
            "extra": (["xed", "mousepad", "galculator"], ("xed", "mousepad", "galculator")),
        },
    }[edition]

    opened_procs = []
    tracked_win_ids = []
    app_results = {}

    def open_and_verify(key, stage_name, capture_event):
        candidates, keywords = app_map[key]
        chosen = next((c for c in candidates if shutil.which(c)), None)
        if not chosen:
            app_results[key] = {"launched": False, "reason": f"{candidates[0]}_missing"}
            if stage_name:
                stages[stage_name] = run_probe(stage_name)
                send_event(port_fd, "stage_mem", stages[stage_name])
            return
        cmd = [chosen]
        before = set(x11_windows(sess))
        p = run_as_user(sess, cmd)
        opened_procs.append(p)
        matched = []
        for _ in range(28):
            time.sleep(0.5)
            after = x11_windows(sess)
            new_wins = [w for w in after if w not in before]
            matched = [w for w in new_wins if any(k in w.lower() for k in keywords)]
            if matched or (p.poll() is None and new_wins):
                if not matched:
                    matched = new_wins
                break
        for w in matched:
            wid = win_id_of(w)
            if wid:
                tracked_win_ids.append(wid)
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

    open_and_verify("file_manager", "4_file_manager", "app_file_manager")
    open_and_verify("terminal", "5_terminal", "app_terminal")
    open_and_verify("settings", None, "app_settings")
    open_and_verify("extra", "6_multi_apps", "app_multi_apps")

    time.sleep(2)
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
    time.sleep(2)
    for p in opened_procs:
        if p.poll() is None:
            try:
                os.killpg(os.getpgid(p.pid), signal.SIGKILL)
            except Exception:
                pass
    time.sleep(2)
    remaining_ids = {win_id_of(w) for w in x11_windows(sess)}
    still_open = [wid for wid in tracked_win_ids if wid in remaining_ids]
    app_results["windows_closed_cleanup"] = len(still_open) == 0
    stages["7_post_close"] = run_probe("post_close")
    send_event(port_fd, "stage_mem", stages["7_post_close"])

    # Network check
    net_info = {"nmcli_state": "missing", "ipv4": []}
    if shutil.which("nmcli"):
        net_info["nmcli_state"] = subprocess.run(["nmcli", "-t", "-f", "STATE", "general"], capture_output=True, text=True).stdout.strip()
    net_info["ipv4"] = subprocess.run(["ip", "-4", "-br", "addr"], capture_output=True, text=True).stdout.strip().splitlines()

    # ZRAM check + pressure test (when /dev/zram0 exists)
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

    # Preflight & storage detection
    preflight = {}
    if shutil.which("nexus-install-preflight"):
        pres = subprocess.run(["nexus-install-preflight", "--json"], capture_output=True, text=True, timeout=20)
        try:
            preflight = json.loads(pres.stdout)
        except Exception:
            preflight = {"raw": pres.stdout}
    lsblk_out = subprocess.run(["lsblk", "-J", "-o", "NAME,SIZE,TYPE,TRAN"], capture_output=True, text=True).stdout
    ubiquity_present = bool(shutil.which("ubiquity"))

    # Hardware inventory & security audit summaries inside booted guest (if tools installed)
    hw_summary = {}
    if shutil.which("nexus-hw-inventory"):
        hres = subprocess.run(["nexus-hw-inventory", "--json"], capture_output=True, text=True, timeout=20)
        if hres.returncode == 0 and hres.stdout.strip():
            try:
                hd = json.loads(hres.stdout)
                hw_summary = {
                    "firmware": hd.get("firmware", {}).get("mode"),
                    "gpus": [(g.get("driver"), (g.get("classification") or {}).get("status")) for g in hd.get("gpus", [])],
                    "storage": [(s.get("device"), s.get("driver"), (s.get("classification") or {}).get("status")) for s in hd.get("storage", [])],
                    "missing_fw_count": len(hd.get("firmware", {}).get("missing_firmware_hints", [])),
                }
            except Exception:
                pass
    sec_summary = {}
    if shutil.which("nexus-security-audit"):
        sres = subprocess.run(["nexus-security-audit", "--json"], capture_output=True, text=True, timeout=20)
        if sres.returncode == 0 and sres.stdout.strip():
            try:
                sd = json.loads(sres.stdout)
                sec_summary = sd.get("summary") or {}
            except Exception:
                pass

    # Live-mode Ubiquity UI check & actual disk installation
    ubiquity_ui = {"checked": False}
    install_report = {"executed": False}
    if mode == "live":
        if check_ubiquity_ui and ubiquity_present and stages["1_post_login"].get("ram_total_mib", 0) >= 850:
            if shutil.which("xhost"):
                subprocess.run(["xhost", "+si:localuser:root"], env=x_env(sess), capture_output=True, text=True)
            before_ub = set(x11_windows(sess))
            ub_env = x_env(sess)
            ub_proc = subprocess.Popen(["ubiquity", "gtk_ui"], env=ub_env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)
            ub_wins = []
            for _ in range(50):
                time.sleep(0.5)
                after_ub = x11_windows(sess)
                new_ub = [w for w in after_ub if w not in before_ub]
                ub_wins = [w for w in new_ub if any(k in w.lower() for k in ("ubiquity", "install"))]
                if ub_wins:
                    break
            ubiquity_ui = {
                "checked": True,
                "launched": ub_proc.poll() is None,
                "window_verified": len(ub_wins) > 0,
                "windows": ub_wins[:3],
            }
            send_event(port_fd, "ubiquity_ui", ubiquity_ui)
            wait_for_cmd(port_file, "ack", timeout=15)
            try:
                os.killpg(os.getpgid(ub_proc.pid), signal.SIGTERM)
                ub_proc.wait(timeout=5)
            except Exception:
                try:
                    os.killpg(os.getpgid(ub_proc.pid), signal.SIGKILL)
                except Exception:
                    pass

        if do_install:
            send_event(port_fd, "live_done", {
                "edition": edition,
                "mode": mode,
                "boot_num": boot_num,
                "desktop": desktop_info,
                "apps": app_results,
                "stages": stages,
                "network": net_info,
                "zram_status": json.loads(zram_status) if zram_status.strip().startswith("{") else {},
                "zram_pressure": zram_pressure,
                "installer_preflight": preflight,
                "ubiquity_present": ubiquity_present,
                "ubiquity_ui": ubiquity_ui,
                "hw_summary": hw_summary,
                "sec_summary": sec_summary,
                "lsblk_vda_present": '"vda"' in lsblk_out,
            })
            install_report = perform_install_and_stage_test_agent(edition, port_fd, port_file, sess)
            install_report["executed"] = True
            send_event(port_fd, "install_done", install_report)

    installed_checks = {}
    persistence = {}
    if mode == "installed":
        root_src = subprocess.run(["findmnt", "-n", "-o", "SOURCE", "/"], capture_output=True, text=True).stdout.strip()
        failed_units = subprocess.run(["systemctl", "--failed", "--no-legend"], capture_output=True, text=True).stdout.strip().splitlines()
        err_lines = subprocess.run(["journalctl", "-p", "err", "-b", "--no-pager", "-q"], capture_output=True, text=True).stdout.strip().splitlines()
        installed_checks = {
            "root_source": root_src,
            "booted_from_vda": root_src.startswith("/dev/vda"),
            "live_iso_absent": not Path("/rofs").exists() and not Path("/cdrom/casper/filesystem.squashfs").exists(),
            "efi_boot_ok": Path("/boot/efi/EFI/BOOT/BOOTX64.EFI").is_file(),
            "grub_cfg_ok": Path("/boot/grub/grub.cfg").is_file(),
            "installed_meta_ok": Path("/etc/nexus-installed.json").is_file(),
            "mint_user_absent": not Path("/home/mint").exists(),
            "failed_systemd_units": len(failed_units),
            "journal_err_count": len(err_lines),
            "journal_err_sample": err_lines[:8],
        }
        persistence = verify_persistence(sess, boot_num, edition)

    send_event(port_fd, "complete", {
        "edition": edition,
        "mode": mode,
        "boot_num": boot_num,
        "desktop": desktop_info,
        "apps": app_results,
        "stages": stages,
        "network": net_info,
        "zram_status": json.loads(zram_status) if zram_status.strip().startswith("{") else {},
        "zram_pressure": zram_pressure,
        "installer_preflight": preflight,
        "ubiquity_present": ubiquity_present,
        "ubiquity_ui": ubiquity_ui,
        "install_report": install_report,
        "installed_checks": installed_checks,
        "persistence": persistence,
        "hw_summary": hw_summary,
        "sec_summary": sec_summary,
        "lsblk_vda_present": '"vda"' in lsblk_out,
    })

    next_cmd = wait_for_cmd(port_file, "", timeout=20)
    action = next_cmd.get("cmd")
    os.close(port_fd)
    if action == "reboot":
        subprocess.Popen(["systemctl", "reboot"])
    elif action == "poweroff":
        subprocess.Popen(["systemctl", "poweroff"])
    return 0


if __name__ == "__main__":
    sys.exit(main())
