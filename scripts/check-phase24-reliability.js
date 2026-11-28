#!/usr/bin/env node
"use strict";

const assert = require("node:assert/strict");
const { execFileSync } = require("node:child_process");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const vm = require("node:vm");

const ROOT = path.resolve(__dirname, "..");

function makeElement(tagName = "div") {
  const listeners = new Map();
  const classSet = new Set();
  const children = [];
  const el = {
    tagName: tagName.toUpperCase(),
    id: "",
    className: "",
    textContent: "",
    innerHTML: "",
    value: "",
    disabled: false,
    scrollTop: 0,
    scrollHeight: 0,
    style: {},
    dataset: {},
    children,
    classList: {
      add: (...cls) => cls.forEach(c => classSet.add(c)),
      remove: (...cls) => cls.forEach(c => classSet.delete(c)),
      toggle: (c, force) => {
        if (force === undefined) {
          if (classSet.has(c)) classSet.delete(c);
          else classSet.add(c);
        } else if (force) classSet.add(c);
        else classSet.delete(c);
      },
      contains: c => classSet.has(c),
    },
    addEventListener: (ev, fn) => {
      if (!listeners.has(ev)) listeners.set(ev, []);
      listeners.get(ev).push(fn);
    },
    removeEventListener: (ev, fn) => {
      if (!listeners.has(ev)) return;
      listeners.set(ev, listeners.get(ev).filter(f => f !== fn));
    },
    dispatch: async (ev, eventObj = {}) => {
      const fns = listeners.get(ev) || [];
      for (const fn of fns) {
        await fn({ preventDefault() {}, target: el, ...eventObj });
      }
    },
    append: (...nodes) => children.push(...nodes),
    appendChild: node => {
      children.push(node);
      return node;
    },
    querySelector: sel => {
      if (sel === "#terminalOut") return el._out;
      if (sel === "#terminalInput") return el._inp;
      if (sel === "#terminalSend") return el._send;
      if (sel === "#terminalInterrupt") return el._interrupt;
      if (sel === ".terminal-mode") return el._mode;
      if (sel === "#terminalStatus") return el._status;
      return null;
    },
    querySelectorAll: () => [],
    focus: () => {},
  };
  return el;
}

async function testBridgeTerminalAsyncPty() {
  const fetchCalls = [];
  let readPollCount = 0;

  const sandbox = {
    window: {
      __NEXUS_BRIDGE__: {
        url: "http://127.0.0.1:49999",
        token: "test-token",
      },
    },
    fetch: async (url, init = {}) => {
      fetchCalls.push({ url, method: init.method || "GET", body: init.body ? JSON.parse(init.body) : null });
      if (url.endsWith("/api/terminal/open")) {
        return { ok: true, json: async () => ({ sessionId: "pty-42" }) };
      }
      if (url.includes("/api/terminal/read")) {
        readPollCount += 1;
        if (readPollCount === 1) {
          return { ok: true, json: async () => ({ output: "NEXUS_BRIDGE_PTY_OK\n", exitCode: null }) };
        }
        return { ok: true, json: async () => ({ output: "", exitCode: null }) };
      }
      if (url.endsWith("/api/terminal/write")) {
        return { ok: true, json: async () => ({ ok: true }) };
      }
      if (url.endsWith("/api/terminal/close")) {
        return { ok: true, json: async () => ({ ok: true }) };
      }
      throw new Error(`Unexpected fetch: ${url}`);
    },
    AbortController,
    setTimeout,
    clearTimeout,
    setInterval,
    clearInterval,
    URLSearchParams,
    document: {
      createElement: tag => makeElement(tag),
    },
  };
  sandbox.window.window = sandbox.window;
  sandbox.window.document = sandbox.document;
  vm.createContext(sandbox);

  vm.runInContext(fs.readFileSync(path.join(ROOT, "apps/app-registry.js"), "utf8"), sandbox);
  vm.runInContext(fs.readFileSync(path.join(ROOT, "apps/native-services.js"), "utf8"), sandbox);
  vm.runInContext(fs.readFileSync(path.join(ROOT, "apps/terminal.js"), "utf8"), sandbox);

  const root = makeElement("div");
  root._out = makeElement("div");
  root._inp = makeElement("input");
  root._send = makeElement("button");
  root._interrupt = makeElement("button");
  root._mode = makeElement("span");
  root._status = makeElement("div");

  sandbox.window.NexusAppRegistry.mountApp("terminal", root, {});
  // Allow async openSession + first read poll to resolve
  await new Promise(resolve => setTimeout(resolve, 220));

  const outTexts = root._out.children.map(c => c.textContent);
  assert(
    outTexts.some(t => t.includes("NEXUS_BRIDGE_PTY_OK")),
    `Expected async bridge PTY output in terminal, got: ${JSON.stringify(outTexts)}`
  );
  assert(
    !outTexts.some(t => t.includes("did not return a session ID")),
    `Bridge terminal must not fail with sync Promise bug: ${JSON.stringify(outTexts)}`
  );

  root._inp.value = "uname -a";
  await root._inp.dispatch("keydown", { key: "Enter" });
  assert(
    fetchCalls.some(c => c.url.endsWith("/api/terminal/write") && c.body?.sessionId === "pty-42" && c.body?.data === "uname -a\n"),
    "Expected terminal write request for async bridge PTY session"
  );

  sandbox.window.NexusAppRegistry.unmountRoot(root);
  await new Promise(resolve => setTimeout(resolve, 40));
  assert(
    fetchCalls.some(c => c.url.endsWith("/api/terminal/close") && c.body?.sessionId === "pty-42"),
    "Expected closeSession to POST /api/terminal/close"
  );
  console.log("PASS bridge async PTY terminal open, polling output, write, and clean close");
}

function testBashAndConfigFixes() {
  // 1. Openbox menu & autostart
  const menuXml = fs.readFileSync(path.join(ROOT, "linux/lite/openbox/menu.xml"), "utf8");
  assert(
    menuXml.includes("<command>nexus-installer-launcher --launch</command>"),
    "Openbox menu must invoke nexus-installer-launcher --launch"
  );
  const autostart = fs.readFileSync(path.join(ROOT, "linux/lite/openbox/autostart"), "utf8");
  assert(
    autostart.includes("/usr/local/bin/nexus-firstboot --autostart"),
    "Openbox autostart must invoke nexus-firstboot --autostart"
  );

  // 2. Terminal=true desktop files pause before exit and follow XDG Exec quoting rules
  for (const df of [
    "linux/branding/applications/nexus-hw-diagnostics.desktop",
    "linux/branding/applications/nexus-recovery.desktop",
    "linux/branding/applications/nexus-security-audit.desktop",
  ]) {
    const content = fs.readFileSync(path.join(ROOT, df), "utf8");
    assert(content.includes("read -r _"), `${df} must wait for user input before closing terminal`);
    const execLine = content.split("\n").find(l => l.startsWith("Exec=")) || "";
    assert(!execLine.includes("'"), `${df} Exec= must use XDG double quotes instead of unescaped single quotes`);
    assert(!execLine.includes("\\n"), `${df} Exec= must not contain raw \\n escape sequences`);
  }

  // 3. app.js hash launch support
  const appJs = fs.readFileSync(path.join(ROOT, "app.js"), "utf8");
  assert(appJs.includes("openAppFromHash") && appJs.includes("hashchange"), "app.js must support #appId hash routing");

  // 4. Temp-home functional tests for apply-nexus-lite, performance, gaming, cinnamon, wallpaper, control-centre
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "nexus-p24-"));
  try {
    const homeDir = path.join(tmp, "home");
    const cfgDir = path.join(tmp, "cfg");
    const cacheDir = path.join(tmp, "cache");
    const dataDir = path.join(tmp, "data");
    fs.mkdirSync(homeDir, { recursive: true });
    fs.mkdirSync(cfgDir, { recursive: true });
    fs.mkdirSync(cacheDir, { recursive: true });
    fs.mkdirSync(dataDir, { recursive: true });

    const env = {
      ...process.env,
      HOME: homeDir,
      XDG_CONFIG_HOME: cfgDir,
      XDG_CACHE_HOME: cacheDir,
      XDG_DATA_HOME: dataDir,
      XDG_CURRENT_DESKTOP: "LXQt",
      DESKTOP_SESSION: "lxqt",
    };

    // Lite Openbox --appearance light maps to arctic & writes appearance=light
    execFileSync("bash", [path.join(ROOT, "linux/lite/apply-nexus-lite.sh"), "--profile", "lite-1g", "--appearance", "light"], { env });
    const liteProfile = fs.readFileSync(path.join(cfgDir, "nexus-os", "lite-profile"), "utf8");
    assert(liteProfile.includes("theme=arctic"), `Expected theme=arctic for --appearance light, got:\n${liteProfile}`);
    assert(liteProfile.includes("appearance=light"), `Expected appearance=light in lite-profile, got:\n${liteProfile}`);

    // Performance & Gaming toggles preserve saved LXQt theme/accent/appearance
    execFileSync(
      "bash",
      [path.join(ROOT, "linux/lite/scripts/apply-nexus-lite-lxqt.sh"), "--profile", "lite-1g", "--theme", "solar", "--accent", "#ffad7a", "--appearance", "dark"],
      { env }
    );
    execFileSync("bash", [path.join(ROOT, "linux/mint/nexus-performance-cli.sh"), "low-resource", "enable"], { env });
    let lxqtProfile = fs.readFileSync(path.join(cfgDir, "nexus-os", "lite-profile"), "utf8");
    assert(lxqtProfile.includes("profile=lite-512"), "Low-resource enable must set lite-512");
    assert(lxqtProfile.includes("theme=solar"), `Low-resource enable must preserve theme=solar, got:\n${lxqtProfile}`);
    assert(lxqtProfile.includes("accent=#ffad7a"), `Low-resource enable must preserve accent, got:\n${lxqtProfile}`);

    execFileSync("bash", [path.join(ROOT, "linux/mint/nexus-gaming-cli.sh"), "gaming-mode", "enable"], { env });
    lxqtProfile = fs.readFileSync(path.join(cfgDir, "nexus-os", "lite-profile"), "utf8");
    assert(lxqtProfile.includes("profile=lite-512"), "Gaming mode enable on LXQt must use lite-512");
    assert(lxqtProfile.includes("theme=solar"), `Gaming mode enable must preserve theme=solar, got:\n${lxqtProfile}`);

    execFileSync("bash", [path.join(ROOT, "linux/mint/nexus-gaming-cli.sh"), "gaming-mode", "disable"], { env });
    lxqtProfile = fs.readFileSync(path.join(cfgDir, "nexus-os", "lite-profile"), "utf8");
    assert(lxqtProfile.includes("profile=lite-1g") && lxqtProfile.includes("theme=solar"), "Gaming mode disable must restore lite-1g while keeping theme");

    // Cinnamon local wallpaper updates wallpaper.conf and validates magic bytes on remote downloads
    const stubBin = path.join(tmp, "bin");
    fs.mkdirSync(stubBin, { recursive: true });
    fs.writeFileSync(path.join(stubBin, "gsettings"), "#!/usr/bin/env bash\nexit 0\n");
    fs.chmodSync(path.join(stubBin, "gsettings"), 0o755);
    const sampleWp = path.join(tmp, "sample.png");
    fs.writeFileSync(sampleWp, Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]));
    execFileSync("bash", [path.join(ROOT, "linux/cinnamon/apply-nexus-cinnamon.sh"), "--wallpaper-url", sampleWp, "--wallpaper-fit", "scaled"], {
      env: { ...env, PATH: `${stubBin}:${process.env.PATH}` },
    });
    const wpConf = fs.readFileSync(path.join(cfgDir, "nexus-os", "wallpaper.conf"), "utf8");
    assert(wpConf.includes(`WALLPAPER_PATH=${fs.realpathSync(sampleWp)}`) && wpConf.includes("WALLPAPER_FIT=scaled"));

    // Edition detection fallback in wallpaper & control-centre CLIs
    const wpCli = fs.readFileSync(path.join(ROOT, "linux/mint/nexus-wallpaper-cli.sh"), "utf8");
    const ccCli = fs.readFileSync(path.join(ROOT, "linux/mint/nexus-control-centre-cli.sh"), "utf8");
    assert(wpCli.includes("/etc/nexus-os-release") && ccCli.includes("/etc/nexus-os-release"), "Edition detection must read /etc/nexus-os-release");

    // Provisioners stage UI bundle and guest provisioner records NEXUS_EDITION
    for (const prov of [
      "linux/mint/provision-nexus-guest.sh",
      "linux/lite/provision-nexus-lite.sh",
      "linux/lite/scripts/provision-nexus-lite-lxqt.sh",
    ]) {
      const txt = fs.readFileSync(path.join(ROOT, prov), "utf8");
      assert(txt.includes("/ui/index.html") || txt.includes("$share_dir/ui/index.html"), `${prov} must stage offline UI bundle`);
    }
    const guestProv = fs.readFileSync(path.join(ROOT, "linux/mint/provision-nexus-guest.sh"), "utf8");
    assert(guestProv.includes('NEXUS_EDITION="$detected_de"'), "provision-nexus-guest.sh must write NEXUS_EDITION");

    // Quantum launcher fails cleanly when no browser is present
    const emptyBin = path.join(tmp, "empty-bin");
    fs.mkdirSync(emptyBin, { recursive: true });
    let quantumFailed = false;
    try {
      execFileSync("/bin/bash", [path.join(ROOT, "linux/branding/nexus-launch-app.sh"), "quantum"], {
        env: { PATH: emptyBin, NEXUS_OFFLINE_UI: path.join(ROOT, "index.html") },
        stdio: "pipe",
      });
    } catch (err) {
      quantumFailed = true;
      assert(err.stderr.toString("utf8").includes("no supported web browser"));
    }
    assert(quantumFailed, "Quantum launcher must fail cleanly when no browser is in PATH");
  } finally {
    fs.rmSync(tmp, { recursive: true, force: true });
  }

  console.log("PASS Phase 24 bash, Openbox, Cinnamon, Lite, provisioner, and launcher reliability checks");
}

(async () => {
  await testBridgeTerminalAsyncPty();
  testBashAndConfigFixes();
})();
