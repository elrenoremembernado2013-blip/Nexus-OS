#!/usr/bin/env node
// Regression tests for Phase 8 NEXUS Welcome First-Boot wizard & Ubiquity Installer guide.
"use strict";
const assert = require("node:assert/strict");
const fs = require("node:fs");
const vm = require("node:vm");

function makeNode(tag = "div") {
  const listeners = new Map();
  const children = [];
  const classSet = new Set();
  const el = {
    tagName: tag.toUpperCase(),
    id: "",
    type: "",
    checked: false,
    disabled: false,
    textContent: "",
    style: { cssText: "" },
    dataset: {},
    children,
    classList: {
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
    addEventListener(type, fn) {
      if (!listeners.has(type)) listeners.set(type, new Set());
      listeners.get(type).add(fn);
    },
    removeEventListener(type, fn) {
      listeners.get(type)?.delete(fn);
    },
    closest(sel) {
      let cur = el;
      while (cur) {
        if (matches(cur, sel)) return cur;
        cur = cur.parentNode || null;
      }
      return null;
    },
    dispatch(type, event = {}) {
      for (const fn of listeners.get(type) || []) fn({ target: el, ...event });
    }
  };
  return el;
}

function matches(el, sel) {
  if (!el || !sel) return false;
  if (sel.startsWith("[") && sel.endsWith("]")) {
    const key = sel.slice(1, -1).replace(/^data-/, "").replace(/-([a-z])/g, (_, c) => c.toUpperCase());
    return el.dataset && Object.prototype.hasOwnProperty.call(el.dataset, key);
  }
  return false;
}

function findById(node, id) {
  if (!node || typeof node !== "object") return null;
  if (node.id === id) return node;
  for (const child of node.children || []) {
    const hit = findById(child, id);
    if (hit) return hit;
  }
  return null;
}

function collectText(node) {
  return [node.textContent || "", ...(node.children || []).map(collectText)].join(" ");
}

function loadWelcome(adapter) {
  let registered = null;
  const store = new Map();
  const context = {
    window: {
      localStorage: {
        getItem: k => (store.has(k) ? store.get(k) : null),
        setItem: (k, v) => store.set(k, String(v))
      },
      NexusAppRegistry: {
        register(app) {
          registered = app;
        }
      }
    },
    document: { createElement: tag => makeNode(tag) }
  };
  vm.createContext(context);
  vm.runInContext(fs.readFileSync("apps/native-services.js", "utf8"), context);
  vm.runInContext(fs.readFileSync("apps/personalisation-catalog.js", "utf8"), context);
  if (adapter) context.window.NexusNativeServices.register("installer", adapter);
  vm.runInContext(fs.readFileSync("apps/welcome.js", "utf8"), context);
  return { app: registered, store };
}

function mountWelcome(app) {
  const root = makeNode("section");
  const panel = makeNode("div");
  panel.id = "welcomePanel";
  const statusEl = makeNode("p");
  statusEl.id = "welcomeStatus";
  const tabs = ["firstboot", "installer"].map(m => {
    const b = makeNode("button");
    b.dataset.welcomeMode = m;
    return b;
  });
  const cleanup = app.mount({
    querySelector: sel => (sel === "#welcomePanel" ? panel : sel === "#welcomeStatus" ? statusEl : findById(panel, sel.slice(1))),
    querySelectorAll: sel => (sel === "[data-welcome-mode]" ? tabs : []),
    addEventListener: (t, fn) => root.addEventListener(t, fn),
    removeEventListener: (t, fn) => root.removeEventListener(t, fn)
  }, { launchApp() {}, desktopShell: { setThemePreset() {}, setDesktopWallpaper() {} } });
  return { root, panel, statusEl, tabs, cleanup };
}

// 1. Disconnected browser preview: first-boot skip works, installer reports unavailable disks/hardware honestly
{
  const { app, store } = loadWelcome(null);
  assert.ok(app.render().includes("Preview Mode"));
  const { root, panel, statusEl, tabs, cleanup } = mountWelcome(app);
  assert.ok(collectText(panel).includes("Welcome to NEXUS OS"));
  const skipBtn = panel.children[0].children.at(-1).children[2];
  root.dispatch("click", { target: skipBtn });
  assert.equal(store.get("nexus-firstboot-done"), "true");
  assert.ok(statusEl.textContent.includes("skipped"));

  root.dispatch("click", { target: tabs[1] });
  const text = collectText(panel);
  assert.ok(text.includes("Unavailable in browser preview"));
  cleanup();
}

// 2. Connected live host: preflight disks rendered & destructive checkbox required before launching Ubiquity
{
  let launched = false;
  const { app } = loadWelcome({
    preflight: () => ({
      arch: "x86_64",
      firmware: "UEFI",
      ubiquity_available: true,
      hardware: { cpu: "AMD Ryzen 5", ram_total_mib: 8192, disks: [{ device: "/dev/vda", size: "40G", model: "QEMU" }] }
    }),
    launch() {
      launched = true;
      return { message: "Launched Ubiquity installer." };
    }
  });
  const { root, panel, statusEl, tabs, cleanup } = mountWelcome(app);
  root.dispatch("click", { target: tabs[1] });
  assert.ok(collectText(panel).includes("/dev/vda (40G, QEMU)"));

  const launchBtn = panel.children[1].children.find(c => c.dataset?.welcomeAction === "launch-ubiquity");
  assert.equal(launchBtn.disabled, false);
  root.dispatch("click", { target: launchBtn });
  assert.equal(launched, false);
  assert.ok(statusEl.textContent.includes("irreversible"));

  const checkbox = findById(panel, "installerDestructiveConfirm");
  checkbox.checked = true;
  root.dispatch("click", { target: launchBtn });
  assert.equal(launched, true);
  assert.equal(statusEl.textContent, "Launched Ubiquity installer.");
  cleanup();
}

console.log("PASS Phase 8 Welcome First-Boot & Ubiquity Installer tests");
