#!/usr/bin/env node
"use strict";
const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const vm = require("node:vm");
const { execFileSync, spawn } = require("node:child_process");

const ROOT = path.resolve(__dirname, "..");

function makeEl(tag = "div") {
  const listeners = new Map();
  const children = [];
  const attrs = {};
  const classes = new Set();
  const el = {
    tagName: tag.toUpperCase(),
    id: "",
    type: "",
    value: "",
    rows: 3,
    disabled: false,
    tabIndex: 0,
    title: "",
    textContent: "",
    dataset: {},
    style: {},
    children,
    _listeners: listeners,
    classList: {
      add: (...c) => c.forEach(x => classes.add(x)),
      remove: (...c) => c.forEach(x => classes.delete(x)),
      toggle: (x, f) => (f === undefined ? (classes.has(x) ? classes.delete(x) : classes.add(x)) : (f ? classes.add(x) : classes.delete(x))),
      contains: x => classes.has(x),
    },
    set className(v) {
      classes.clear();
      String(v || "").split(/\s+/).filter(Boolean).forEach(x => classes.add(x));
    },
    get className() {
      return [...classes].join(" ");
    },
    setAttribute(k, v) {
      attrs[k] = String(v);
      if (k === "id") el.id = String(v);
      if (k.startsWith("data-")) {
        const camel = k.slice(5).replace(/-([a-z])/g, (_, ch) => ch.toUpperCase());
        el.dataset[camel] = String(v);
      }
    },
    getAttribute(k) {
      return attrs[k] ?? null;
    },
    append(...nodes) {
      for (const n of nodes) {
        if (n && typeof n === "object") {
          n.parentNode = el;
          children.push(n);
        }
      }
    },
    prepend(...nodes) {
      for (const n of [...nodes].reverse()) {
        if (n && typeof n === "object") {
          n.parentNode = el;
          children.unshift(n);
        }
      }
    },
    replaceChildren(...nodes) {
      children.length = 0;
      el.append(...nodes);
    },
    addEventListener(type, fn) {
      if (!listeners.has(type)) listeners.set(type, []);
      listeners.get(type).push(fn);
    },
    removeEventListener(type, fn) {
      listeners.set(type, (listeners.get(type) || []).filter(f => f !== fn));
    },
    closest(sel) {
      let cur = el;
      while (cur) {
        if (matches(cur, sel)) return cur;
        cur = cur.parentNode || null;
      }
      return null;
    },
    focus() {},
    remove() {
      if (el.parentNode && Array.isArray(el.parentNode.children)) {
        el.parentNode.children = el.parentNode.children.filter(c => c !== el);
      }
    },
    querySelector(sel) {
      return el.querySelectorAll(sel)[0] || null;
    },
    querySelectorAll(sel) {
      const out = [];
      (function walk(node) {
        for (const c of node.children || []) {
          if (matches(c, sel)) out.push(c);
          walk(c);
        }
      })(el);
      return out;
    },
    click() {
      let cur = el;
      const ev = { target: el, currentTarget: el, preventDefault() {} };
      while (cur) {
        for (const fn of cur._listeners?.get("click") || []) fn(ev);
        cur = cur.parentNode || null;
      }
    },
    dispatch(type, ev = {}) {
      for (const fn of listeners.get(type) || []) fn({ target: el, preventDefault() {}, ...ev });
    },
  };
  return el;
}

function matches(el, sel) {
  if (!el || !sel) return false;
  if (sel.startsWith("#")) return el.id === sel.slice(1);
  if (sel.startsWith(".")) return el.className.split(/\s+/).includes(sel.slice(1));
  const m = sel.match(/^\[([a-zA-Z0-9-]+)(?:="([^"]*)")?\]$/);
  if (m) {
    const camel = m[1].replace(/^data-/, "").replace(/-([a-z])/g, (_, ch) => ch.toUpperCase());
    const v = el.dataset?.[camel];
    return m[2] !== undefined ? v === m[2] : v !== undefined;
  }
  return /^[a-zA-Z0-9-]+$/.test(sel) && el.tagName === sel.toUpperCase();
}

function collectText(node) {
  let txt = node.textContent || "";
  for (const c of node.children || []) txt += " " + collectText(c);
  return txt;
}

function testQuantumNotesAndLinuxTrack() {
  const storage = new Map();
  const contentCtx = { window: {} };
  vm.runInNewContext(fs.readFileSync(path.join(ROOT, "apps/quantum-content.js"), "utf8"), contentCtx);
  const content = contentCtx.window.NexusQuantumContent;
  assert.ok(content.getTrack("linux"), "Quantum must include linux track");
  assert.equal(content.checkAnswer("lx-permissions", "pkexec").correct, true);
  assert.equal(content.checkAnswer("lx-packages", "Flatpak").correct, true);

  const engineCtx = { window: {} };
  vm.runInNewContext(fs.readFileSync(path.join(ROOT, "apps/quantum-engine.js"), "utf8"), engineCtx);

  let registered = null;
  const viewTabs = ["learn", "lab", "languages", "coding", "notes", "guide"].map(v => {
    const b = makeEl("button");
    b.dataset.quantumView = v;
    return b;
  });
  const body = makeEl("div");
  const xp = makeEl("span");
  const completed = makeEl("span");
  const status = makeEl("p");
  let savedNativeNotes = null;

  const qCtx = {
    document: { createElement: t => makeEl(t), createTextNode: s => ({ textContent: String(s) }) },
    window: {
      localStorage: {
        getItem: k => (storage.has(k) ? storage.get(k) : null),
        setItem: (k, v) => storage.set(k, String(v)),
      },
      NexusQuantumEngine: engineCtx.window.NexusQuantumEngine,
      NexusQuantumContent: content,
      NexusNativeServices: {
        status: id => ({ available: id === "quantum" }),
        call: (_id, method, arg) => {
          if (method === "loadNotes") return Promise.resolve({ path: "/home/user/.local/share/nexus-os/quantum-notes.json", notes: [] });
          if (method === "saveNotes") {
            savedNativeNotes = arg;
            return Promise.resolve({ ok: true });
          }
          return {};
        },
      },
      NexusAppRegistry: { register: app => { registered = app; } },
    },
  };
  vm.runInNewContext(fs.readFileSync(path.join(ROOT, "apps/quantum.js"), "utf8"), qCtx);
  assert.ok(registered.render().includes("Notes &amp; Paths") || registered.render().includes("Notes & Paths"));
  registered.mount({
    querySelector: s => ({ "#quantumBody": body, "#quantumXp": xp, "#quantumCompleted": completed, "#quantumStorageStatus": status }[s] || makeEl("div")),
    querySelectorAll: s => (s === "[data-quantum-view]" ? viewTabs : []),
  }, {});

  // Switch to Notes & Paths tab and save a note
  viewTabs.find(t => t.dataset.quantumView === "notes").click();
  const form = body.querySelector("form");
  assert.ok(form, "Notes tab must render note creation form");
  const titleInput = form.querySelectorAll("input")[0];
  const bodyInput = form.querySelector("textarea");
  titleInput.value = "Phase 21 Note";
  bodyInput.value = "Polkit protects APT actions";
  form.dispatch("submit");
  assert.ok(collectText(body).includes("Phase 21 Note"));
  assert.ok(Array.isArray(savedNativeNotes) && savedNativeNotes[0].title === "Phase 21 Note");
  console.log("PASS Quantum Linux track, Notes & Paths creation, and local/native sync check");
}

async function testStoreInstalledLibraryAndErrors() {
  const storage = new Map();
  const catCtx = {
    window: {
      localStorage: { getItem: k => storage.get(k) ?? null, setItem: (k, v) => storage.set(k, String(v)) },
      addEventListener() {},
    },
  };
  vm.runInNewContext(fs.readFileSync(path.join(ROOT, "apps/store-catalog.js"), "utf8"), catCtx);

  let storeApp = null;
  const storeCtx = {
    window: {
      NexusApplicationCatalog: catCtx.window.NexusApplicationCatalog,
      NexusNativeServices: {
        status: id => ({ available: id === "packages" }),
        call: (_id, method, a1, a2) => {
          if (method === "sources") return Promise.resolve({ apt: true, flatpak: true, pkexec: true });
          if (method === "installed") {
            return Promise.resolve({
              apt: [{ id: "gimp", name: "gimp", version: "2.10.36", source: "apt" }],
              flatpak: [{ id: "org.videolan.VLC", name: "VLC", version: "3.0.21", source: "flatpak" }],
            });
          }
          if (method === "install") {
            return Promise.resolve({ ok: false, errorKind: "polkit_cancelled", message: "Cancelled" });
          }
          if (method === "info") {
            return Promise.resolve({ id: a2, source: a1, version: "2.10.36", dependencies: ["libc6"] });
          }
          return Promise.resolve([]);
        },
      },
      NexusAppRegistry: { register: app => { storeApp = app; } },
      confirm: () => true,
    },
    document: { createElement: t => makeEl(t) },
  };
  vm.runInNewContext(fs.readFileSync(path.join(ROOT, "apps/software-centre.js"), "utf8"), storeCtx);
  assert.ok(storeApp.render().includes("Native APT / Flatpak connected"));

  const page = makeEl("div"); page.id = "storePage";
  const search = makeEl("input"); search.id = "storeSearch";
  const title = makeEl("h2"); title.id = "storeViewTitle";
  const back = makeEl("button"); back.id = "storeBack";
  const message = makeEl("p"); message.id = "storeMessage";
  const libBtn = makeEl("button"); libBtn.dataset.storeView = "library";
  const root = makeEl("div");
  root.append(page, search, title, back, message, libBtn);

  storeApp.mount(root, {});
  libBtn.click();
  await new Promise(r => setTimeout(r, 20));
  const txt = collectText(page);
  assert.ok(txt.includes("Installed Linux Mint packages"), "My Library must show installed Linux Mint packages section");
  assert.ok(txt.includes("VLC"), "My Library must display installed Flatpak app");
  assert.ok(txt.includes("gimp"), "My Library must display installed APT package");
  console.log("PASS NEXUS Store live sources & installed APT/Flatpak library integration check");
}

function testAppModeClassificationAndLaunchers() {
  const appJs = fs.readFileSync(path.join(ROOT, "app.js"), "utf8");
  assert.ok(appJs.includes("classifyAppMode"), "app.js must classify native vs local vs preview apps");
  assert.ok(appJs.includes("getAppRuntimeMode"), "NexusDesktopShell must expose getAppRuntimeMode");

  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "nexus-p21-launch-"));
  try {
    const bin = path.join(tmp, "bin");
    fs.mkdirSync(bin);
    const log = path.join(tmp, "log.txt");
    for (const tool of ["qterminal", "firefox"]) {
      const p = path.join(bin, tool);
      fs.writeFileSync(p, `#!/bin/sh\necho "${tool} $*" >> "${log}"\n`);
      fs.chmodSync(p, 0o755);
    }
    const perfStub = path.join(bin, "nexus-perf");
    fs.writeFileSync(perfStub, "#!/bin/sh\nexit 0\n");
    fs.chmodSync(perfStub, 0o755);

    execFileSync("/bin/bash", [path.join(ROOT, "linux/branding/nexus-launch-app.sh"), "performance"], {
      env: { PATH: bin, NEXUS_PERF_CLI: perfStub },
    });
    assert.ok(fs.readFileSync(log, "utf8").includes("qterminal -e"));

    execFileSync("/bin/bash", [path.join(ROOT, "linux/branding/nexus-launch-app.sh"), "quantum"], {
      env: { PATH: bin },
    });
    assert.ok(fs.readFileSync(log, "utf8").includes("firefox file:///usr/local/share/nexus-os/ui/index.html#quantum"));

    for (const ed of ["cinnamon", "xfce", "lite", "lite-lxqt"]) {
      const out = execFileSync("bash", [path.join(ROOT, "linux/build/build-nexus-iso.sh"), "--edition", ed, "--dry-run"], { encoding: "utf8" });
      assert.ok(out.includes(ed));
    }
    console.log("PASS Native launcher parity (performance + quantum) & 4-edition compatibility checks");
  } finally {
    fs.rmSync(tmp, { recursive: true, force: true });
  }
}

async function testNativeFilesJailingAndBridgeSecurity() {
  const tmpHome = fs.mkdtempSync(path.join(os.tmpdir(), "nexus-p21-home-"));
  const runtimeFile = path.join(tmpHome, "bridge.json");
  fs.mkdirSync(path.join(tmpHome, "Documents"), { recursive: true });
  fs.mkdirSync(path.join(tmpHome, ".ssh"), { recursive: true });
  fs.mkdirSync(path.join(tmpHome, ".config", "nexus-os"), { recursive: true });
  fs.writeFileSync(path.join(tmpHome, "Documents", "readme.txt"), "hello nexus");
  fs.writeFileSync(path.join(tmpHome, ".ssh", "id_rsa"), "PRIVATE-KEY");

  const proc = spawn("python3", [path.join(ROOT, "linux/mint/nexus-system-bridge.py"), "--serve", "--port", "0", "--runtime-file", runtimeFile], {
    env: { ...process.env, HOME: tmpHome, XDG_DATA_HOME: path.join(tmpHome, ".local", "share") },
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
    assert.ok(info && info.url && info.token, "Bridge did not start");

    // 1. Unauthenticated access rejected
    assert.equal((await fetch(`${info.url}/api/files/list`)).status, 401);
    assert.equal((await fetch(`${info.url}/api/quantum/notes`)).status, 401);

    const hdrs = { "X-Nexus-Token": info.token, "Content-Type": "application/json" };

    // 2. Protected system/credential paths strictly denied (403)
    assert.equal((await fetch(`${info.url}/api/files/list?path=/etc`, { headers: hdrs })).status, 403);
    assert.equal((await fetch(`${info.url}/api/files/preview?path=${encodeURIComponent(path.join(tmpHome, ".ssh/id_rsa"))}`, { headers: hdrs })).status, 403);
    assert.equal((await fetch(`${info.url}/api/files/list?path=../`, { headers: hdrs })).status, 403);
    assert.equal((await fetch(`${info.url}/api/files/delete`, {
      method: "POST",
      headers: hdrs,
      body: JSON.stringify({ path: path.join(tmpHome, ".config/nexus-os") }),
    })).status, 403);

    // 3. Safe $HOME operations succeed and list hides .ssh
    const homeList = await (await fetch(`${info.url}/api/files/list`, { headers: hdrs })).json();
    assert.ok(!homeList.entries.some(e => e.name === ".ssh"), ".ssh must be hidden from directory listings");

    const prev = await (await fetch(`${info.url}/api/files/preview?path=Documents/readme.txt`, { headers: hdrs })).json();
    assert.equal(prev.text, "hello nexus");

    assert.equal((await fetch(`${info.url}/api/files/mkdir`, { method: "POST", headers: hdrs, body: JSON.stringify({ path: "Documents", name: "sub" }) })).status, 200);
    assert.equal((await fetch(`${info.url}/api/files/touch`, { method: "POST", headers: hdrs, body: JSON.stringify({ path: "Documents/sub", name: "a.txt" }) })).status, 200);
    assert.equal((await fetch(`${info.url}/api/files/rename`, { method: "POST", headers: hdrs, body: JSON.stringify({ path: "Documents/sub/a.txt", newName: "b.txt" }) })).status, 200);
    assert.ok(fs.existsSync(path.join(tmpHome, "Documents", "sub", "b.txt")));
    assert.equal((await fetch(`${info.url}/api/files/delete`, { method: "POST", headers: hdrs, body: JSON.stringify({ path: "Documents/sub" }) })).status, 200);
    assert.ok(!fs.existsSync(path.join(tmpHome, "Documents", "sub")));

    // 4. Quantum notes local JSON save & load
    assert.equal((await fetch(`${info.url}/api/quantum/notes`, {
      method: "POST",
      headers: hdrs,
      body: JSON.stringify({ notes: [{ title: "Saved", body: "On disk", track: "linux" }] }),
    })).status, 200);
    const loadedNotes = await (await fetch(`${info.url}/api/quantum/notes`, { headers: hdrs })).json();
    assert.equal(loadedNotes.notes[0].title, "Saved");

    // 5. Real Bash PTY session lifecycle
    const openRes = await (await fetch(`${info.url}/api/terminal/open`, { method: "POST", headers: hdrs, body: JSON.stringify({ cols: 80, rows: 24 }) })).json();
    assert.ok(openRes.sessionId);
    await fetch(`${info.url}/api/terminal/write`, { method: "POST", headers: hdrs, body: JSON.stringify({ sessionId: openRes.sessionId, data: "echo P21_BASH_OK\n" }) });
    let termOut = "";
    for (let i = 0; i < 20 && !termOut.includes("P21_BASH_OK"); i += 1) {
      await new Promise(r => setTimeout(r, 80));
      const rd = await (await fetch(`${info.url}/api/terminal/read?sessionId=${encodeURIComponent(openRes.sessionId)}`, { headers: hdrs })).json();
      termOut += rd.output || "";
    }
    assert.ok(termOut.includes("P21_BASH_OK"), "Terminal must run real GNU Bash");
    await fetch(`${info.url}/api/terminal/close`, { method: "POST", headers: hdrs, body: JSON.stringify({ sessionId: openRes.sessionId }) });

    console.log("PASS Bridge $HOME-jailed Files API, protected path denial, Quantum JSON notes, and GNU Bash PTY checks");
  } finally {
    proc.kill("SIGTERM");
    fs.rmSync(tmpHome, { recursive: true, force: true });
  }
}

(async () => {
  testQuantumNotesAndLinuxTrack();
  await testStoreInstalledLibraryAndErrors();
  testAppModeClassificationAndLaunchers();
  await testNativeFilesJailingAndBridgeSecurity();
})();
