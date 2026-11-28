#!/usr/bin/env python3
"""Repeatable browser & GPU/WebGL/video benchmark for NEXUS OS (Falkon vs Firefox).
Spins up a local deterministic HTTP fixture server and measures startup time,
page load latency, RAM/RSS, CPU, ZRAM/swap activity, OOM/crashes, WebGL/video
readiness, GPU acceleration vs llvmpipe, and post-close memory recovery across
1, 2, 4, and 6 tabs.
"""
import argparse
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

    "/webgl.html": """<!doctype html><html><head><meta charset="utf-8"><title>NEXUS WebGL GPU Probe</title>
<style>body{background:#0b1016;color:#e6edf3;font-family:sans-serif;margin:1.5rem}</style></head>
<body><h1>WebGL & GPU Renderer Probe</h1><canvas id="gl" width="320" height="180"></canvas><script>
window.addEventListener('load',()=>{
  const loadMs=Math.round(performance.now());
  const cv=document.getElementById('gl');
  let ver='none', ren='unavailable';
  const gl2=cv.getContext('webgl2');
  const gl=gl2||cv.getContext('webgl')||cv.getContext('experimental-webgl');
  if(gl){
    ver=gl2?'webgl2':'webgl1';
    const dbg=gl.getExtension('WEBGL_debug_renderer_info');
    ren=dbg?String(gl.getParameter(dbg.UNMASKED_RENDERER_WEBGL)):String(gl.getParameter(gl.RENDERER));
    gl.clearColor(0.08,0.2,0.32,1.0);gl.clear(gl.COLOR_BUFFER_BIT);
  }
  let frames=0, t0=performance.now();
  function step(now){
    frames++;
    if(gl){gl.clearColor(((frames%30)/30)*0.4,0.2,0.35,1.0);gl.clear(gl.COLOR_BUFFER_BIT);}
    if(now-t0>=500){
      const fps=Math.round((frames*1000)/(now-t0));
      const q=new URLSearchParams({page:'webgl',load_ms:String(loadMs),webgl:ver,fps:String(fps),renderer:ren.slice(0,80)});
      fetch('/beacon?'+q.toString()).catch(()=>{});
    } else { requestAnimationFrame(step); }
  }
  requestAnimationFrame(step);
});</script></body></html>""",

    "/video.html": """<!doctype html><html><head><meta charset="utf-8"><title>NEXUS Video Codec Probe</title>
<style>body{background:#0d131a;color:#e6edf3;font-family:sans-serif;margin:1.5rem}</style></head>
<body><h1>HTML5 Video Codec & Frame Loop Probe</h1><video id="vid" width="320" height="180" muted playsinline></video><script>
window.addEventListener('load',()=>{
  const loadMs=Math.round(performance.now());
  const v=document.getElementById('vid');
  const h264=v.canPlayType('video/mp4; codecs="avc1.42E01E"')||'no';
  const vp9=v.canPlayType('video/webm; codecs="vp9"')||'no';
  const vp8=v.canPlayType('video/webm; codecs="vp8"')||'no';
  const av1=v.canPlayType('video/mp4; codecs="av01.0.04M.08"')||'no';
  let frames=0, t0=performance.now();
  function tick(now){
    frames++;
    if(now-t0>=400){
      const fps=Math.round((frames*1000)/(now-t0));
      const q=new URLSearchParams({page:'video',load_ms:String(loadMs),h264,vp9,vp8,av1,fps:String(fps)});
      fetch('/beacon?'+q.toString()).catch(()=>{});
    } else { requestAnimationFrame(tick); }
  }
  requestAnimationFrame(tick);
});</script></body></html>""",
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
                        item = {
                            "ts": time.time(),
                            "page": (qs.get("page") or ["unknown"])[0],
                            "load_ms": int((qs.get("load_ms") or ["0"])[0]) if (qs.get("load_ms") or ["0"])[0].isdigit() else None,
                        }
                        for key in ("webgl", "fps", "renderer", "h264", "vp9", "vp8", "av1"):
                            if key in qs and qs[key]:
                                item[key] = qs[key][0]
                        parent.events.append(item)
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

    def events_since(self, start_idx):
        with self.lock:
            return list(self.events[start_idx:])

    def stop(self):
        self.srv.shutdown()
        self.srv.server_close()


def probe_gpu_environment(sess):
    pci_drivers = []
    pci_dir = Path("/sys/bus/pci/devices")
    if pci_dir.is_dir():
        try:
            for dev in sorted(pci_dir.iterdir()):
                cls = (dev / "class").read_text(encoding="utf-8", errors="replace").strip() if (dev / "class").is_file() else ""
                if cls.startswith("0x03"):
                    drv_link = dev / "driver"
                    pci_drivers.append(drv_link.resolve().name if drv_link.is_symlink() else "none")
        except OSError:
            pass

    glx_renderer = None
    if shutil.which("glxinfo"):
        try:
            gres = subprocess.run(["glxinfo", "-B"], env=x_env(sess), capture_output=True, text=True, timeout=5)
            if gres.returncode == 0:
                for line in gres.stdout.splitlines():
                    if "OpenGL renderer string:" in line:
                        glx_renderer = line.split(":", 1)[1].strip()
                        break
        except Exception:
            pass

    sw = (
        any(d in ("bochs-drm", "virtio_gpu", "virtio-pci", "none") for d in pci_drivers)
        or (glx_renderer is not None and any(k in glx_renderer.lower() for k in ("llvmpipe", "softpipe", "swrast")))
    )
    accel_mode = "software_llvmpipe_or_virtual" if sw else ("hardware_gpu" if pci_drivers else "unknown")
    return {
        "pci_gpu_drivers": sorted(set(pci_drivers)),
        "glx_renderer": glx_renderer,
        "acceleration_mode": accel_mode,
        "bare_metal_gpu_qualified": accel_mode == "hardware_gpu",
    }


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
    if sess.get("xauthority"):
        env["XAUTHORITY"] = sess["xauthority"]
    env["HOME"] = sess["home"]
    env["USER"] = sess["user"]
    env["LOGNAME"] = sess["user"]
    env["XDG_RUNTIME_DIR"] = f"/run/user/{sess['uid']}"
    if sess.get("dbus"):
        env["DBUS_SESSION_BUS_ADDRESS"] = sess["dbus"]
    return env


def run_as_user(sess, cmd):
    if os.geteuid() == sess["uid"]:
        return subprocess.Popen(
            cmd,
            env=x_env(sess),
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            start_new_session=True,
        )

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


def kill_browser(uid, proc_names, main_procs):
    for p in main_procs:
        if p.poll() is None:
            try:
                os.killpg(os.getpgid(p.pid), signal.SIGTERM)
            except Exception:
                pass
    time.sleep(3)
    for name in proc_names:
        subprocess.run(["pkill", "-u", str(uid), "-TERM", "-f", name], capture_output=True)
    time.sleep(2)
    for name in proc_names:
        subprocess.run(["pkill", "-u", str(uid), "-KILL", "-f", name], capture_output=True)


def run_browser_suite(sess, port_fd=None, port_file=None, send_event=None, wait_for_cmd=None, browser_filter=None):
    srv = BenchHTTPServer()
    base = f"http://127.0.0.1:{srv.port}"
    urls = [
        f"{base}/page1.html",
        f"{base}/webgl.html",
        f"{base}/video.html",
        f"{base}/page2.html",
        f"{base}/page3.html",
        f"{base}/page4.html",
    ]

    all_candidates = [
        ("falkon", "falkon", ["falkon", "qtwebengine"]),
        ("firefox", "firefox", ["firefox", "isolated", "web content"]),
    ]
    candidates = [c for c in all_candidates if not browser_filter or c[0] in browser_filter]
    sys_ram_mib = read_mem_snapshot([])["ram_total_mib"]
    gpu_env = probe_gpu_environment(sess)
    results = {}

    try:
        for bname, bin_name, proc_keys in candidates:
            if not shutil.which(bin_name):
                results[bname] = {"available": False, "reason": f"{bin_name}_not_installed"}
                continue

            prof_dir = Path(sess["home"]) / f".nexus-bench-{bname}"
            shutil.rmtree(prof_dir, ignore_errors=True)
            prof_dir.mkdir(parents=True, exist_ok=True)
            if bname == "falkon":
                shutil.rmtree(Path(sess["home"]) / ".config/falkon/profiles" / f"nexus-bench-{bname}", ignore_errors=True)
            if os.geteuid() == 0:
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
            run_ev_start = srv.count()
            ev_idx = run_ev_start

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

            sw_mode = not gpu_env.get("bare_metal_gpu_qualified")
            tab_wait_sec = 45 if sw_mode else 30
            b_deadline = time.time() + tab_wait_sec
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

            for target_tabs in (2, 4, 6):
                cur_open = 1 if target_tabs == 2 else (2 if target_tabs == 4 else 4)
                step_ev_idx = srv.count()
                needed = target_tabs - cur_open
                for j in range(needed):
                    u = urls[(cur_open + j) % len(urls)]
                    procs.append(run_as_user(sess, build_cmd(u, False)))
                    time.sleep(1.2)

                wait_dl = time.time() + tab_wait_sec
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

            all_evs = srv.events_since(run_ev_start)
            webgl_ev = next((e for e in all_evs if e.get("page") == "webgl"), None)
            video_ev = next((e for e in all_evs if e.get("page") == "video"), None)

            if port_fd is not None and port_file is not None:
                if send_event and wait_for_cmd:
                    send_event(port_fd, f"browser_{bname}_max", {"browser": bname, "stable_tabs": stable_tabs})
                    wait_for_cmd(port_file, "ack", timeout=15)
                else:
                    msg = {"event": f"browser_{bname}_max", "ts_utc": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()), "data": {"browser": bname, "stable_tabs": stable_tabs}}
                    os.write(port_fd, (json.dumps(msg) + "\n").encode("utf-8"))
                    ack_dl = time.time() + 10
                    while time.time() < ack_dl:
                        ln = port_file.readline()
                        if ln:
                            break
                        time.sleep(0.2)

            kill_browser(sess["uid"], [bin_name, "Web Content", "QtWebEngineProcess"], procs)
            time.sleep(10)
            post_close = read_mem_snapshot(proc_keys)
            shutil.rmtree(prof_dir, ignore_errors=True)

            results[bname] = {
                "available": True,
                "startup_sec": startup_sec,
                "window_mapped": win_mapped,
                "baseline": baseline,
                "stages": tab_stages,
                "webgl_probe": webgl_ev or {"webgl": "not_reached"},
                "video_probe": video_ev or {"h264": "not_reached", "vp9": "not_reached"},
                "post_close": post_close,
                "stable_tabs_max": stable_tabs,
                "crashes": crashes,
                "oom_kills_delta": post_close["oom_kills"] - oom_start,
                "ram_delta_6tabs_mib": round(tab_stages["tabs_6"]["snapshot"]["ram_used_mib"] - baseline["ram_used_mib"], 1),
                "ram_retained_post_close_mib": round(post_close["ram_used_mib"] - baseline["ram_used_mib"], 1),
            }
    finally:
        srv.stop()

    return {"system_ram_mib": sys_ram_mib, "gpu_environment": gpu_env, "browsers": results}


def main():
    parser = argparse.ArgumentParser(description="NEXUS OS Browser & GPU/WebGL/Video Benchmark")
    parser.add_argument("--standalone", action="store_true", help="Run directly inside the current X11 desktop session")
    parser.add_argument("--edition", default="unknown", help="Edition label (cinnamon, xfce, lite, lite-lxqt)")
    parser.add_argument("--browsers", default="falkon,firefox", help="Comma-separated browsers to test")
    parser.add_argument("--out", default="", help="Optional path to write JSON results")
    args = parser.parse_args()

    if not args.standalone:
        print(json.dumps({"bench_ready": True, "pages": list(PAGES.keys())}, indent=2))
        return

    disp = os.environ.get("DISPLAY")
    if not disp:
        print("Error: --standalone requires an active X11 DISPLAY session.", file=sys.stderr)
        sys.exit(2)

    pw = pwd.getpwuid(os.geteuid())
    sess = {
        "uid": pw.pw_uid,
        "user": pw.pw_name,
        "home": pw.pw_dir,
        "display": disp,
        "xauthority": os.environ.get("XAUTHORITY", str(Path(pw.pw_dir) / ".Xauthority")),
        "dbus": os.environ.get("DBUS_SESSION_BUS_ADDRESS", ""),
    }
    bfilter = {b.strip().lower() for b in args.browsers.split(",") if b.strip()}
    report = {
        "schema_version": 2,
        "edition": args.edition,
        "generated_at_utc": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "results": run_browser_suite(sess, browser_filter=bfilter),
    }
    if args.out:
        out_p = Path(args.out)
        out_p.parent.mkdir(parents=True, exist_ok=True)
        out_p.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    main()
