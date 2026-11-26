#!/usr/bin/env python3
"""Test-only repeatable browser benchmark for NEXUS OS (Falkon vs Firefox).
Spins up a local deterministic HTTP fixture server and measures startup time,
page load latency, RAM/RSS, CPU, ZRAM/swap activity, OOM/crashes, and post-close
memory recovery across 1, 2, 4, and 6 tabs.
"""
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import os
from pathlib import Path
import pwd
import shutil
import signal
import subprocess
import sys
import threading
import time
import urllib.parse

PAGES = {
    "/page1.html": """<!doctype html><html><head><meta charset="utf-8"><title>NEXUS Docs Bench</title>
<style>body{font-family:sans-serif;background:#0f141c;color:#e6edf3;margin:2rem;line-height:1.6}
.grid{display:grid;grid-template-columns:repeat(3,1fr);gap:1rem}.card{background:#18202c;padding:1rem;border-radius:8px}</style>
</head><body><h1>NEXUS Documentation Workload</h1><div class="grid">""" + "".join(
        f"<div class='card'><h3>Section {i}</h3><p>Benchmark paragraph content for DOM layout measurement ({i}).</p></div>"
        for i in range(1, 31)
    ) + """</div><script>
window.addEventListener('load',()=>{const t=Math.round(performance.now());
fetch('/beacon?page=page1&load_ms='+t).catch(()=>{});});</script></body></html>""",

    "/page2.html": """<!doctype html><html><head><meta charset="utf-8"><title>NEXUS News Grid Bench</title>
<style>body{font-family:sans-serif;background:#121820;color:#d8e1ea;margin:1.5rem}
article{border-bottom:1px solid #2b3648;padding:0.75rem 0}</style></head><body><h1>News Layout Workload</h1>""" + "".join(
        f"<article><h2>Headline {i}</h2><p>Repeatable CSS flex and text reflow workload item #{i}.</p></article>"
        for i in range(1, 45)
    ) + """<script>
window.addEventListener('load',()=>{const t=Math.round(performance.now());
fetch('/beacon?page=page2&load_ms='+t).catch(()=>{});});</script></body></html>""",

    "/page3.html": """<!doctype html><html><head><meta charset="utf-8"><title>NEXUS JS Dashboard Bench</title>
<style>body{font-family:monospace;background:#0b1017;color:#8be9fd;margin:1.5rem}
table{width:100%;border-collapse:collapse}td,th{border:1px solid #243042;padding:4px 8px}</style></head>
<body><h1>JavaScript Compute & Table Workload</h1><table id="tbl"></table><script>
const tbl=document.getElementById('tbl');let acc=0;
for(let r=0;r<120;r++){acc+=Math.sqrt(r*17+3);const tr=document.createElement('tr');
tr.innerHTML='<td>Row '+r+'</td><td>'+acc.toFixed(3)+'</td><td>OK</td>';tbl.appendChild(tr);}
window.addEventListener('load',()=>{const t=Math.round(performance.now());
fetch('/beacon?page=page3&load_ms='+t).catch(()=>{});});</script></body></html>""",

    "/page4.html": """<!doctype html><html><head><meta charset="utf-8"><title>NEXUS Canvas SVG Bench</title>
<style>body{background:#10151d;color:#f0f4f8;font-family:sans-serif;margin:1.5rem}</style></head>
<body><h1>Vector & Canvas Rendering Workload</h1>
<svg width="640" height="200">""" + "".join(
        f"<rect x='{(i*18)%600}' y='{(i*11)%160}' width='28' height='28' rx='4' fill='hsl({(i*15)%360},65%,55%)' opacity='0.8'/>"
        for i in range(40)
    ) + """</svg><canvas id="cv" width="640" height="180"></canvas><script>
const ctx=document.getElementById('cv').getContext('2d');
for(let i=0;i<200;i++){ctx.fillStyle='rgba(78,205,196,0.25)';ctx.fillRect((i*13)%610,(i*7)%150,24,24);}
window.addEventListener('load',()=>{const t=Math.round(performance.now());
fetch('/beacon?page=page4&load_ms='+t).catch(()=>{});});</script></body></html>""",
}


class BenchHTTPServer:
    def __init__(self):
        self.events = []
        self.lock = threading.Lock()
        parent = self

        class Handler(BaseHTTPRequestHandler):
            def do_GET(self):
                parsed = urllib.parse.urlparse(self.path)
                if parsed.path == "/beacon":
                    qs = urllib.parse.parse_qs(parsed.query)
                    with parent.lock:
                        parent.events.append({
                            "ts": time.time(),
                            "page": (qs.get("page") or ["unknown"])[0],
                            "load_ms": int((qs.get("load_ms") or ["0"])[0]) if (qs.get("load_ms") or ["0"])[0].isdigit() else None,
                        })
                    self.send_response(204)
                    self.end_headers()
                    return
                body = PAGES.get(parsed.path, PAGES["/page1.html"]).encode("utf-8")
                self.send_response(200)
                self.send_header("Content-Type", "text/html; charset=utf-8")
                self.send_header("Content-Length", str(len(body)))
                self.end_headers()
                self.wfile.write(body)

            def log_message(self, format, *args):
                return

        self.srv = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        self.port = self.srv.server_address[1]
        self.thread = threading.Thread(target=self.srv.serve_forever, daemon=True)
        self.thread.start()

    def count(self):
        with self.lock:
            return len(self.events)

    def recent_loads(self, start_idx):
        with self.lock:
            return [e for e in self.events[start_idx:] if e.get("load_ms") is not None]

    def stop(self):
        self.srv.shutdown()
        self.srv.server_close()


def read_mem_snapshot(browser_names):
    info = {}
    for line in Path("/proc/meminfo").read_text(encoding="utf-8", errors="replace").splitlines():
        parts = line.split()
        if len(parts) >= 2 and parts[1].isdigit():
            info[parts[0].rstrip(":")] = int(parts[1])
    total = round(info.get("MemTotal", 0) / 1024.0, 1)
    avail = round(info.get("MemAvailable", 0) / 1024.0, 1)
    used = round(total - avail, 1)
    swap_total = round(info.get("SwapTotal", 0) / 1024.0, 1)
    swap_free = round(info.get("SwapFree", 0) / 1024.0, 1)
    swap_used = round(swap_total - swap_free, 1)

    oom_kills = 0
    vmstat = Path("/proc/vmstat")
    if vmstat.is_file():
        for line in vmstat.read_text(encoding="utf-8", errors="replace").splitlines():
            if line.startswith("oom_kill "):
                oom_kills = int(line.split()[1])

    zram_ratio = None
    mm_stat = Path("/sys/block/zram0/mm_stat")
    if mm_stat.is_file():
        cols = mm_stat.read_text(encoding="utf-8", errors="replace").split()
        if len(cols) >= 2 and int(cols[1]) > 0:
            zram_ratio = round(int(cols[0]) / int(cols[1]), 2)

    rss_kb = 0
    proc_count = 0
    for pd in Path("/proc").iterdir():
        if not pd.name.isdigit():
            continue
        try:
            comm = (pd / "comm").read_text(encoding="utf-8", errors="replace").strip().lower()
            if any(b in comm for b in browser_names):
                proc_count += 1
                st = (pd / "status").read_text(encoding="utf-8", errors="replace")
                for ln in st.splitlines():
                    if ln.startswith("VmRSS:"):
                        rss_kb += int(ln.split()[1])
                        break
        except Exception:
            continue

    # Short 1-second CPU busy sample
    def stat_cpu():
        vals = [int(x) for x in Path("/proc/stat").read_text().splitlines()[0].split()[1:8]]
        return sum(vals), vals[3] + vals[4]

    t1, i1 = stat_cpu()
    time.sleep(1.0)
    t2, i2 = stat_cpu()
    dt = max(1, t2 - t1)
    cpu_pct = round(((dt - (i2 - i1)) / dt) * 100.0, 1)

    return {
        "ram_total_mib": total,
        "ram_used_mib": used,
        "ram_avail_mib": avail,
        "swap_used_mib": swap_used,
        "zram_ratio": zram_ratio,
        "browser_rss_mib": round(rss_kb / 1024.0, 1),
        "browser_procs": proc_count,
        "cpu_pct": cpu_pct,
        "oom_kills": oom_kills,
    }


def x_env(sess):
    env = dict(os.environ)
    env["DISPLAY"] = sess["display"]
    env["XAUTHORITY"] = sess["xauthority"]
    if sess.get("dbus"):
        env["DBUS_SESSION_BUS_ADDRESS"] = sess["dbus"]
    return env


def run_as_user(sess, cmd):
    def preexec():
        pw = pwd.getpwuid(sess["uid"])
        os.setgid(pw.pw_gid)
        os.setuid(pw.pw_uid)

    return subprocess.Popen(
        cmd,
        env=x_env(sess),
        preexec_fn=preexec,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
    )


def x11_windows(sess):
    if not shutil.which("xwininfo"):
        return []
    res = subprocess.run(["xwininfo", "-root", "-tree"], env=x_env(sess), capture_output=True, text=True, timeout=10)
    return [l.strip() for l in res.stdout.splitlines() if l.strip().startswith("0x") and '"' in l]


def kill_browser(proc_names, main_procs):
    for p in main_procs:
        if p.poll() is None:
            try:
                os.killpg(os.getpgid(p.pid), signal.SIGTERM)
            except Exception:
                pass
    time.sleep(3)
    for name in proc_names:
        subprocess.run(["pkill", "-TERM", "-f", name], capture_output=True)
    time.sleep(2)
    for name in proc_names:
        subprocess.run(["pkill", "-KILL", "-f", name], capture_output=True)


def run_browser_suite(sess, port_fd=None, port_file=None):
    srv = BenchHTTPServer()
    base = f"http://127.0.0.1:{srv.port}"
    urls = [f"{base}/page1.html", f"{base}/page2.html", f"{base}/page3.html", f"{base}/page4.html"]

    candidates = [
        ("falkon", "falkon", ["falkon"], lambda u, first: ["falkon", "--no-remote", u] if first else ["falkon", "--new-tab", u]),
        ("firefox", "firefox", ["firefox", "isolated", "web content"], lambda u, first: ["firefox", "--new-instance", u] if first else ["firefox", "--new-tab", u]),
    ]
    results = {}

    try:
        for bname, bin_name, proc_keys, cmd_fn in candidates:
            if not shutil.which(bin_name):
                results[bname] = {"available": False, "reason": f"{bin_name}_not_installed"}
                continue

            # Clean profile dir per run for repeatability
            prof_dir = Path(sess["home"]) / f".nexus-bench-{bname}"
            shutil.rmtree(prof_dir, ignore_errors=True)
            prof_dir.mkdir(parents=True, exist_ok=True)
            pw = pwd.getpwuid(sess["uid"])
            os.chown(prof_dir, pw.pw_uid, pw.pw_gid)

            def build_cmd(url, first):
                if bname == "firefox":
                    if first:
                        return ["firefox", "--no-remote", "--profile", str(prof_dir), url]
                    return ["firefox", "--profile", str(prof_dir), "--new-tab", url]
                if first:
                    return ["falkon", "--profile", f"nexus-bench-{bname}", "--new-window", url]
                return ["falkon", "--profile", f"nexus-bench-{bname}", "--new-tab", url]

            baseline = read_mem_snapshot(proc_keys)
            oom_start = baseline["oom_kills"]
            before_wins = set(x11_windows(sess))
            ev_idx = srv.count()

            t0 = time.time()
            procs = []
            p1 = run_as_user(sess, build_cmd(urls[0], True))
            procs.append(p1)

            win_mapped = False
            startup_sec = None
            deadline = t0 + 45
            while time.time() < deadline:
                new_wins = [w for w in x11_windows(sess) if w not in before_wins]
                if any(bname in w.lower() or "mozilla" in w.lower() or "nexus docs" in w.lower() for w in new_wins):
                    win_mapped = True
                    startup_sec = round(time.time() - t0, 2)
                    break
                if p1.poll() is not None and not win_mapped:
                    break
                time.sleep(0.5)

            # Wait for Tab 1 beacon
            b_deadline = time.time() + 30
            while time.time() < b_deadline and srv.count() == ev_idx:
                time.sleep(0.3)
            tab1_loads = srv.recent_loads(ev_idx)
            tab1_snap = read_mem_snapshot(proc_keys)
            crashes = 1 if (p1.poll() is not None and not tab1_snap["browser_procs"]) else 0

            tab_stages = {
                "tab_1": {
                    "snapshot": tab1_snap,
                    "beacon_received": len(tab1_loads) > 0,
                    "page_load_ms": tab1_loads[0]["load_ms"] if tab1_loads else None,
                }
            }

            stable_tabs = 1 if (tab1_snap["browser_procs"] > 0 and (win_mapped or len(tab1_loads) > 0)) else 0

            # Progressively open tabs up to 6
            for target_tabs in (2, 4, 6):
                cur_open = 1 if target_tabs == 2 else (2 if target_tabs == 4 else 4)
                step_ev_idx = srv.count()
                needed = target_tabs - cur_open
                for j in range(needed):
                    u = urls[(cur_open + j) % len(urls)]
                    procs.append(run_as_user(sess, build_cmd(u, False)))
                    time.sleep(1.2)

                wait_dl = time.time() + 30
                while time.time() < wait_dl and (srv.count() - step_ev_idx) < needed:
                    time.sleep(0.4)
                loads = srv.recent_loads(step_ev_idx)
                snap = read_mem_snapshot(proc_keys)
                oom_delta = snap["oom_kills"] - oom_start
                alive = snap["browser_procs"] > 0
                responsive = len(loads) >= max(1, needed // 2)
                if not alive:
                    crashes += 1
                if alive and oom_delta == 0 and responsive:
                    stable_tabs = target_tabs
                tab_stages[f"tabs_{target_tabs}"] = {
                    "snapshot": snap,
                    "beacons_received": len(loads),
                    "expected_beacons": needed,
                    "avg_page_load_ms": round(sum(x["load_ms"] for x in loads) / len(loads), 1) if loads else None,
                    "alive": alive,
                    "responsive": responsive,
                    "oom_delta": oom_delta,
                }

            if port_fd is not None and port_file is not None:
                # Notify host runner so QMP can capture screenshot while max tabs are open
                msg = {"event": f"browser_{bname}_max", "ts_utc": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()), "data": {"browser": bname, "stable_tabs": stable_tabs}}
                os.write(port_fd, (json.dumps(msg) + "\n").encode("utf-8"))
                # Wait briefly for ack
                ack_dl = time.time() + 10
                while time.time() < ack_dl:
                    ln = port_file.readline()
                    if ln:
                        break
                    time.sleep(0.2)

            kill_browser([bin_name, "Web Content", "QtWebEngineProcess"], procs)
            time.sleep(10)
            post_close = read_mem_snapshot(proc_keys)
            shutil.rmtree(prof_dir, ignore_errors=True)

            results[bname] = {
                "available": True,
                "startup_sec": startup_sec,
                "window_mapped": win_mapped,
                "baseline": baseline,
                "stages": tab_stages,
                "post_close": post_close,
                "stable_tabs_max": stable_tabs,
                "crashes": crashes,
                "oom_kills_delta": post_close["oom_kills"] - oom_start,
                "ram_delta_6tabs_mib": round(tab_stages["tabs_6"]["snapshot"]["ram_used_mib"] - baseline["ram_used_mib"], 1),
                "ram_retained_post_close_mib": round(post_close["ram_used_mib"] - baseline["ram_used_mib"], 1),
            }
    finally:
        srv.stop()

    return results


if __name__ == "__main__":
    print(json.dumps({"bench_ready": True, "pages": list(PAGES.keys())}, indent=2))
