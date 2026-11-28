#!/usr/bin/env node
// Phase 18 integration, reliability, bridge wiring, async Promise UI, and cross-edition checks.
"use strict";
const assert = require("node:assert/strict");
const fs = require("node:fs");
const vm = require("node:vm");
const { execFileSync } = require("node:child_process");

function makeNode(tag = "div") {
  const listeners = new Map();
  const children = [];
  const attrs = {};
  const classSet = new Set();
  const el = {
    tagName: tag.toUpperCase(),
    id: "",
    type: "",
    value: "",
    placeholder: "",
    disabled: false,
    textContent: "",
    dataset: {},
    style: {},
    children,
    setAttribute(k, v) { attrs[k] = String(v); },
    getAttribute(k) { return Object.prototype.hasOwnProperty.call(attrs, k) ? attrs[k] : null; },
    classList: {
      add: (...c) => c.forEach(x => classSet.add(x)),
      remove: (...c) => c.forEach(x => classSet.delete(x)),
      toggle: (c, f) => {
        if (f === undefined) {
          if (classSet.has(c)) classSet.delete(c);
          else classSet.add(c);
        } else if (f) classSet.add(c);
        else classSet.delete(c);
      },
      contains: c => classSet.has(c)
    },
    set className(v) {
      classSet.clear();
      String(v || "").split(/\s+/).filter(Boolean).forEach(c => classSet.add(c));
    },
    get className() {
      return [...classSet].join(" ");
    },
    append(...nodes) {
      for (const n of nodes) {
        if (n && typeof n === "object") {
          n.parentNode = el;
          children.push(n);
        }
      }
    },
    replaceChildren(...nodes) {
      children.length = 0;
      el.append(...nodes);
    },
    remove() {
      if (el.parentNode && Array.isArray(el.parentNode.children)) {
        const idx = el.parentNode.children.indexOf(el);
        if (idx >= 0) el.parentNode.children.splice(idx, 1);
      }
    },
    addEventListener(type, fn) {
      if (!listeners.has(type)) listeners.set(type, new Set());
      listeners.get(type).add(fn);
    },
    removeEventListener(type, fn) {
      listeners.get(type)?.delete(fn);
    },
    querySelector(sel) {
      return el.querySelectorAll(sel)[0] || null;
    },
    querySelectorAll(sel) {
      const out = [];
      const visit = node => {
        for (const ch of node.children || []) {
          if (matches(ch, sel)) out.push(ch);
          visit(ch);
        }
      };
      visit(el);
      return out;
    },
    closest(sel) {
      let cur = el;
      while (cur) {
        if (matches(cur, sel)) return cur;
        cur = cur.parentNode || null;
      }
      return null;
    },
    click() {
      const event = { target: el, preventDefault() {} };
      let cur = el;
      while (cur) {
        for (const fn of listeners.get("click") || []) fn(event);
        cur = cur.parentNode || null;
      }
    }
  };
  return el;
}

function matches(node, sel) {
  if (!node || typeof node !== "object") return false;
  if (sel.startsWith("#")) return node.id === sel.slice(1);
  if (sel.startsWith(".")) return node.classList?.contains(sel.slice(1));
  const attrMatch = sel.match(/^\[([a-z0-9-]+)(?:="([^"]*)")?\]$/i);
  if (attrMatch) {
    const raw = attrMatch[1];
    const val = attrMatch[2];
    const camel = raw.replace(/^data-/, "").replace(/-([a-z])/g, (_, ch) => ch.toUpperCase());
    const actual = raw.startsWith("data-") ? node.dataset?.[camel] : node.getAttribute?.(raw);
    return val === undefined ? actual !== undefined && actual !== null : String(actual) === val;
  }
  return false;
}

function collectText(node) {
  return [node.textContent || "", ...(node.children || []).map(collectText)].join(" ");
}

async function run() {
  // 1. Native Bridge full-service registration & authenticated requests
  {
    const fetchCalls = [];
    const context = {
      fetch: async (url, init = {}) => {
        fetchCalls.push({ url, init });
        return {
          ok: true,
          status: 200,
          async json() {
            if (url.includes("/api/store/info")) {
              return { id: "gamemode", source: "apt", version: "1.8.1", installed_size_kb: 2048, dependencies: ["libc6", "libsystemd0"] };
            }
            if (url.includes("/api/security/permissions")) {
              return { ok: true, app_id: "org.mozilla.firefox", permissions: "shared=network;ipc;" };
            }
            return { ok: true };
          }
        };
      },
      window: {
        __NEXUS_BRIDGE__: { url: "http://127.0.0.1:47821", token: "secret-tok" }
      },
      console
    };
    vm.createContext(context);
    vm.runInContext(fs.readFileSync("apps/native-services.js", "utf8"), context);
    const ns = context.window.NexusNativeServices;
    for (const id of [
      "control-centre", "personalisation", "packages", "privacy-security",
      "gaming", "installer", "telemetry", "terminal",
      "display", "sound", "network", "bluetooth", "power", "accounts", "files"
    ]) {
      assert.equal(ns.status(id).available, true, `Bridge should register ${id}`);
    }
    const info = await ns.call("packages", "info", "apt", "gamemode");
    assert.equal(info.id, "gamemode");
    assert.deepEqual(info.dependencies, ["libc6", "libsystemd0"]);
    const fp = await ns.call("privacy-security", "permissions", "org.mozilla.firefox");
    assert.match(fp.permissions, /shared=network/);
    assert.equal(fetchCalls[0].init.headers["X-Nexus-Token"], "secret-tok");
  }

  // 2. Gaming Hub handles async Promise status() cleanly
  {
    let appDef = null;
    const context = {
      window: {
        NexusAppRegistry: { register(def) { appDef = def; } },
        NexusNativeServices: {
          status: id => ({ available: id === "gaming" }),
          call: (_id, method) => {
            if (method === "status") {
              return Promise.resolve({
                steam: { installed: true, installed_games: [{ appid: 440, name: "Team Fortress 2" }], proton_versions: ["Proton 9.0"] },
                launchers: { lutris: { installed: true }, heroic: { installed: false } },
                performance: { gaming_mode: "enabled", gamemode_installed: true, mangohud_installed: false },
                capabilities: { apt_available: true, flatpak_available: true },
                graphics: { gpus: [], vulkan: "available", software_rendering: false },
                hardware: { cpu: "Test CPU", ram_total_mib: 8192, ram_available_mib: 6144, storage_available_gib: 120 },
                controllers: []
              });
            }
            return Promise.resolve({ ok: true, message: "ok" });
          }
        }
      },
      document: {
        createElement: tag => makeNode(tag)
      }
    };
    vm.createContext(context);
    vm.runInContext(fs.readFileSync("apps/gaming.js", "utf8"), context);
    const root = makeNode("div");
    const panel = makeNode("div"); panel.id = "gamingPanel";
    const statusEl = makeNode("p"); statusEl.id = "gamingStatus";
    root.append(panel, statusEl);
    appDef.mount(root, {});
    await new Promise(r => setTimeout(r, 15));
    const text = collectText(panel);
    assert.ok(text.includes("Team Fortress 2"), "Async Gaming Hub should render Steam games once resolved");
  }

  // 3. Settings Privacy & Security handles async Promise overview() + Flatpak permissions UI
  {
    let enhancement = null;
    const called = [];
    const context = {
      window: {
        NexusAppRegistry: { registerSettingsEnhancement(fn) { enhancement = fn; } },
        NexusNativeServices: {
          status: id => ({ available: id === "privacy-security" }),
          call: (_id, method, ...args) => {
            called.push([method, ...args]);
            if (method === "overview") {
              return Promise.resolve({
                firewall: { status: "enabled" },
                security_updates: { status: "enabled" },
                disk_encryption: { status: "disabled" },
                secure_boot: { status: "enabled" },
                devices: { status: "enabled" },
                startup_apps: [{ name: "Bridge", scope: "user", enabled: true }],
                services: { "nexus-system-bridge": "active", ufw: "active" },
                listening_ports: { loopback: 1, external: 0 }
              });
            }
            if (method === "permissions") {
              return Promise.resolve({ permissions: "shared=network;ipc;" });
            }
            return Promise.resolve({ ok: true, message: "updated" });
          }
        }
      },
      document: {
        createElement: tag => makeNode(tag),
        createTextNode: text => ({ nodeType: 3, textContent: String(text) })
      }
    };
    vm.createContext(context);
    vm.runInContext(fs.readFileSync("apps/settings-sections.js", "utf8"), context);
    const sidebar = makeNode("div");
    const main = makeNode("div");
    enhancement({
      querySelector(sel) {
        if (sel === ".settings-sidebar") return sidebar;
        if (sel === ".settings-main") return main;
        return null;
      }
    });
    await new Promise(r => setTimeout(r, 15));
    const privacyPage = main.children.find(p => p.dataset.settingsPage === "privacy");
    const text = collectText(privacyPage);
    assert.ok(text.includes("Enabled"), "Async Privacy overview should resolve Enabled state");
    assert.ok(text.includes("Inspect Flatpak"), "Privacy should include Flatpak permission inspector");
    const fpInput = privacyPage.querySelectorAll("input")[0] || privacyPage.children[4].children[3].children[0];
    fpInput.value = "org.mozilla.firefox";
    const inspectBtn = privacyPage.children[4].children[3].children[1];
    inspectBtn.click();
    await new Promise(r => setTimeout(r, 15));
    assert.ok(called.some(c => c[0] === "permissions" && c[1] === "org.mozilla.firefox"));
  }

  // 4. Openbox menu.xml validity + power actions (Log Out, Reboot, Shut Down)
  {
    const menuXml = fs.readFileSync("linux/lite/openbox/menu.xml", "utf8");
    assert.ok(menuXml.includes("Log Out"));
    assert.ok(menuXml.includes("systemctl reboot"));
    assert.ok(menuXml.includes("systemctl poweroff"));
    execFileSync("python3", ["-c", "import xml.etree.ElementTree as ET; ET.parse('linux/lite/openbox/menu.xml')"]);
  }

  // 5. First-boot script forwards --theme and --appearance across all 4 editions
  {
    for (const [de, needle] of [
      ["X-Cinnamon", "NEXUS-Arctic"],
      ["XFCE", "arctic"],
      ["LXQt", "arctic"],
      ["Openbox", "arctic"]
    ]) {
      const out = execFileSync(
        "bash",
        ["linux/mint/nexus-firstboot.sh", "--dry-run", "--theme-preset", "arctic", "--theme", "light", "--check-updates"],
        { env: { ...process.env, XDG_CURRENT_DESKTOP: de }, encoding: "utf8" }
      );
      assert.ok(out.includes(needle), `Expected '${needle}' in first-boot output for ${de}, got:\n${out}`);
      assert.ok(out.includes("theme=light"), `Expected 'theme=light' in first-boot output for ${de}, got:\n${out}`);
      assert.ok(out.includes("nexus-recovery --diagnose"), "Expected recovery guidance in first-boot output");
    }
  }

  console.log("PASS Phase 18 integration, bridge, async UI, Openbox menu, and first-boot parity tests");
}

run().catch(err => {
  console.error(err);
  process.exit(1);
});
