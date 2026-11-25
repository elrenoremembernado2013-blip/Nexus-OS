#!/usr/bin/env node
// Regression tests for Phase 6 Gaming Hub UI, zero-fake-library boundaries, and connected host mode.
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
    textContent: "",
    dataset: {},
    children,
    classList: {
      add: (...c) => c.forEach(x => classSet.add(x)),
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

function collectText(node) {
  return [node.textContent || "", ...(node.children || []).map(collectText)].join(" ");
}

function loadGaming(adapter) {
  let registered = null;
  const context = {
    window: {
      NexusAppRegistry: {
        register(app) {
          registered = app;
        }
      }
    },
    document: {
      createElement: tag => makeNode(tag)
    }
  };
  vm.createContext(context);
  vm.runInContext(fs.readFileSync("apps/native-services.js", "utf8"), context);
  if (adapter) context.window.NexusNativeServices.register("gaming", adapter);
  vm.runInContext(fs.readFileSync("apps/gaming.js", "utf8"), context);
  return registered;
}

function mountGaming(app) {
  const root = makeNode("section");
  const panel = makeNode("div");
  panel.id = "gamingPanel";
  const statusEl = makeNode("p");
  statusEl.id = "gamingStatus";
  const tabs = ["overview", "proton", "hardware", "controllers"].map(name => {
    const b = makeNode("button");
    b.dataset.gamingTab = name;
    return b;
  });
  const map = new Map([["#gamingPanel", panel], ["#gamingStatus", statusEl]]);
  const cleanup = app.mount({
    querySelector: sel => map.get(sel) || null,
    querySelectorAll: sel => (sel === "[data-gaming-tab]" ? tabs : []),
    addEventListener: (t, fn) => root.addEventListener(t, fn),
    removeEventListener: (t, fn) => root.removeEventListener(t, fn)
  }, { launchApp() {} });
  return { root, panel, statusEl, tabs, cleanup };
}

// 1. Disconnected browser prototype: zero fake game libraries or FPS claims
{
  const app = loadGaming(null);
  assert.ok(app.render().includes("Preview Only"));
  const { root, panel, tabs, cleanup } = mountGaming(app);
  assert.ok(collectText(panel).includes("No fake library or playtime data is shown"));
  root.dispatch("click", { target: tabs[2] });
  assert.ok(collectText(panel).includes("No synthetic FPS benchmarks are shown"));
  cleanup();
}

// 2. Connected Linux gaming service: renders real games, Proton versions, GPUs, controllers, and Gaming Mode
{
  let modeEnabled = false;
  const app = loadGaming({
    status: () => ({
      steam: {
        installed: true,
        installed_games: [{ appid: "440", name: "<script>TF2</script>" }],
        proton_versions: ["Proton Experimental"]
      },
      graphics: {
        gpus: [{ slot: "0000:00:02.0", vendor: "0x8086", device: "0x4e55", driver: "i915" }],
        vulkan: "available",
        opengl_renderer: "Mesa Intel"
      },
      hardware: { cpu: "Intel N4500", ram_total_mib: 3900, ram_available_mib: 2200, storage_available_gib: 18.2 },
      controllers: [{ device: "js0", name: "Xbox Wireless Controller" }],
      performance: { gaming_mode: modeEnabled ? "enabled" : "disabled", gamemode_installed: true }
    }),
    setGamingMode(enable) {
      modeEnabled = enable;
      return { message: `Gaming Mode ${enable ? "enabled" : "disabled"}` };
    }
  });
  const { root, panel, statusEl, tabs, cleanup } = mountGaming(app);
  assert.ok(collectText(panel).includes("<script>TF2</script> (AppID 440)"));
  root.dispatch("click", { target: tabs[1] });
  assert.ok(collectText(panel).includes("Proton Experimental"));
  root.dispatch("click", { target: tabs[2] });
  assert.ok(collectText(panel).includes("Mesa Intel"));
  root.dispatch("click", { target: tabs[3] });
  assert.ok(collectText(panel).includes("Xbox Wireless Controller (js0)"));
  const grid = panel.children[0];
  const toggleBtn = grid.children[1].children.find(c => c.dataset?.gamingAction === "mode-enable");
  assert.ok(toggleBtn);
  root.dispatch("click", { target: toggleBtn });
  assert.equal(statusEl.textContent, "Gaming Mode enabled");
  cleanup();
}

console.log("PASS Phase 6 Gaming Hub UI, Proton, hardware, and boundary tests");
