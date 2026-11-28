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
    disabled: false,
    tabIndex: 0,
    title: "",
    textContent: "",
    dataset: {},
    style: {},
    children,
    get lastChild() {
      return children[children.length - 1] || null;
    },
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
    remove() {
      if (el.parentNode && Array.isArray(el.parentNode.children)) {
        el.parentNode.children = el.parentNode.children.filter(c => c !== el);
      }
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

function makePeExe(machineCode) {
  const b = new Uint8Array(128);
  b[0] = 0x4d; b[1] = 0x5a; // MZ
  b[0x3c] = 0x40; // PE offset 64
  b[0x40] = 0x50; b[0x41] = 0x45; // PE\0\0
  b[0x44] = machineCode & 0xff;
  b[0x45] = (machineCode >> 8) & 0xff;
  return b;
}

function makeElf(eMachine, appImage = false) {
  const b = new Uint8Array(64);
  b[0] = 0x7f; b[1] = 0x45; b[2] = 0x4c; b[3] = 0x46; // \x7fELF
  if (appImage) { b[8] = 0x41; b[9] = 0x49; b[10] = 0x02; }
  b[18] = eMachine & 0xff;
  b[19] = (eMachine >> 8) & 0xff;
  return b;
}

function testClientClassifierAndUI() {
  let registered = null;
  const ctx = {
    window: {
      NexusAppRegistry: { register: app => { registered = app; } },
      NexusNativeServices: { status: () => ({ available: false }) },
      confirm: () => true,
    },
    document: { createElement: t => makeEl(t) },
  };
  vm.runInNewContext(fs.readFileSync(path.join(ROOT, "apps/compatibility.js"), "utf8"), ctx);
  const clf = ctx.window.NexusCompatibilityClassifier;
  assert.ok(registered && registered.id === "compatibility");

  const fakeHost = {
    host: { machine: "x86_64", dpkg_arch: "amd64", low_ram: false },
    ecosystems: {
      linux: { apt: true, flatpak: true, appimage_fuse2: true },
      windows: { wine_installed: true, proton_versions: ["Proton 9.0"] },
      android: { waydroid_installed: false },
    },
  };

  // PE64 + PE32 + ARM64 Windows
  const exe64 = clf.classifyBuffer(makePeExe(0x8664), "app.exe", fakeHost);
  assert.equal(exe64.source_os, "Windows");
  assert.equal(exe64.status, "Compatible");
  assert.equal(exe64.executed, false);

  const exe32 = clf.classifyBuffer(makePeExe(0x014c), "legacy32.exe", fakeHost);
  assert.ok(exe32.target_arch.includes("i386"));
  assert.ok(exe32.security_notes.some(n => n.includes("wine32")));

  const exeArm = clf.classifyBuffer(makePeExe(0xaa64), "winarm.exe", fakeHost);
  assert.equal(exeArm.status, "Unsupported");

  // AppImage x86_64 vs aarch64
  const appImgOk = clf.classifyBuffer(makeElf(62, true), "tool.AppImage", fakeHost);
  assert.equal(appImgOk.source_os, "Linux");
  assert.equal(appImgOk.status, "Compatible");

  const appImgWrongArch = clf.classifyBuffer(makeElf(183, true), "armtool.AppImage", fakeHost);
  assert.equal(appImgWrongArch.status, "Unsupported");

  // Apple DMG / PKG / IPA strictly Unsupported
  const dmgBytes = new Uint8Array(64);
  dmgBytes.set(Buffer.from("koly"), 40);
  const dmg = clf.classifyBuffer(dmgBytes, "Safari.dmg", fakeHost);
  assert.equal(dmg.source_os, "Apple (macOS)");
  assert.equal(dmg.status, "Unsupported");

  const pkgBytes = Buffer.from("xar!\x00\x1c");
  const pkg = clf.classifyBuffer(pkgBytes, "Xcode.pkg", fakeHost);
  assert.equal(pkg.status, "Unsupported");

  // Unknown format
  const unk = clf.classifyBuffer(Buffer.from("RANDOM_BYTES"), "mystery.bin", fakeHost);
  assert.equal(unk.status, "Not tested");

  console.log("PASS Client magic-byte format classifier (Windows PE, Linux AppImage/ELF, Apple DMG/PKG, Unknown)");
}

function testCliRealFixturesAndSecurity() {
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "nexus-p22-cli-"));
  try {
    // 1. Real host runtime & architecture detection
    const statusJson = JSON.parse(execFileSync("bash", [path.join(ROOT, "linux/mint/nexus-compat-cli.sh"), "status"], { encoding: "utf8" }));
    assert.ok(statusJson.host.machine);
    assert.equal(statusJson.ecosystems.apple.direct_execution_supported, false);
    assert.equal(statusJson.ecosystems.android.gms_included, false);

    // 2. Catalog Tested vs Estimated distinction
    const catJson = JSON.parse(execFileSync("bash", [path.join(ROOT, "linux/mint/nexus-compat-cli.sh"), "catalog"], { encoding: "utf8" }));
    assert.ok(catJson.entries.some(e => e.tested === "Tested"));
    assert.ok(catJson.entries.some(e => e.tested === "Estimated"));
    assert.ok(catJson.entries.some(e => e.source_os.startsWith("Apple") && e.status === "Unsupported"));

    // 3. Real .deb built via dpkg-deb on this Linux host
    const debRoot = path.join(tmp, "pkgroot");
    fs.mkdirSync(path.join(debRoot, "DEBIAN"), { recursive: true });
    fs.writeFileSync(path.join(debRoot, "DEBIAN", "control"), "Package: nexus-test-pkg\nVersion: 1.0.0\nArchitecture: all\nMaintainer: NEXUS Test <test@example.org>\nDescription: Phase 22 test package\n");
    const debPath = path.join(tmp, "nexus-test.deb");
    execFileSync("dpkg-deb", ["--build", debRoot, debPath]);
    const debInspect = JSON.parse(execFileSync("bash", [path.join(ROOT, "linux/mint/nexus-compat-cli.sh"), "inspect", debPath], { encoding: "utf8" }));
    assert.equal(debInspect.source_os, "Linux");
    assert.equal(debInspect.status, "Native");
    assert.equal(debInspect.target_arch, "all");
    assert.equal(debInspect.executed, false);

    // 4. Real ZIP-based Android APK fixtures (FOSS x86_64 vs ARM-only vs GMS Play Services)
    const mkApk = (name, files) => {
      const p = path.join(tmp, name);
      execFileSync("python3", ["-c", `
import zipfile, sys
with zipfile.ZipFile(sys.argv[1], "w") as z:
    for k, v in __import__("json").loads(sys.argv[2]).items():
        z.writestr(k, v)
`, p, JSON.stringify(files)]);
      return p;
    };

    const apkX86 = mkApk("foss.apk", { "AndroidManifest.xml": "manifest", "lib/x86_64/libapp.so": "ELF" });
    const apkX86Res = JSON.parse(execFileSync("bash", [path.join(ROOT, "linux/mint/nexus-compat-cli.sh"), "inspect", apkX86], { encoding: "utf8" }));
    assert.equal(apkX86Res.source_os, "Android");
    assert.equal(apkX86Res.executed, false);

    const apkArm = mkApk("armonly.apk", { "AndroidManifest.xml": "manifest", "lib/arm64-v8a/libapp.so": "ELF" });
    const apkArmRes = JSON.parse(execFileSync("bash", [path.join(ROOT, "linux/mint/nexus-compat-cli.sh"), "inspect", apkArm], { encoding: "utf8" }));
    assert.equal(apkArmRes.status, "Experimental");
    assert.ok(apkArmRes.missing_dependencies.some(d => d.includes("ARM-to-x86_64")));

    const apkGms = mkApk("banking.apk", { "AndroidManifest.xml": "uses com.google.android.gms", "lib/x86_64/libapp.so": "ELF" });
    const apkGmsRes = JSON.parse(execFileSync("bash", [path.join(ROOT, "linux/mint/nexus-compat-cli.sh"), "inspect", apkGms], { encoding: "utf8" }));
    assert.equal(apkGmsRes.status, "Unsupported");

    // 5. Real Windows PE + Apple IPA fixtures
    const exePath = path.join(tmp, "sample.exe");
    fs.writeFileSync(exePath, makePeExe(0x8664));
    const exeInspect = JSON.parse(execFileSync("bash", [path.join(ROOT, "linux/mint/nexus-compat-cli.sh"), "inspect", exePath], { encoding: "utf8" }));
    assert.equal(exeInspect.source_os, "Windows");
    assert.equal(exeInspect.executed, false);

    const ipaPath = mkApk("sample.ipa", { "Payload/Sample.app/Info.plist": "plist" });
    const ipaInspect = JSON.parse(execFileSync("bash", [path.join(ROOT, "linux/mint/nexus-compat-cli.sh"), "inspect", ipaPath], { encoding: "utf8" }));
    assert.equal(ipaInspect.source_os, "Apple (iOS / iPadOS)");
    assert.equal(ipaInspect.status, "Unsupported");

    // 6. Security: launch & install-runtime MUST refuse without --confirm; invalid Wine prefix slug rejected
    assert.throws(() => execFileSync("bash", [path.join(ROOT, "linux/mint/nexus-compat-cli.sh"), "launch", exePath], { stdio: "pipe" }));
    assert.throws(() => execFileSync("bash", [path.join(ROOT, "linux/mint/nexus-compat-cli.sh"), "install-runtime", "wine"], { stdio: "pipe" }));
    assert.throws(() => execFileSync("bash", [path.join(ROOT, "linux/mint/nexus-compat-cli.sh"), "prefix", "create", "../escape"], { stdio: "pipe" }));

    // Dry-run runtime install prints exact PolicyKit APT command without executing
    const dryWine = JSON.parse(execFileSync("bash", [path.join(ROOT, "linux/mint/nexus-compat-cli.sh"), "--dry-run", "install-runtime", "wine"], { encoding: "utf8" }));
    assert.equal(dryWine.dryRun, true);
    assert.ok(dryWine.command.includes("wine"));

    // 7. Four-edition compatibility: Lite manifests MUST NOT force wine/proton/waydroid
    for (const manifest of [
      "linux/lite/lite-packages.list",
      "linux/lite/manifests/lite-openbox-packages.list",
      "linux/lite/manifests/lite-lxqt-packages.list",
    ]) {
      const txt = fs.readFileSync(path.join(ROOT, manifest), "utf8");
      assert.ok(!/^(core|desktop|nexus):(wine|waydroid|steam)/m.test(txt), `${manifest} must never force Wine/Waydroid/Steam`);
    }

    console.log("PASS CLI real .deb/.exe/.apk/.ipa inspection, security confirmation guards, and 4-edition Lite exclusion checks");
  } finally {
    fs.rmSync(tmp, { recursive: true, force: true });
  }
}

async function testStoreIntegrationAndBridgeAuth() {
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
        status: id => ({ available: id === "compatibility" }),
        call: (id, method) => {
          if (id === "compatibility" && method === "status") {
            return Promise.resolve({
              ecosystems: {
                linux: { apt: true, flatpak: false },
                windows: { wine_installed: false, proton_versions: [] },
                android: { waydroid_installed: false },
              },
            });
          }
          return null;
        },
      },
      NexusAppRegistry: { register: app => { storeApp = app; } },
      confirm: () => true,
    },
    document: { createElement: t => makeEl(t) },
  };
  vm.runInNewContext(fs.readFileSync(path.join(ROOT, "apps/software-centre.js"), "utf8"), storeCtx);

  const page = makeEl("div"); page.id = "storePage";
  const search = makeEl("input"); search.id = "storeSearch";
  const title = makeEl("h2"); title.id = "storeViewTitle";
  const back = makeEl("button"); back.id = "storeBack";
  const message = makeEl("p"); message.id = "storeMessage";
  const appsBtn = makeEl("button"); appsBtn.dataset.storeView = "apps";
  const root = makeEl("div");
  root.append(page, search, title, back, message, appsBtn);

  storeApp.mount(root, { launchApp() {} });
  appsBtn.click();
  // Open details for Bottles (Windows) and Apple macOS entry
  const detailsButtons = root.querySelectorAll('[data-store-action="details"]');
  const bottlesBtn = detailsButtons.find(b => b.dataset.appId === "bottles");
  assert.ok(bottlesBtn, "Store must include Bottles Windows listing");
  bottlesBtn.click();
  await new Promise(r => setTimeout(r, 20));
  const bottlesText = collectText(page);
  assert.ok(bottlesText.includes("Cross-platform compatibility"));
  assert.ok(bottlesText.includes("Windows (.exe / .msi)"));
  assert.ok(bottlesText.includes("Not installed (optional runtime)"));

  appsBtn.click();
  const appleBtn = root.querySelectorAll('[data-store-action="details"]').find(b => b.dataset.appId === "apple-macos-ecosystem");
  assert.ok(appleBtn, "Store must include honest Apple macOS/iOS entry");
  appleBtn.click();
  await new Promise(r => setTimeout(r, 20));
  const appleText = collectText(page);
  assert.ok(appleText.includes("Unsupported on Linux"));

  // Test Bridge HTTP /api/compat/* security
  const tmpHome = fs.mkdtempSync(path.join(os.tmpdir(), "nexus-p22-bridge-"));
  const runtimeFile = path.join(tmpHome, "bridge.json");
  fs.mkdirSync(path.join(tmpHome, "Downloads"), { recursive: true });
  fs.writeFileSync(path.join(tmpHome, "Downloads", "winapp.exe"), makePeExe(0x8664));
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
    assert.ok(info && info.url && info.token);
    assert.equal((await fetch(`${info.url}/api/compat/status`)).status, 401);

    const hdrs = { "X-Nexus-Token": info.token, "Content-Type": "application/json" };
    assert.equal((await fetch(`${info.url}/api/compat/inspect?path=/etc/passwd`, { headers: hdrs })).status, 403);
    assert.equal((await fetch(`${info.url}/api/compat/launch`, { method: "POST", headers: hdrs, body: JSON.stringify({ path: "Downloads/winapp.exe", confirm: false }) })).status, 400);
    assert.equal((await fetch(`${info.url}/api/compat/runtime/install`, { method: "POST", headers: hdrs, body: JSON.stringify({ runtime: "wine", confirm: false }) })).status, 400);

    const insp = await (await fetch(`${info.url}/api/compat/inspect?path=Downloads/winapp.exe`, { headers: hdrs })).json();
    assert.equal(insp.source_os, "Windows");
    assert.equal(insp.executed, false);

    const pref = await (await fetch(`${info.url}/api/compat/prefix/create`, { method: "POST", headers: hdrs, body: JSON.stringify({ name: "work-apps" }) })).json();
    assert.equal(pref.ok, true);
    assert.ok(fs.existsSync(path.join(tmpHome, ".local", "share", "nexus-os", "wine-prefixes", "work-apps")));

    console.log("PASS Store cross-platform compatibility metadata & Bridge /api/compat/* auth/jailing checks");
  } finally {
    proc.kill("SIGTERM");
    fs.rmSync(tmpHome, { recursive: true, force: true });
  }
}

(async () => {
  testClientClassifierAndUI();
  testCliRealFixturesAndSecurity();
  await testStoreIntegrationAndBridgeAuth();
})();
