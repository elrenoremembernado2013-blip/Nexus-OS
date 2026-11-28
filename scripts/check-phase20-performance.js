const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const { execFileSync, spawn } = require("node:child_process");

const ROOT = path.resolve(__dirname, "..");

function makeNode(tag, doc) {
  const listeners = new Map();
  const children = [];
  const classes = new Set();
  const node = {
    tagName: String(tag).toUpperCase(),
    className: "",
    id: "",
    textContent: "",
    innerHTML: "",
    disabled: false,
    dataset: {},
    style: {},
    attributes: {},
    children,
    parentNode: null,
    _listeners: listeners,
    classList: {
      add: (...names) => names.forEach(n => classes.add(n)),
      remove: (...names) => names.forEach(n => classes.delete(n)),
      toggle: (n, force) => {
        if (force === undefined) {
          if (classes.has(n)) classes.delete(n);
          else classes.add(n);
        } else if (force) classes.add(n);
        else classes.delete(n);
      },
      contains: n => classes.has(n),
    },
    setAttribute(k, v) {
      this.attributes[k] = String(v);
      if (k === "id") this.id = String(v);
      if (k === "class") this.className = String(v);
    },
    getAttribute(k) {
      return this.attributes[k] ?? null;
    },
    append(...items) {
      for (const item of items) {
        if (item && typeof item === "object") {
          item.parentNode = this;
          children.push(item);
        }
      }
    },
    replaceChildren(...items) {
      children.length = 0;
      this.append(...items);
    },
    addEventListener(type, fn) {
      if (!listeners.has(type)) listeners.set(type, []);
      listeners.get(type).push(fn);
    },
    removeEventListener(type, fn) {
      const list = listeners.get(type) || [];
      listeners.set(type, list.filter(f => f !== fn));
    },
    closest(selector) {
      let cur = this;
      while (cur) {
        if (matches(cur, selector)) return cur;
        cur = cur.parentNode;
      }
      return null;
    },
    click() {
      let cur = this;
      const ev = { target: this, currentTarget: this, preventDefault() {} };
      while (cur) {
        for (const fn of cur._listeners?.get("click") || []) fn(ev);
        cur = cur.parentNode;
      }
    },
    querySelector(sel) {
      return this.querySelectorAll(sel)[0] || null;
    },
    querySelectorAll(sel) {
      const out = [];
      const visit = n => {
        for (const c of n.children || []) {
          if (matches(c, sel)) out.push(c);
          visit(c);
        }
      };
      visit(this);
      return out;
    },
  };
  return node;
}

function matches(node, selector) {
  if (!node || !selector) return false;
  if (selector.startsWith("#")) return node.id === selector.slice(1);
  if (selector.startsWith(".")) return node.className.split(/\s+/).includes(selector.slice(1)) || node.classList.contains(selector.slice(1));
  const m = selector.match(/^\[([a-zA-Z0-9-]+)(?:="([^"]*)")?\]$/);
  if (m) {
    const key = m[1].replace(/^data-/, "").replace(/-([a-z])/g, (_, c) => c.toUpperCase());
    const val = node.dataset?.[key];
    return m[2] !== undefined ? val === m[2] : val !== undefined;
  }
  if (/^[a-zA-Z0-9-]+$/.test(selector)) {
    return node.tagName === selector.toUpperCase();
  }
  return false;
}

function runUiTests() {
  let activeIntervals = 0;
  let nextTimerId = 1;
  let lowResEnabled = false;
  const controlListeners = new Set();

  const doc = {
    createElement: tag => makeNode(tag, doc),
    createElementNS: (_ns, tag) => makeNode(tag, doc),
  };

  global.document = doc;
  global.window = {
    setInterval: () => {
      activeIntervals += 1;
      return nextTimerId++;
    },
    clearInterval: id => {
      if (id) activeIntervals = Math.max(0, activeIntervals - 1);
    },
  };

  const apps = new Map();
  global.window.NexusAppRegistry = {
    register: def => apps.set(def.id, def),
  };

  let telemetryAvail = false;
  let perfAvail = false;
  let cpuVal = 15;
  const cleanupCalls = [];
  const startupCalls = [];

  global.window.NexusNativeServices = {
    status: id => ({
      available: id === "telemetry" ? telemetryAvail : id === "performance" ? perfAvail : false,
    }),
    call: (id, method, ...args) => {
      if (id === "telemetry" && method === "snapshot") {
        cpuVal += 5;
        return {
          processor: { summary: `${cpuVal}% used`, detail: "Load avg (1m): 0.25", percent: cpuVal },
          memory: { summary: "1200 / 4096 MiB (29.3%)", detail: "2896 MiB available", percent: 29.3, swap_used_mib: 64, swap_total_mib: 2048, swap_percent: 3.1 },
          storage: { summary: "12 / 60 GiB", detail: "48 GiB free on /" },
          processes: { summary: "Top 2 by RSS", detail: "python3, xfwm4", items: [{ pid: 101, name: "python3", user: "user", rss_mib: 42.1 }] },
          network: { summary: "1 iface(s)", detail: "RX 1.2 MiB · TX 0.4 MiB" },
          battery: { summary: "Unavailable", detail: "No battery reported" },
          temperature: { summary: "42 °C", detail: "thermal_zone0", celsius: 42 },
          gpu: { driver: "amdgpu", busy_percent: 12 },
          uptime_seconds: 3725,
        };
      }
      if (id === "performance" && method === "overview") {
        return {
          edition: "lite-lxqt",
          boot: { summary: "Startup finished in 1.2s (kernel) + 3.4s (userspace)", top_slow_units: [{ time: "1.1s", unit: "NetworkManager-wait-online.service" }] },
          startup_apps: [
            { id: "polkit-gnome.desktop", name: "Polkit Auth", scope: "system", enabled: true, essential: true },
            { id: "sample-helper.desktop", name: "Sample Helper", scope: "user", enabled: true, essential: false },
          ],
          storage_devices: [{ device: "vda", kind: "ssd_or_nvme" }],
          cleanup_preview: [
            { target: "thumbnails", label: "Image thumbnail cache", path: "/home/user/.cache/thumbnails", mib: 14.5, files: 12, requires_admin: false },
          ],
          edition_recommendations: ["Keep zramswap enabled for responsive multitasking."],
        };
      }
      if (id === "performance" && method === "cleanup") {
        cleanupCalls.push(args[0]);
        return { ok: true, message: `Cleaned ${args[0]}` };
      }
      if (id === "performance" && method === "setStartup") {
        startupCalls.push(args);
        return { ok: true, message: `Updated ${args[0]}` };
      }
      return {};
    },
  };

  require(path.join(ROOT, "apps/system-monitor.js"));
  const monitorApp = apps.get("monitor");
  assert(monitorApp, "monitor app must register");

  const desktopShell = {
    isLowResourceMode: () => lowResEnabled,
    setLowResourceMode: next => {
      lowResEnabled = Boolean(next);
      controlListeners.forEach(fn => fn({ power: lowResEnabled }));
    },
    onControlChange: fn => {
      controlListeners.add(fn);
      return () => controlListeners.delete(fn);
    },
  };

  // 1. Disconnected state: no synthetic graphs, Low-Resource Mode works & reverses
  const rootOff = makeNode("div", doc);
  const gridOff = makeNode("div", doc); gridOff.id = "monitorGrid";
  const badgeOff = makeNode("span", doc); badgeOff.id = "monitorStatusBadge";
  const boundaryOff = makeNode("div", doc); boundaryOff.id = "monitorBoundary";
  const lowResBtnOff = makeNode("button", doc); lowResBtnOff.id = "perfLowResToggle";
  const lowResStatusOff = makeNode("p", doc); lowResStatusOff.id = "perfLowResStatus";
  const tabPanelOff = makeNode("div", doc); tabPanelOff.id = "perfTabPanel";
  const tabGraphs = makeNode("button", doc); tabGraphs.dataset.perfTab = "graphs";
  rootOff.append(gridOff, badgeOff, boundaryOff, lowResBtnOff, lowResStatusOff, tabPanelOff, tabGraphs);

  const unmountOff = monitorApp.mount(rootOff, { desktopShell });
  assert.equal(gridOff.children.length, 7);
  assert(tabPanelOff.querySelectorAll(".perf-sparkline").length === 0, "Must not render synthetic sparklines when disconnected");
  lowResBtnOff.click();
  assert.equal(lowResEnabled, true);
  assert.equal(lowResBtnOff.textContent, "Disable Low-Resource Mode");
  lowResBtnOff.click();
  assert.equal(lowResEnabled, false);
  assert.equal(lowResBtnOff.textContent, "Enable Low-Resource Mode");
  unmountOff();

  // 2. Connected state: bounded history <= 24, auto-refresh cleanup, startup & confirmed cleanup
  telemetryAvail = true;
  perfAvail = true;
  const rootOn = makeNode("div", doc);
  const gridOn = makeNode("div", doc); gridOn.id = "monitorGrid";
  const badgeOn = makeNode("span", doc); badgeOn.id = "monitorStatusBadge";
  const boundaryOn = makeNode("div", doc); boundaryOn.id = "monitorBoundary";
  const refreshOn = makeNode("button", doc); refreshOn.id = "monitorRefresh";
  const autoOn = makeNode("button", doc); autoOn.id = "monitorAutoBtn";
  const lowResBtnOn = makeNode("button", doc); lowResBtnOn.id = "perfLowResToggle";
  const lowResStatusOn = makeNode("p", doc); lowResStatusOn.id = "perfLowResStatus";
  const tabPanelOn = makeNode("div", doc); tabPanelOn.id = "perfTabPanel";
  const actionStatusOn = makeNode("p", doc); actionStatusOn.id = "perfActionStatus";
  const tGraphs = makeNode("button", doc); tGraphs.dataset.perfTab = "graphs";
  const tStartup = makeNode("button", doc); tStartup.dataset.perfTab = "startup";
  const tCleanup = makeNode("button", doc); tCleanup.dataset.perfTab = "cleanup";
  const tEditions = makeNode("button", doc); tEditions.dataset.perfTab = "editions";
  rootOn.append(gridOn, badgeOn, boundaryOn, refreshOn, autoOn, lowResBtnOn, lowResStatusOn, tabPanelOn, actionStatusOn, tGraphs, tStartup, tCleanup, tEditions);

  const unmountOn = monitorApp.mount(rootOn, { desktopShell });
  for (let i = 0; i < 29; i += 1) refreshOn.click();
  const hints = tabPanelOn.querySelectorAll(".settings-hint").map(n => n.textContent);
  assert(hints.some(t => t.includes("Bounded buffer: 24/24 samples")), `Expected bounded 24/24 buffer, got: ${hints.join(" | ")}`);

  autoOn.click();
  assert.equal(activeIntervals, 1, "Auto-refresh must register one timer");

  // Startup tab: essential unit disabled button, non-essential callable
  tStartup.click();
  const startupBtns = tabPanelOn.querySelectorAll("button").filter(b => b.dataset.startupId);
  assert.equal(startupBtns.length, 2);
  assert.equal(startupBtns[0].disabled, true, "Essential polkit startup button must stay disabled");
  assert.equal(startupBtns[1].disabled, false);
  startupBtns[1].click();
  assert.deepEqual(startupCalls, [["sample-helper.desktop", false]]);

  // Cleanup tab: requires preview -> confirm step
  tCleanup.click();
  const previewBtn = tabPanelOn.querySelectorAll("button").find(b => b.dataset.cleanupPreview === "thumbnails");
  assert(previewBtn, "Cleanup preview button must appear");
  previewBtn.click();
  assert.equal(cleanupCalls.length, 0, "Preview click must not delete immediately");
  const confirmBtn = tabPanelOn.querySelectorAll("button").find(b => b.dataset.cleanupConfirm === "thumbnails");
  assert(confirmBtn, "Confirm Clean button must appear after preview");
  confirmBtn.click();
  assert.deepEqual(cleanupCalls, ["thumbnails"]);

  unmountOn();
  assert.equal(activeIntervals, 0, "Unmount must clear auto-refresh interval");
  console.log("PASS Performance Centre UI, bounded history, timer cleanup, startup & confirmed cleanup checks");
}

function runCliAndAppChecks() {
  const appJs = fs.readFileSync(path.join(ROOT, "app.js"), "utf8");
  assert(appJs.includes("launcherButtonMap"), "app.js must cache launcher DOM nodes");
  assert(appJs.includes("isLowResourceMode"), "app.js must expose isLowResourceMode");
  assert(appJs.includes("setLowResourceMode"), "app.js must expose setLowResourceMode");

  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "nexus-p20-"));
  try {
    const cfg = path.join(tmp, "cfg");
    const cache = path.join(tmp, "cache");
    const data = path.join(tmp, "data");
    const docs = path.join(tmp, "Documents");
    fs.mkdirSync(path.join(cache, "thumbnails", "normal"), { recursive: true });
    fs.mkdirSync(path.join(data, "nexus-os", "wallpapers"), { recursive: true });
    fs.mkdirSync(path.join(cfg, "nexus-os"), { recursive: true });
    fs.mkdirSync(docs, { recursive: true });

    const keepDoc = path.join(docs, "important.txt");
    const thumbFile = path.join(cache, "thumbnails", "normal", "t1.png");
    const activeWp = path.join(data, "nexus-os", "wallpapers", "active.jpg");
    const oldWp = path.join(data, "nexus-os", "wallpapers", "unused.jpg");
    fs.writeFileSync(keepDoc, "keep-me");
    fs.writeFileSync(thumbFile, "thumb");
    fs.writeFileSync(activeWp, "wp-active");
    fs.writeFileSync(oldWp, "wp-old");
    fs.writeFileSync(path.join(cfg, "nexus-os", "wallpaper.conf"), `WALLPAPER_PATH=${activeWp}\n`);

    const env = { ...process.env, XDG_CONFIG_HOME: cfg, XDG_CACHE_HOME: cache, XDG_DATA_HOME: data };
    const cli = path.join(ROOT, "linux/mint/nexus-performance-cli.sh");

    const ov = JSON.parse(execFileSync("bash", [cli, "overview"], { env, encoding: "utf8" }));
    assert(ov.cleanup_preview.some(c => c.target === "thumbnails" && c.files === 1));
    assert(Array.isArray(ov.edition_recommendations) && ov.edition_recommendations.length > 0);

    // Cleanup without --confirm must fail and preserve files
    let failedWithoutConfirm = false;
    try {
      execFileSync("bash", [cli, "cleanup", "--target", "thumbnails"], { env, stdio: "ignore" });
    } catch {
      failedWithoutConfirm = true;
    }
    assert.equal(failedWithoutConfirm, true);
    assert(fs.existsSync(thumbFile));

    // Confirmed cleanup removes ONLY target cache, preserving active wallpaper & user Documents
    execFileSync("bash", [cli, "cleanup", "--target", "thumbnails", "--confirm"], { env, stdio: "ignore" });
    assert(!fs.existsSync(thumbFile), "Thumbnail cache must be cleared after --confirm");
    assert(fs.existsSync(keepDoc), "User Documents must never be deleted");

    execFileSync("bash", [cli, "cleanup", "--target", "wallpapers", "--confirm"], { env, stdio: "ignore" });
    assert(fs.existsSync(activeWp), "Active wallpaper must be preserved");
    assert(!fs.existsSync(oldWp), "Unused cached wallpaper should be removed");

    // Low-resource mode enable/disable reversibility
    execFileSync("bash", [cli, "low-resource", "enable"], { env, stdio: "ignore" });
    assert.equal(execFileSync("bash", [cli, "low-resource", "status"], { env, encoding: "utf8" }).trim(), "low_resource_mode=enabled");
    execFileSync("bash", [cli, "low-resource", "disable"], { env, stdio: "ignore" });
    assert.equal(execFileSync("bash", [cli, "low-resource", "status"], { env, encoding: "utf8" }).trim(), "low_resource_mode=disabled");

    // Startup reversible toggle
    execFileSync("bash", [cli, "startup", "disable", "example-notifier.desktop"], { env, stdio: "ignore" });
    assert(fs.readFileSync(path.join(cfg, "autostart", "example-notifier.desktop"), "utf8").includes("Hidden=true"));
    execFileSync("bash", [cli, "startup", "enable", "example-notifier.desktop"], { env, stdio: "ignore" });
    assert(fs.readFileSync(path.join(cfg, "autostart", "example-notifier.desktop"), "utf8").includes("Hidden=false"));

    // Gaming CLI enhanced telemetry
    const gaming = JSON.parse(execFileSync("bash", [path.join(ROOT, "linux/mint/nexus-gaming-cli.sh"), "status"], { env, encoding: "utf8" }));
    assert(gaming.hardware && "storage_kind" in gaming.hardware);
    assert(gaming.performance && "compositor_guidance" in gaming.performance);
    assert(Array.isArray(gaming.steam?.launch_options_hints));

    console.log("PASS nexus-performance-cli.sh safety, reversibility, and gaming CLI telemetry checks");
  } finally {
    fs.rmSync(tmp, { recursive: true, force: true });
  }
}

async function runBridgeAndBenchTests() {
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "nexus-p20-bridge-"));
  const runtimeFile = path.join(tmp, "bridge.json");
  const proc = spawn("python3", [path.join(ROOT, "linux/mint/nexus-system-bridge.py"), "--serve", "--port", "0", "--runtime-file", runtimeFile], {
    stdio: ["ignore", "pipe", "pipe"],
  });

  try {
    let info = null;
    for (let i = 0; i < 60; i += 1) {
      if (fs.existsSync(runtimeFile)) {
        info = JSON.parse(fs.readFileSync(runtimeFile, "utf8"));
        break;
      }
      await new Promise(r => setTimeout(r, 100));
    }
    assert(info && info.url && info.token, "Bridge runtime JSON did not appear");

    // Unauthorized request must fail 401
    const unauth = await fetch(`${info.url}/api/performance/overview`);
    assert.equal(unauth.status, 401);

    // Authorized overview & telemetry benchmark (initial vs cached delta calls)
    const ovRes = await fetch(`${info.url}/api/performance/overview`, {
      headers: { "X-Nexus-Token": info.token },
    });
    assert.equal(ovRes.status, 200);
    const ovJson = await ovRes.json();
    assert(ovJson.memory && ovJson.boot && ovJson.cleanup_preview);

    const t0 = performance.now();
    const firstTel = await fetch(`${info.url}/api/telemetry`, { headers: { "X-Nexus-Token": info.token } });
    assert.equal(firstTel.status, 200);
    const firstMs = performance.now() - t0;

    const samples = [];
    for (let i = 0; i < 5; i += 1) {
      const s0 = performance.now();
      const r = await fetch(`${info.url}/api/telemetry`, { headers: { "X-Nexus-Token": info.token } });
      assert.equal(r.status, 200);
      const snap = await r.json();
      assert("swap_total_mib" in snap.memory);
      assert("uptime_seconds" in snap);
      samples.push(performance.now() - s0);
    }
    const avgFollowupMs = samples.reduce((a, b) => a + b, 0) / samples.length;
    console.log(`PASS Bridge /api/performance/overview auth + /api/telemetry latency (first=${firstMs.toFixed(1)}ms, cached-delta avg=${avgFollowupMs.toFixed(1)}ms)`);
  } finally {
    proc.kill("SIGTERM");
    fs.rmSync(tmp, { recursive: true, force: true });
  }
}

(async () => {
  runUiTests();
  runCliAndAppChecks();
  await runBridgeAndBenchTests();
})();
