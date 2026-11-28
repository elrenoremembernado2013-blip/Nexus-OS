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
import stat
import subprocess
import sys
import time
import urllib.error
import urllib.request

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


def user_systemd_env(sess):
    env = x_env(sess)
    uid = sess["uid"]
    rt = f"/run/user/{uid}"
    env["HOME"] = sess["home"]
    env["USER"] = sess["user"]
    env["LOGNAME"] = sess["user"]
    env["XDG_RUNTIME_DIR"] = rt
    if not env.get("DBUS_SESSION_BUS_ADDRESS"):
        env["DBUS_SESSION_BUS_ADDRESS"] = f"unix:path={rt}/bus"
    return env


def run_as_user_capture(sess, cmd_list, timeout=15):
    def preexec():
        pw = pwd.getpwuid(sess["uid"])
        os.setgid(pw.pw_gid)
        os.setuid(pw.pw_uid)

    return subprocess.run(
        cmd_list,
        env=user_systemd_env(sess),
        preexec_fn=preexec,
        capture_output=True,
        text=True,
        timeout=timeout,
    )


def http_json(url, method="GET", token=None, body=None, timeout=10):
    headers = {}
    if token is not None:
        headers["X-Nexus-Token"] = token
    data = None
    if body is not None:
        headers["Content-Type"] = "application/json"
        data = json.dumps(body).encode("utf-8")
    req = urllib.request.Request(url, data=data, headers=headers, method=method)
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            raw = resp.read().decode("utf-8", errors="replace")
            return resp.status, json.loads(raw) if raw else {}
    except urllib.error.HTTPError as err:
        raw = err.read().decode("utf-8", errors="replace")
        try:
            parsed = json.loads(raw) if raw else {}
        except json.JSONDecodeError:
            parsed = {"raw": raw}
        return err.code, parsed
    except Exception as exc:
        return 0, {"error": str(exc)}


def check_port_loopback_only(port):
    hex_port = f"{int(port):04X}"
    loopback_found = False
    wildcard_found = False
    for proc_file, is_v6 in (("/proc/net/tcp", False), ("/proc/net/tcp6", True)):
        p = Path(proc_file)
        if not p.is_file():
            continue
        for line in p.read_text(encoding="utf-8", errors="replace").splitlines()[1:]:
            cols = line.split()
            if len(cols) < 4:
                continue
            local_addr = cols[1]
            st = cols[3]
            if st != "0A" or ":" not in local_addr:
                continue
            addr_hex, port_hex = local_addr.split(":", 1)
            if port_hex.upper() != hex_port:
                continue
            if not is_v6 and addr_hex.upper() == "0100007F":
                loopback_found = True
            elif is_v6 and addr_hex.upper() == "00000000000000000000000001000000":
                loopback_found = True
            else:
                wildcard_found = True
    return loopback_found and not wildcard_found, loopback_found, wildcard_found


def check_native_services(sess, edition):
    uid = sess["uid"]
    svc_result = {
        "unit_file_present": Path("/etc/systemd/user/nexus-system-bridge.service").is_file(),
        "bridge_bin_present": bool(shutil.which("nexus-system-bridge")),
        "service_state": "unknown",
        "bridge_service_active": False,
        "runtime_file_exists": False,
        "runtime_file_mode": None,
        "runtime_file_0600": False,
        "runtime_url_loopback": False,
        "loopback_only": False,
        "unauth_rejected_401": False,
        "pty_bash_ok": False,
        "telemetry_ok": False,
        "settings_tools_ok": False,
        "settings_launch_ok": False,
        "missing_app_error_ok": False,
        "store_sources_ok": False,
        "gaming_status_ok": False,
        "security_status_ok": False,
        "control_centre_ok": False,
        "files_jailed_ok": False,
        "quantum_ok": False,
        "perf_ok": False,
        "hw_ok": False,
        "compat_ok": False,
        "wallpaper_cli_ok": False,
        "ui_bundle_present": Path("/usr/local/share/nexus-os/ui/index.html").is_file() and bool(shutil.which("nexus-launch-app")),
    }

    # 1. Wait up to 16s for systemd --user nexus-system-bridge.service activation
    rt_path = Path(f"/run/user/{uid}/nexus-os/system-bridge.json")
    for _ in range(16):
        try:
            st_res = run_as_user_capture(sess, ["systemctl", "--user", "is-active", "nexus-system-bridge.service"], timeout=5)
            svc_result["service_state"] = st_res.stdout.strip() or st_res.stderr.strip() or f"rc={st_res.returncode}"
            if st_res.returncode == 0 and svc_result["service_state"] == "active" and rt_path.is_file():
                break
        except Exception as exc:
            svc_result["service_state"] = f"err:{exc}"
        time.sleep(1)
    svc_result["bridge_service_active"] = svc_result["service_state"] == "active"
    if not svc_result["bridge_service_active"]:
        try:
            jres = run_as_user_capture(sess, ["journalctl", "--user", "-u", "nexus-system-bridge.service", "-n", "15", "--no-pager"], timeout=5)
            svc_result["bridge_journal_tail"] = (jres.stdout or jres.stderr).splitlines()[-10:]
        except Exception:
            pass

    # 2. Runtime token file permissions (0600, owned by user) & loopback URL
    bridge_url = None
    bridge_token = None
    if rt_path.is_file():
        svc_result["runtime_file_exists"] = True
        try:
            st = rt_path.stat()
            mode = stat.S_IMODE(st.st_mode)
            svc_result["runtime_file_mode"] = oct(mode)
            svc_result["runtime_file_owner_ok"] = st.st_uid == uid
            svc_result["runtime_file_0600"] = (mode == 0o600 and st.st_uid == uid)
            rt_data = json.loads(rt_path.read_text(encoding="utf-8"))
            bridge_url = str(rt_data.get("url") or "")
            bridge_token = str(rt_data.get("token") or "")
            svc_result["runtime_url_loopback"] = bridge_url.startswith("http://127.0.0.1:")
            svc_result["token_present"] = bool(bridge_token)
            svc_result["bridge_pid"] = rt_data.get("pid")
        except Exception as exc:
            svc_result["runtime_error"] = str(exc)

    # 3. Loopback-only socket + unauthorized rejection (401)
    if bridge_url and bridge_token and svc_result["runtime_url_loopback"]:
        try:
            port = int(bridge_url.rsplit(":", 1)[1].split("/", 1)[0])
            lb_only, lb_found, wild_found = check_port_loopback_only(port)
            svc_result["loopback_only"] = lb_only
            svc_result["loopback_socket_found"] = lb_found
            svc_result["wildcard_socket_found"] = wild_found
        except Exception as exc:
            svc_result["socket_error"] = str(exc)

        code_unauth, _ = http_json(f"{bridge_url}/api/telemetry", method="GET", token=None)
        svc_result["unauth_status_code"] = code_unauth
        svc_result["unauth_rejected_401"] = code_unauth == 401

        # 4. Real GNU Bash PTY Terminal
        c_open, r_open = http_json(f"{bridge_url}/api/terminal/open", method="POST", token=bridge_token, body={"cols": 100, "rows": 30})
        sid = r_open.get("sessionId") if c_open == 200 else None
        if sid:
            try:
                http_json(
                    f"{bridge_url}/api/terminal/write",
                    method="POST",
                    token=bridge_token,
                    body={"sessionId": sid, "data": 'printf "NEXUS_PTY_%s:%s\\n" "VERIFIED" "$BASH_VERSION"\n'},
                )
                out_acc = ""
                deadline = time.time() + 6.0
                while time.time() < deadline:
                    c_rd, r_rd = http_json(f"{bridge_url}/api/terminal/read?sessionId={sid}", method="GET", token=bridge_token)
                    if c_rd == 200:
                        out_acc += str(r_rd.get("output") or "")
                        if "NEXUS_PTY_VERIFIED:" in out_acc:
                            break
                    time.sleep(0.2)
                for line in out_acc.splitlines():
                    clean_line = line.strip()
                    if clean_line.startswith("NEXUS_PTY_VERIFIED:"):
                        svc_result["pty_bash_sample"] = clean_line[:80]
                        break
                svc_result["pty_bash_ok"] = any(
                    ln.strip().startswith("NEXUS_PTY_VERIFIED:") for ln in out_acc.splitlines()
                )
            finally:
                http_json(f"{bridge_url}/api/terminal/close", method="POST", token=bridge_token, body={"sessionId": sid})

        # 5. System Monitor /proc + /sys telemetry
        c_tel, r_tel = http_json(f"{bridge_url}/api/telemetry", method="GET", token=bridge_token)
        if c_tel == 200 and isinstance(r_tel, dict):
            proc_d = r_tel.get("processor") or {}
            mem_d = r_tel.get("memory") or {}
            stor_d = r_tel.get("storage") or {}
            procs_d = r_tel.get("processes") or {}
            proc_items = procs_d.get("items") or []
            svc_result["telemetry_ok"] = bool(
                str(proc_d.get("summary") or "") not in ("", "Unavailable")
                and str(mem_d.get("summary") or "") not in ("", "Unavailable")
                and str(stor_d.get("summary") or "") not in ("", "Unavailable")
                and len(proc_items) > 0
            )
            svc_result["telemetry_summary"] = {
                "cpu_summary": proc_d.get("summary"),
                "mem_summary": mem_d.get("summary"),
                "storage_summary": stor_d.get("summary"),
                "proc_count": len(proc_items),
            }

        # 6. Native Settings tools + real GUI launch
        c_tools, r_tools = http_json(f"{bridge_url}/api/tools", method="GET", token=bridge_token)
        if c_tools == 200 and isinstance(r_tools, dict):
            svc_result["tools_detected"] = {k: (v.get("command") if v.get("available") else None) for k, v in r_tools.items()}
            svc_result["settings_tools_ok"] = bool(
                r_tools.get("files", {}).get("available")
                and r_tools.get("terminal", {}).get("available")
                and r_tools.get("monitor", {}).get("available")
            )
            launch_cat = next((c for c in ("display", "network", "power", "files", "terminal") if r_tools.get(c, {}).get("available")), None)
            if launch_cat:
                c_l, r_l = http_json(f"{bridge_url}/api/tools/launch", method="POST", token=bridge_token, body={"category": launch_cat})
                svc_result["settings_launch_category"] = launch_cat
                svc_result["settings_launch_cmd"] = r_l.get("command")
                svc_result["settings_launch_ok"] = (c_l == 200 and r_l.get("ok") is True)
                if not svc_result["settings_launch_ok"]:
                    svc_result["settings_launch_msg"] = r_l.get("message")
                else:
                    time.sleep(1.0)
                    cmd_name = str(r_l.get("command") or "")
                    if cmd_name:
                        subprocess.run(["pkill", "-u", str(uid), "-n", cmd_name], capture_output=True)

            # 7. Useful missing-app error reporting (unknown category + uninstalled allowlisted category)
            c_unk, r_unk = http_json(f"{bridge_url}/api/tools/launch", method="POST", token=bridge_token, body={"category": "nonexistent-tool"})
            unk_ok = (c_unk == 400 and r_unk.get("ok") is False and "Unknown tool category" in str(r_unk.get("message", "")))
            missing_cat = next((k for k, v in r_tools.items() if not v.get("available")), None)
            miss_ok = True
            if missing_cat:
                c_m, r_m = http_json(f"{bridge_url}/api/tools/launch", method="POST", token=bridge_token, body={"category": missing_cat})
                miss_ok = (c_m == 400 and r_m.get("ok") is False and len(str(r_m.get("message", ""))) > 10)
                svc_result["missing_app_sample"] = {"category": missing_cat, "code": c_m, "message": r_m.get("message")}
            svc_result["missing_app_error_ok"] = bool(unk_ok and miss_ok)

        # 8. Gaming Hub capabilities (read-only, never installs gaming clients)
        c_gam, r_gam = http_json(f"{bridge_url}/api/gaming/status", method="GET", token=bridge_token, timeout=15)
        if c_gam == 200 and isinstance(r_gam, dict):
            svc_result["gaming_status_ok"] = bool("steam" in r_gam and "graphics" in r_gam and "capabilities" in r_gam)
            svc_result["gaming_summary"] = {
                "steam_installed": (r_gam.get("steam") or {}).get("installed"),
                "vulkan": (r_gam.get("graphics") or {}).get("vulkan"),
                "gaming_mode": r_gam.get("gamingMode"),
                "apt_avail": (r_gam.get("capabilities") or {}).get("apt_available"),
            }

        # 9. Security & Privacy actual status (read-only, never modifies firewall)
        c_sec, r_sec = http_json(f"{bridge_url}/api/security/status", method="GET", token=bridge_token, timeout=15)
        if c_sec == 200 and isinstance(r_sec, dict):
            svc_result["security_status_ok"] = bool(
                isinstance(r_sec.get("firewall"), dict)
                and isinstance(r_sec.get("secure_boot"), dict)
                and isinstance(r_sec.get("disk_encryption"), dict)
                and isinstance(r_sec.get("security_updates"), dict)
                and isinstance(r_sec.get("account"), dict)
            )
            svc_result["security_summary"] = {
                "firewall": (r_sec.get("firewall") or {}).get("status"),
                "secure_boot": (r_sec.get("secure_boot") or {}).get("status"),
                "disk_encryption": (r_sec.get("disk_encryption") or {}).get("status"),
                "user": (r_sec.get("account") or {}).get("user"),
            }

        # 9b. Control Centre status & notifications integration
        c_cc, r_cc = http_json(f"{bridge_url}/api/control-centre", method="GET", token=bridge_token, timeout=10)
        if c_cc == 200 and isinstance(r_cc, dict):
            svc_result["control_centre_ok"] = bool("do_not_disturb" in r_cc or "network" in r_cc or "sound" in r_cc or "ok" in r_cc)

        # 9c. $HOME-jailed File Manager CRUD + 403 out-of-$HOME confinement
        c_fl, r_fl = http_json(f"{bridge_url}/api/files/list", method="GET", token=bridge_token, timeout=10)
        c_esc, _ = http_json(f"{bridge_url}/api/files/preview?path=/etc/passwd", method="GET", token=bridge_token, timeout=10)
        crud_ok = False
        if c_fl == 200 and isinstance(r_fl, dict) and c_esc == 403:
            tname = f".nexus-p23-{os.getpid()}"
            c_mk, _ = http_json(f"{bridge_url}/api/files/mkdir", method="POST", token=bridge_token, body={"path": "", "name": tname})
            c_tc, _ = http_json(f"{bridge_url}/api/files/touch", method="POST", token=bridge_token, body={"path": tname, "name": "probe.txt"})
            c_rn, _ = http_json(f"{bridge_url}/api/files/rename", method="POST", token=bridge_token, body={"path": f"{tname}/probe.txt", "newName": "probe2.txt"})
            c_pv, _ = http_json(f"{bridge_url}/api/files/preview?path={tname}/probe2.txt", method="GET", token=bridge_token)
            c_d1, _ = http_json(f"{bridge_url}/api/files/delete", method="POST", token=bridge_token, body={"path": f"{tname}/probe2.txt"})
            c_d2, _ = http_json(f"{bridge_url}/api/files/delete", method="POST", token=bridge_token, body={"path": tname})
            crud_ok = (c_mk == 200 and c_tc == 200 and c_rn == 200 and c_pv == 200 and c_d1 == 200 and c_d2 == 200)
        svc_result["files_jailed_ok"] = bool(crud_ok and c_esc == 403)

        # 9d. Quantum local notes persistence
        c_qn_get, r_qn_get = http_json(f"{bridge_url}/api/quantum/notes", method="GET", token=bridge_token, timeout=10)
        if c_qn_get == 200 and isinstance(r_qn_get, dict):
            orig_notes = r_qn_get.get("notes") if isinstance(r_qn_get.get("notes"), list) else []
            test_notes = orig_notes + [{"id": "p23-probe", "title": "Phase 23 Probe", "body": "verified"}]
            c_qn_post, _ = http_json(f"{bridge_url}/api/quantum/notes", method="POST", token=bridge_token, body={"notes": test_notes})
            c_qn_chk, r_qn_chk = http_json(f"{bridge_url}/api/quantum/notes", method="GET", token=bridge_token)
            http_json(f"{bridge_url}/api/quantum/notes", method="POST", token=bridge_token, body={"notes": orig_notes})
            svc_result["quantum_ok"] = bool(c_qn_post == 200 and c_qn_chk == 200 and any(n.get("id") == "p23-probe" for n in (r_qn_chk.get("notes") or [])))

        # 9e. Performance Centre overview
        c_pf, r_pf = http_json(f"{bridge_url}/api/performance/overview", method="GET", token=bridge_token, timeout=10)
        if c_pf == 200 and isinstance(r_pf, dict):
            svc_result["perf_ok"] = bool("memory" in r_pf or "low_resource_mode" in r_pf or "disk" in r_pf)

        # 9f. Hardware Compatibility Centre inventory + redacted diagnostics
        c_hw1, r_hw1 = http_json(f"{bridge_url}/api/hardware/inventory", method="GET", token=bridge_token, timeout=15)
        c_hw2, r_hw2 = http_json(f"{bridge_url}/api/hardware/diagnostics", method="GET", token=bridge_token, timeout=15)
        svc_result["hw_ok"] = bool(c_hw1 == 200 and isinstance(r_hw1, dict) and c_hw2 == 200 and isinstance(r_hw2, dict) and r_hw2.get("privacy_redacted") is True)

        # 9g. NEXUS Compatibility Centre status, catalog & security checks
        c_cs, r_cs = http_json(f"{bridge_url}/api/compat/status", method="GET", token=bridge_token, timeout=10)
        c_ccat, r_ccat = http_json(f"{bridge_url}/api/compat/catalog", method="GET", token=bridge_token, timeout=10)
        c_ci, _ = http_json(f"{bridge_url}/api/compat/inspect?path=/etc/passwd", method="GET", token=bridge_token, timeout=10)
        c_cl, _ = http_json(f"{bridge_url}/api/compat/launch", method="POST", token=bridge_token, body={"path": "nope.exe"})
        svc_result["compat_ok"] = bool(
            c_cs == 200 and isinstance(r_cs, dict) and "runtimes" in r_cs
            and c_ccat == 200 and isinstance(r_ccat, dict) and len(r_ccat.get("entries") or []) > 0
            and c_ci == 403 and c_cl == 400
        )

    # 10. Store APT / Flatpak availability (read-only) + wallpaper/control-centre CLIs
    wp_bin = shutil.which("nexus-wallpaper")
    cc_bin = shutil.which("nexus-control-centre")
    if wp_bin and cc_bin:
        try:
            wres = run_as_user_capture(sess, [wp_bin, "list"], timeout=10)
            cres = run_as_user_capture(sess, [cc_bin, "status"], timeout=10)
            svc_result["wallpaper_cli_ok"] = (wres.returncode == 0 and cres.returncode == 0)
        except Exception:
            pass
    store_bin = shutil.which("nexus-store-cli")
    if store_bin:
        try:
            sres = run_as_user_capture(sess, [store_bin, "sources"], timeout=10)
            if sres.returncode == 0 and sres.stdout.strip():
                sdata = json.loads(sres.stdout)
                svc_result["store_sources"] = sdata
                svc_result["store_sources_ok"] = bool(sdata.get("apt") is True and "flatpak" in sdata)
        except Exception as exc:
            svc_result["store_error"] = str(exc)

    # 11. Offline NEXUS desktop UI bundle & native launcher CLI parity
    svc_result["offline_ui_present"] = Path("/usr/local/share/nexus-os/ui/index.html").is_file()
    required_clis = [
        "nexus-launch-app",
        "nexus-store-cli",
        "nexus-control-centre",
        "nexus-performance-cli",
        "nexus-compat-cli",
        "nexus-wallpaper",
        "nexus-firstboot",
    ]
    svc_result["nexus_cli_tools_ok"] = all(bool(shutil.which(name)) for name in required_clis)

    return svc_result


def disable_screen_blanking(sess, edition):
    if shutil.which("xset"):
        try:
            run_as_user_capture(sess, ["xset", "s", "off", "s", "noblank", "-dpms"], timeout=5)
            run_as_user_capture(sess, ["xset", "s", "reset"], timeout=5)
            run_as_user_capture(sess, ["xset", "dpms", "force", "on"], timeout=5)
        except Exception:
            pass
    if edition == "cinnamon" and shutil.which("gsettings"):
        for schema, key, val in (
            ("org.cinnamon.desktop.session", "idle-delay", "0"),
            ("org.cinnamon.desktop.screensaver", "lock-enabled", "false"),
            ("org.cinnamon.settings-daemon.plugins.power", "sleep-display-ac", "0"),
            ("org.cinnamon.settings-daemon.plugins.power", "sleep-display-battery", "0"),
        ):
            try:
                run_as_user_capture(sess, ["gsettings", "set", schema, key, val], timeout=5)
            except Exception:
                pass
    elif edition == "xfce" and shutil.which("xfconf-query"):
        for prop, ptype, val in (
            ("/xfce4-power-manager/dpms-enabled", "bool", "false"),
            ("/xfce4-power-manager/blank-on-ac", "int", "0"),
            ("/xfce4-power-manager/blank-on-battery", "int", "0"),
        ):
            try:
                run_as_user_capture(sess, ["xfconf-query", "-c", "xfce4-power-manager", "-p", prop, "-n", "-t", ptype, "-s", val], timeout=5)
            except Exception:
                pass


def read_proc_names():
    res = subprocess.run(["ps", "-eo", "comm"], capture_output=True, text=True)
    return set(res.stdout.splitlines())


def verify_persistence(sess, boot_num, edition):
    home = Path(sess["home"])
    cfg_dir = home / ".config" / "nexus-os"
    docs_dir = home / "Documents"
    marker = cfg_dir / "persist-marker.json"
    personalisation_file = cfg_dir / "personalisation.json"
    doc_file = docs_dir / "nexus-reboot-check.txt"
    pw = pwd.getpwuid(sess["uid"])

    if boot_num <= 1:
        cfg_dir.mkdir(parents=True, exist_ok=True)
        docs_dir.mkdir(parents=True, exist_ok=True)
        payload = {"created_boot": boot_num, "edition": edition, "theme_pref": "nexus-obsidian", "ts": time.time()}
        pers_payload = {"wallpaper": "obsidian-glass", "accent": "#4cc9f0", "theme": "dark", "low_resource_mode": edition in ("lite", "lite-lxqt"), "created_boot": boot_num}
        marker.write_text(json.dumps(payload), encoding="utf-8")
        personalisation_file.write_text(json.dumps(pers_payload), encoding="utf-8")
        doc_file.write_text(f"nexus-persist-ok-boot-{boot_num}\n", encoding="utf-8")
        for p in (cfg_dir, marker, personalisation_file, docs_dir, doc_file):
            os.chown(p, pw.pw_uid, pw.pw_gid)
        return {"written_on_boot": boot_num, "persistence_verified": None}

    ok_marker = False
    ok_pers = False
    ok_doc = False
    marker_data = None
    if marker.is_file():
        try:
            marker_data = json.loads(marker.read_text(encoding="utf-8"))
            ok_marker = marker_data.get("created_boot") == 1 and marker_data.get("theme_pref") == "nexus-obsidian"
        except Exception:
            pass
    if personalisation_file.is_file():
        try:
            pdata = json.loads(personalisation_file.read_text(encoding="utf-8"))
            ok_pers = pdata.get("wallpaper") == "obsidian-glass" and pdata.get("accent") == "#4cc9f0"
        except Exception:
            pass
    if doc_file.is_file():
        ok_doc = "nexus-persist-ok-boot-1" in doc_file.read_text(encoding="utf-8", errors="replace")
    return {
        "boot_num": boot_num,
        "marker_ok": ok_marker,
        "personalisation_ok": ok_pers,
        "doc_ok": ok_doc,
        "marker_data": marker_data,
        "persistence_verified": bool(ok_marker and ok_pers and ok_doc),
    }


def perform_install_and_stage_test_agent(edition, port_fd, port_file, sess, install_mode="guided", luks_pass=None):
    disk_inst = shutil.which("nexus-disk-install") or "/usr/local/bin/nexus-disk-install"
    if not Path(disk_inst).is_file():
        return {"install_success": False, "reason": "nexus-disk-install_missing"}

    # Generate ephemeral runtime password (never hardcoded or logged)
    pw_file = Path("/tmp/.nexus-ephemeral-install-pw")
    pw_file.write_text(secrets.token_urlsafe(18) + "\n", encoding="utf-8")
    os.chmod(pw_file, 0o600)

    extra_diag = {"install_mode": install_mode}
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

    luks_pw_file = None
    if install_mode == "manual":
        # Create custom 3-partition GPT layout: vda1=512M ESP, vda2=14G root, vda3=extra data partition
        subprocess.run(["wipefs", "-af", "/dev/vda"], capture_output=True, check=False)
        subprocess.run(["parted", "-s", "/dev/vda", "mklabel", "gpt"], check=True)
        subprocess.run(["parted", "-s", "/dev/vda", "mkpart", "ESP", "fat32", "1MiB", "513MiB"], check=True)
        subprocess.run(["parted", "-s", "/dev/vda", "set", "1", "esp", "on"], check=True)
        subprocess.run(["parted", "-s", "/dev/vda", "mkpart", "root", "ext4", "513MiB", "14849MiB"], check=True)
        subprocess.run(["parted", "-s", "/dev/vda", "mkpart", "nexus_data", "ext4", "14849MiB", "100%"], check=True)
        subprocess.run(["partprobe", "/dev/vda"], capture_output=True, check=False)
        subprocess.run(["udevadm", "settle"], capture_output=True, check=False)
        subprocess.run(["mkfs.ext4", "-F", "-L", "nexus_data", "/dev/vda3"], capture_output=True, check=True)
        dmnt = Path("/mnt/nexus-data-prep")
        dmnt.mkdir(parents=True, exist_ok=True)
        subprocess.run(["mount", "/dev/vda3", str(dmnt)], check=True)
        (dmnt / "preserve-check.txt").write_text("manual-partition-preserved\n", encoding="utf-8")
        subprocess.run(["umount", str(dmnt)], check=True)
        cmd.extend(["--efi-part", "/dev/vda1", "--root-part", "/dev/vda2"])
    elif install_mode == "recovery":
        # Simulate an interrupted/dirty prior installation + verify unconfirmed guard refuses
        refusal = subprocess.run(["bash", disk_inst, "--disk", "/dev/vda"], capture_output=True, text=True)
        extra_diag["refused_without_confirm"] = refusal.returncode != 0
        subprocess.run(["wipefs", "-af", "/dev/vda"], capture_output=True, check=False)
        subprocess.run(["parted", "-s", "/dev/vda", "mklabel", "gpt"], check=True)
        subprocess.run(["parted", "-s", "/dev/vda", "mkpart", "ESP", "fat32", "1MiB", "513MiB"], check=True)
        subprocess.run(["parted", "-s", "/dev/vda", "mkpart", "dirty", "ext4", "513MiB", "4096MiB"], check=True)
        subprocess.run(["partprobe", "/dev/vda"], capture_output=True, check=False)
        subprocess.run(["udevadm", "settle"], capture_output=True, check=False)
        subprocess.run(["mkfs.ext4", "-F", "/dev/vda2"], capture_output=True, check=True)
        dirty_mnt = Path("/mnt/nexus-install-target")
        dirty_mnt.mkdir(parents=True, exist_ok=True)
        subprocess.run(["mount", "/dev/vda2", str(dirty_mnt)], check=True)
        (dirty_mnt / "partial-failed.txt").write_text("interrupted-install-artifact\n", encoding="utf-8")
        extra_diag["dirty_mount_created"] = True
    elif install_mode == "dualboot":
        # Simulate an existing Windows/OS disk: vda1=512M ESP with Microsoft EFI stub, vda2=4G NTFS (or FAT32 fallback), vda3=15G+ target root
        try:
            subprocess.run(["wipefs", "-af", "/dev/vda"], capture_output=True, check=False)
            subprocess.run(["parted", "-s", "/dev/vda", "mklabel", "gpt"], check=True)
            subprocess.run(["parted", "-s", "/dev/vda", "mkpart", "ESP", "fat32", "1MiB", "513MiB"], check=True)
            subprocess.run(["parted", "-s", "/dev/vda", "set", "1", "esp", "on"], check=True)
            subprocess.run(["parted", "-s", "/dev/vda", "mkpart", "Windows", "ntfs", "513MiB", "4609MiB"], check=True)
            subprocess.run(["parted", "-s", "/dev/vda", "mkpart", "nexus_root", "ext4", "4609MiB", "100%"], check=True)
            subprocess.run(["partprobe", "/dev/vda"], capture_output=True, check=False)
            subprocess.run(["udevadm", "settle"], capture_output=True, check=False)
            subprocess.run(["mkfs.vfat", "-F", "32", "-n", "ESP", "/dev/vda1"], capture_output=True, check=True)
            emnt = Path("/mnt/nexus-esp-prep")
            emnt.mkdir(parents=True, exist_ok=True)
            subprocess.run(["mount", "/dev/vda1", str(emnt)], check=True)
            (emnt / "EFI/Microsoft/Boot").mkdir(parents=True, exist_ok=True)
            (emnt / "EFI/Microsoft/Boot/bootmgfw.efi").write_text("SIMULATED_WINDOWS_BOOTMGR\n", encoding="utf-8")
            subprocess.run(["umount", str(emnt)], check=True)
            if shutil.which("mkfs.ntfs"):
                subprocess.run(["mkfs.ntfs", "-Q", "-F", "-L", "Windows", "/dev/vda2"], capture_output=True, check=True)
                extra_diag["simulated_os_fs"] = "ntfs"
            else:
                subprocess.run(["mkfs.vfat", "-F", "32", "-n", "WINOS", "/dev/vda2"], capture_output=True, check=True)
                extra_diag["simulated_os_fs"] = "vfat_fallback"
            subprocess.run(["udevadm", "settle"], capture_output=True, check=False)
            wmnt = Path("/mnt/nexus-win-prep")
            wmnt.mkdir(parents=True, exist_ok=True)
            mounted_win = False
            for m_cmd in (["mount", "/dev/vda2", str(wmnt)], ["mount", "-t", "ntfs-3g", "/dev/vda2", str(wmnt)], ["mount", "-t", "ntfs3", "/dev/vda2", str(wmnt)]):
                if subprocess.run(m_cmd, capture_output=True).returncode == 0:
                    mounted_win = True
                    break
            if not mounted_win:
                raise RuntimeError("Failed to mount simulated /dev/vda2 OS partition")
            (wmnt / "Windows/System32").mkdir(parents=True, exist_ok=True)
            (wmnt / "Windows/System32/winload.efi").write_text("SIMULATED_WINLOAD\n", encoding="utf-8")
            (wmnt / "dualboot-ntfs-marker.txt").write_text("windows-os-preserved\n", encoding="utf-8")
            subprocess.run(["umount", str(wmnt)], check=True)
            subprocess.run(["udevadm", "settle"], capture_output=True, check=False)
        except Exception as exc:
            pw_file.unlink(missing_ok=True)
            return {"install_success": False, "install_mode": install_mode, "reason": f"dualboot_prep_error: {exc}", **extra_diag}
        # Verify nexus-install-preflight detects simulated dual-boot layout before installing
        if shutil.which("nexus-install-preflight"):
            pf_res = subprocess.run(["nexus-install-preflight", "--json"], capture_output=True, text=True, timeout=20)
            if pf_res.returncode == 0 and pf_res.stdout.strip():
                try:
                    pf_data = json.loads(pf_res.stdout)
                    extra_diag["dualboot_preflight_detected"] = (pf_data.get("dual_boot_detection") or {}).get("dual_boot_candidates_detected")
                    extra_diag["dualboot_ntfs_count"] = len((pf_data.get("dual_boot_detection") or {}).get("ntfs_partitions", []))
                    extra_diag["dualboot_esp_count"] = len((pf_data.get("dual_boot_detection") or {}).get("esp_partitions", []))
                except Exception:
                    pass
        cmd.extend(["--efi-part", "/dev/vda1", "--root-part", "/dev/vda3", "--keep-efi"])
    elif install_mode == "luks":
        if not luks_pass:
            pw_file.unlink(missing_ok=True)
            return {"install_success": False, "reason": "missing_ephemeral_luks_passphrase"}
        luks_pw_file = Path("/tmp/.nexus-ephemeral-luks-pw")
        luks_pw_file.write_text(luks_pass, encoding="utf-8")
        os.chmod(luks_pw_file, 0o600)
        cmd.extend(["--luks", "--luks-passphrase-file", str(luks_pw_file)])

    t0 = time.time()
    res = subprocess.run(cmd, capture_output=True, text=True, timeout=2400)
    pw_file.unlink(missing_ok=True)
    if luks_pw_file is not None and install_mode != "luks":
        luks_pw_file.unlink(missing_ok=True)
    elapsed = round(time.time() - t0, 1)

    if res.returncode != 0:
        if luks_pw_file is not None:
            luks_pw_file.unlink(missing_ok=True)
        return {
            "install_success": False,
            "install_method": "nexus-disk-install",
            "install_mode": install_mode,
            "elapsed_sec": elapsed,
            "returncode": res.returncode,
            "stderr_tail": res.stderr.splitlines()[-15:],
            "stdout_tail": res.stdout.splitlines()[-15:],
        }

    # Verify target disk partitions, EFI bootloader, kernel, initrd, and stage test-only hook on disposable target
    parted_out = subprocess.run(["parted", "-s", "/dev/vda", "print"], capture_output=True, text=True).stdout
    blkid_out = subprocess.run(["blkid", "/dev/vda1", "/dev/vda2"] + (["/dev/vda3"] if Path("/dev/vda3").exists() else []), capture_output=True, text=True).stdout

    mnt = Path("/mnt/nexus-verify-target")
    mnt.mkdir(parents=True, exist_ok=True)
    crypt_opened_here = False
    if install_mode == "luks":
        subprocess.run(
            ["cryptsetup", "luksOpen", "--key-file", "-", "/dev/vda3", "nexus_crypt"],
            input=luks_pass.rstrip("\r\n").encode("utf-8"),
            check=True,
        )
        luks_pw_file.unlink(missing_ok=True)
        crypt_opened_here = True
        subprocess.run(["mount", "/dev/mapper/nexus_crypt", str(mnt)], check=True)
        subprocess.run(["mount", "/dev/vda2", str(mnt / "boot")], check=True)
    elif install_mode == "dualboot":
        subprocess.run(["mount", "/dev/vda3", str(mnt)], check=True)
    else:
        subprocess.run(["mount", "/dev/vda2", str(mnt)], check=True)
    subprocess.run(["mount", "/dev/vda1", str(mnt / "boot" / "efi")], check=True)
    try:
        efi_ok = (mnt / "boot/efi/EFI/BOOT/BOOTX64.EFI").is_file()
        grub_cfg_ok = (mnt / "boot/grub/grub.cfg").is_file()
        vmlinuz_ok = any((mnt / "boot").glob("vmlinuz-*"))
        initrd_ok = any((mnt / "boot").glob("initrd.img-*"))
        meta_ok = (mnt / "etc/nexus-installed.json").is_file()
        efi_dir_files = sorted(str(p.relative_to(mnt / "boot/efi")) for p in (mnt / "boot/efi").rglob("*") if p.is_file())
        if install_mode == "luks":
            extra_diag["crypttab_ok"] = (mnt / "etc/crypttab").is_file()
            extra_diag["luks_recovery_guide_ok"] = (mnt / "usr/local/share/nexus-os/luks-recovery-guide.txt").is_file()
            extra_diag["crypto_luks_blkid"] = (
                "crypto_LUKS" in blkid_out
                or subprocess.run(["cryptsetup", "isLuks", "/dev/vda3"], capture_output=True).returncode == 0
            )
        if install_mode == "manual":
            dmnt = Path("/mnt/nexus-data-verify")
            dmnt.mkdir(parents=True, exist_ok=True)
            subprocess.run(["mount", "/dev/vda3", str(dmnt)], check=True)
            extra_diag["manual_extra_part_preserved"] = (dmnt / "preserve-check.txt").is_file()
            subprocess.run(["umount", str(dmnt)], check=True)
        if install_mode == "dualboot":
            extra_diag["dualboot_efi_preserved"] = (mnt / "boot/efi/EFI/Microsoft/Boot/bootmgfw.efi").is_file()
            wmnt = Path("/mnt/nexus-win-verify")
            wmnt.mkdir(parents=True, exist_ok=True)
            for m_cmd in (["mount", "-o", "ro", "/dev/vda2", str(wmnt)], ["mount", "-t", "ntfs-3g", "-o", "ro", "/dev/vda2", str(wmnt)], ["mount", "-t", "ntfs3", "-o", "ro", "/dev/vda2", str(wmnt)]):
                if subprocess.run(m_cmd, capture_output=True).returncode == 0:
                    extra_diag["dualboot_os_part_preserved"] = (wmnt / "dualboot-ntfs-marker.txt").is_file() and (wmnt / "Windows/System32/winload.efi").is_file()
                    subprocess.run(["umount", str(wmnt)], capture_output=True)
                    break

        # Enable ttyS0 serial console inside disposable test disk grub.cfg for CI diagnostics
        grub_def = mnt / "etc/default/grub"
        if grub_def.is_file():
            gtxt = grub_def.read_text(encoding="utf-8", errors="replace")
            if install_mode == "luks":
                gtxt = gtxt.replace("quiet splash", "")
            if "console=ttyS0" not in gtxt:
                gtxt += '\nGRUB_CMDLINE_LINUX="$GRUB_CMDLINE_LINUX console=tty1 console=ttyS0,115200"\n'
            if install_mode == "luks" or "console=ttyS0" in gtxt:
                grub_def.write_text(gtxt, encoding="utf-8")
                for mp in ("dev", "proc", "sys"):
                    subprocess.run(["mount", "--bind", f"/{mp}", str(mnt / mp)], check=False)
                subprocess.run(["chroot", str(mnt), "/usr/sbin/update-grub"], capture_output=True, check=False)
                for mp in ("dev", "proc", "sys"):
                    subprocess.run(["umount", "-lf", str(mnt / mp)], check=False)

        # Install ephemeral virtio-serial agent ONLY onto disposable QEMU test disk
        test_dir = mnt / "usr/local/libexec/nexus-test"
        test_dir.mkdir(parents=True, exist_ok=True)
        for fn in ("guest-mem-probe.sh", "test-zram-pressure.sh", "nexus-guest-test.py", "nexus-browser-bench.py"):
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
        if install_mode == "luks":
            subprocess.run(["umount", str(mnt / "boot")], check=False)
        subprocess.run(["umount", str(mnt)], check=False)
        if crypt_opened_here:
            subprocess.run(["cryptsetup", "luksClose", "nexus_crypt"], check=False)

    return {
        "install_success": bool(efi_ok and grub_cfg_ok and vmlinuz_ok and initrd_ok and meta_ok),
        "install_method": "nexus-disk-install",
        **extra_diag,
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
    install_mode = str(cfg.get("install_mode", "guided"))
    luks_pass = cfg.get("luks_passphrase")
    install_browsers = bool(cfg.get("install_browsers", False))
    browser_bench = bool(cfg.get("browser_bench", False))
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
    disable_screen_blanking(sess, edition)

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
    disable_screen_blanking(sess, edition)
    time.sleep(0.5)
    send_event(port_fd, "desktop_ready", desktop_info)
    wait_for_cmd(port_file, "ack", timeout=15)

    stages["2_post_session_init"] = run_probe("post_session_init")
    send_event(port_fd, "stage_mem", stages["2_post_session_init"])

    time.sleep(max(1, idle_seconds))
    disable_screen_blanking(sess, edition)
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
    zram_status = "{}"
    if shutil.which("nexus-configure-zram"):
        try:
            zram_status = subprocess.run(["nexus-configure-zram", "status"], capture_output=True, text=True, timeout=10).stdout
        except Exception:
            pass
    zram_pressure = {"skipped": True}
    if Path("/sys/block/zram0").exists() and Path(ZRAM_SH).is_file():
        total_mib = stages["1_post_login"].get("ram_total_mib", 512)
        p_mb = "64" if total_mib < 700 else "96"
        try:
            zres = subprocess.run(["bash", ZRAM_SH, "--pressure-mb", p_mb], capture_output=True, text=True, timeout=60)
            try:
                zram_pressure = json.loads(zres.stdout)
            except Exception:
                zram_pressure = {"returncode": zres.returncode, "stdout": zres.stdout, "stderr": zres.stderr}
            zram_pressure["post_recovery_mem"] = run_probe("post_zram_recovery")
        except Exception as exc:
            zram_pressure = {"error": str(exc)}

    # Preflight & storage detection
    preflight = {}
    if shutil.which("nexus-install-preflight"):
        try:
            pres = subprocess.run(["nexus-install-preflight", "--json"], capture_output=True, text=True, timeout=20)
            try:
                preflight = json.loads(pres.stdout)
            except Exception:
                preflight = {"raw": pres.stdout}
        except Exception as exc:
            preflight = {"error": str(exc)}
    lsblk_out = ""
    try:
        lsblk_out = subprocess.run(["lsblk", "-J", "-o", "NAME,SIZE,TYPE,TRAN"], capture_output=True, text=True, timeout=10).stdout
    except Exception:
        pass
    ubiquity_present = bool(shutil.which("ubiquity"))

    # Hardware inventory & security audit summaries inside booted guest (if tools installed)
    hw_summary = {}
    if shutil.which("nexus-hw-inventory"):
        try:
            hres = subprocess.run(["nexus-hw-inventory", "--json"], capture_output=True, text=True, timeout=20)
            if hres.returncode == 0 and hres.stdout.strip():
                hd = json.loads(hres.stdout)
                hw_summary = {
                    "firmware": hd.get("firmware", {}).get("mode"),
                    "secure_boot": hd.get("firmware", {}).get("secure_boot"),
                    "secure_boot_chain": hd.get("secure_boot_chain", {}),
                    "graphics_qualification": hd.get("graphics_qualification", {}),
                    "gpus": [(g.get("driver"), (g.get("classification") or {}).get("status")) for g in hd.get("gpus", [])],
                    "storage": [(s.get("device"), s.get("driver"), (s.get("classification") or {}).get("status")) for s in hd.get("storage", [])],
                    "missing_fw_count": len(hd.get("firmware", {}).get("missing_firmware_hints", [])),
                }
        except Exception:
            pass
    sec_summary = {}
    if shutil.which("nexus-security-audit"):
        try:
            sres = subprocess.run(["nexus-security-audit", "--json"], capture_output=True, text=True, timeout=20)
            if sres.returncode == 0 and sres.stdout.strip():
                sd = json.loads(sres.stdout)
                sec_summary = sd.get("summary") or {}
        except Exception:
            pass

    update_status = {
        "auto_upgrades_conf": Path("/etc/apt/apt.conf.d/20auto-upgrades").is_file(),
        "unattended_upgrades_installed": shutil.which("unattended-upgrade") is not None,
        "dpkg_audit_ok": False,
        "apt_check_ok": False,
    }
    if shutil.which("dpkg"):
        try:
            dres = subprocess.run(["dpkg", "--audit"], capture_output=True, text=True, timeout=15)
            update_status["dpkg_audit_ok"] = dres.returncode == 0 and not dres.stdout.strip()
        except Exception as exc:
            update_status["dpkg_audit_error"] = str(exc)
    if shutil.which("apt-cache"):
        try:
            ares = subprocess.run(["apt-cache", "stats"], capture_output=True, text=True, timeout=15)
            update_status["apt_check_ok"] = ares.returncode == 0
        except Exception as exc:
            update_status["apt_check_error"] = str(exc)

    recovery_diag = {}
    if shutil.which("nexus-recovery"):
        try:
            rres = subprocess.run(["nexus-recovery", "--diagnose", "--json", "--redacted"], capture_output=True, text=True, timeout=15)
            if rres.returncode == 0 and rres.stdout.strip():
                recovery_diag = json.loads(rres.stdout)
        except Exception as exc:
            recovery_diag = {"error": str(exc)}

    native_services = {}
    if not browser_bench:
        try:
            native_services = check_native_services(sess, edition)
        except Exception as exc:
            native_services = {"error": str(exc)}

    # Live-mode Ubiquity UI check (launch + multi-screen navigation) & actual disk installation
    ubiquity_ui = {
        "checked": False,
        "installer_launch_verified": False,
        "individual_screens_verified": False,
        "complete_gui_install_verified": False,
        "installed_boot_verified": False,
        "qualification_tier": "not_checked",
        "screens_observed": [],
    }
    install_report = {"executed": False}
    if mode == "live":
        if check_ubiquity_ui and ubiquity_present and stages["1_post_login"].get("ram_total_mib", 0) >= 850:
            if shutil.which("xhost"):
                subprocess.run(["xhost", "+si:localuser:root"], env=x_env(sess), capture_output=True, text=True)
            before_ub = set(x11_windows(sess))
            ub_env = x_env(sess)
            dbg_path = Path("/var/log/installer/debug")
            prev_dbg_len = dbg_path.stat().st_size if dbg_path.is_file() else 0
            ub_proc = subprocess.Popen(
                ["ubiquity", "--debug", "gtk_ui"],
                env=ub_env,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                start_new_session=True,
            )
            ub_wins = []
            for _ in range(50):
                time.sleep(0.5)
                after_ub = x11_windows(sess)
                new_ub = [w for w in after_ub if w not in before_ub]
                ub_wins = [w for w in new_ub if any(k in w.lower() for k in ("ubiquity", "install"))]
                if ub_wins:
                    break

            def read_ub_steps():
                if not dbg_path.is_file():
                    return []
                try:
                    raw = dbg_path.read_text(encoding="utf-8", errors="replace")[prev_dbg_len:]
                except OSError:
                    return []
                found = []
                for line in raw.splitlines():
                    if "Step_before" in line or "Step_after" in line or "step " in line.lower() or "ubi-" in line:
                        for token in line.replace("(", " ").replace(")", " ").replace(",", " ").split():
                            if token.startswith("ubi-") or token in ("stepLanguage", "stepKeyboardConf", "stepPrepare", "stepPartAuto", "stepPartAdvanced", "stepLocation", "stepUserInfo"):
                                if token not in found:
                                    found.append(token)
                return found

            screens_observed = []
            launch_ok = ub_proc.poll() is None and len(ub_wins) > 0
            if launch_ok:
                try:
                    time.sleep(1.5)
                    screens_observed = read_ub_steps() or ["initial_screen"]
                    send_event(port_fd, "ubiquity_step", {"step": "01_language", "steps": screens_observed})
                    wait_for_cmd(port_file, "ack", timeout=15)

                    # Attempt keyboard navigation across up to 3 subsequent screens (Language -> Keyboard -> Prepare -> Install Type)
                    for idx, step_label in enumerate(("02_keyboard", "03_prepare", "04_partman"), start=2):
                        if ub_proc.poll() is not None:
                            break
                        prev_count = len(screens_observed)
                        send_event(port_fd, "qmp_send_key", {"keys": ["ret"]})
                        wait_for_cmd(port_file, "ack", timeout=15)
                        for _ in range(12):
                            time.sleep(0.5)
                            cur_steps = read_ub_steps()
                            if len(cur_steps) > prev_count:
                                screens_observed = cur_steps
                                break
                        send_event(port_fd, "ubiquity_step", {"step": step_label, "steps": screens_observed})
                        wait_for_cmd(port_file, "ack", timeout=15)
                except Exception:
                    pass

            screens_verified = launch_ok and len(screens_observed) >= 2
            ubiquity_ui = {
                "checked": True,
                "launched": ub_proc.poll() is None,
                "window_verified": len(ub_wins) > 0,
                "installer_launch_verified": launch_ok,
                "individual_screens_verified": screens_verified,
                "complete_gui_install_verified": False,
                "installed_boot_verified": False,
                "qualification_tier": "screens_navigated" if screens_verified else ("launch_only" if launch_ok else "failed"),
                "screens_observed": screens_observed[:10],
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
                "native_services": native_services,
                "lsblk_vda_present": '"vda"' in lsblk_out,
            })
            install_report = perform_install_and_stage_test_agent(
                edition, port_fd, port_file, sess,
                install_mode=install_mode,
                luks_pass=luks_pass,
            )
            install_report["executed"] = True
            send_event(port_fd, "install_done", install_report)

    installed_checks = {}
    persistence = {}
    browser_bench_result = {}
    if mode == "installed":
        root_src = subprocess.run(["findmnt", "-n", "-o", "SOURCE", "/"], capture_output=True, text=True).stdout.strip()
        failed_units = subprocess.run(["systemctl", "--failed", "--no-legend"], capture_output=True, text=True).stdout.strip().splitlines()
        err_lines = subprocess.run(["journalctl", "-p", "err", "-b", "--no-pager", "-q"], capture_output=True, text=True).stdout.strip().splitlines()
        luks_active = root_src.startswith("/dev/mapper/nexus_crypt")
        luks_guide = Path("/usr/local/share/nexus-os/luks-recovery-guide.txt").is_file()
        crypttab_ok = Path("/etc/crypttab").is_file()
        extra_part_preserved = False
        if Path("/dev/vda3").exists() and not luks_active and root_src != "/dev/vda3":
            dmnt = Path("/mnt/nexus-extra-check")
            dmnt.mkdir(parents=True, exist_ok=True)
            if subprocess.run(["mount", "-o", "ro", "/dev/vda3", str(dmnt)], capture_output=True).returncode == 0:
                extra_part_preserved = (dmnt / "preserve-check.txt").is_file()
                subprocess.run(["umount", str(dmnt)], capture_output=True)
        dualboot_efi_preserved = Path("/boot/efi/EFI/Microsoft/Boot/bootmgfw.efi").is_file()
        dualboot_os_part_preserved = False
        if root_src == "/dev/vda3" and Path("/dev/vda2").exists():
            wmnt = Path("/mnt/nexus-win-check")
            wmnt.mkdir(parents=True, exist_ok=True)
            for m_cmd in (["mount", "-o", "ro", "/dev/vda2", str(wmnt)], ["mount", "-t", "ntfs-3g", "-o", "ro", "/dev/vda2", str(wmnt)], ["mount", "-t", "ntfs3", "-o", "ro", "/dev/vda2", str(wmnt)]):
                if subprocess.run(m_cmd, capture_output=True).returncode == 0:
                    dualboot_os_part_preserved = (wmnt / "dualboot-ntfs-marker.txt").is_file() and (wmnt / "Windows/System32/winload.efi").is_file()
                    subprocess.run(["umount", str(wmnt)], capture_output=True)
                    break
        user_failed_units = []
        try:
            uf = run_as_user_capture(sess, ["systemctl", "--user", "--failed", "--no-legend"], timeout=5)
            user_failed_units = [ln.strip() for ln in uf.stdout.splitlines() if ln.strip()]
        except Exception:
            pass
        installed_checks = {
            "root_source": root_src,
            "booted_from_vda": root_src.startswith("/dev/vda") or luks_active,
            "booted_from_luks": luks_active,
            "crypttab_present": crypttab_ok,
            "luks_recovery_guide_present": luks_guide,
            "extra_partition_preserved": extra_part_preserved,
            "dualboot_efi_preserved": dualboot_efi_preserved,
            "dualboot_os_part_preserved": dualboot_os_part_preserved,
            "live_iso_absent": not Path("/rofs").exists() and not Path("/cdrom/casper/filesystem.squashfs").exists(),
            "efi_boot_ok": Path("/boot/efi/EFI/BOOT/BOOTX64.EFI").is_file(),
            "grub_cfg_ok": Path("/boot/grub/grub.cfg").is_file(),
            "installed_meta_ok": Path("/etc/nexus-installed.json").is_file(),
            "mint_user_absent": not Path("/home/mint").exists(),
            "nexus_firstboot_bin": bool(shutil.which("nexus-firstboot")),
            "nexus_firstboot_autostart": Path("/etc/xdg/autostart/nexus-firstboot.desktop").is_file(),
            "hw_summary": hw_summary,
            "sec_summary": sec_summary,
            "failed_systemd_units": len(failed_units),
            "systemd_user_failed_units": len(user_failed_units),
            "systemd_user_failed_sample": user_failed_units[:5],
            "journal_err_count": len(err_lines),
            "journal_err_sample": err_lines[:8],
        }
        persistence = verify_persistence(sess, boot_num, edition)

        if install_browsers and boot_num == 1:
            subprocess.run(["apt-get", "update"], capture_output=True, text=True, timeout=300)
            bres = subprocess.run(
                ["apt-get", "install", "-y", "--no-install-recommends", "falkon", "firefox"],
                capture_output=True, text=True, timeout=600,
            )
            installed_checks["browsers_installed_rc"] = bres.returncode
            installed_checks["falkon_bin"] = bool(shutil.which("falkon"))
            installed_checks["firefox_bin"] = bool(shutil.which("firefox"))

        if browser_bench:
            bench_path = Path("/usr/local/libexec/nexus-test/nexus-browser-bench.py")
            if bench_path.is_file():
                import importlib.util
                spec = importlib.util.spec_from_file_location("nexus_browser_bench", str(bench_path))
                bmod = importlib.util.module_from_spec(spec)
                spec.loader.exec_module(bmod)
                browser_bench_result = bmod.run_browser_suite(
                    sess, port_fd, port_file,
                    send_event=send_event,
                    wait_for_cmd=wait_for_cmd,
                )
            else:
                browser_bench_result = {"error": "nexus-browser-bench.py missing"}

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
        "browser_bench": browser_bench_result,
        "hw_summary": hw_summary,
        "sec_summary": sec_summary,
        "update_status": update_status,
        "recovery_diag": recovery_diag,
        "native_services": native_services,
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
