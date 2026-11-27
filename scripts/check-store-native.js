#!/usr/bin/env node
// Regression tests for NEXUS Store UI in disconnected prototype mode and connected native package mode.
"use strict";
const assert = require("node:assert/strict");
const fs = require("node:fs");
const vm = require("node:vm");

function createStorage() {
  const map = new Map();
  return {
    getItem: key => (map.has(key) ? map.get(key) : null),
    setItem: (key, val) => map.set(key, String(val)),
    removeItem: key => map.delete(key)
  };
}

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
    disabled: false,
    tabIndex: 0,
    title: "",
    textContent: "",
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
      contains: c => classSet.has(c)
    },
    set className(v) {
      classSet.clear();
      String(v || "").split(/\s+/).filter(Boolean).forEach(c => classSet.add(c));
    },
    get className() {
      return [...classSet].join(" ");
    },
    setAttribute(k, v) {
      attrs[k] = String(v);
      if (k.startsWith("data-")) {
        const camel = k.slice(5).replace(/-([a-z])/g, (_, ch) => ch.toUpperCase());
        el.dataset[camel] = String(v);
      }
    },
    getAttribute(k) {
      return attrs[k];
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
    focus() {},
    querySelector(sel) {
      return el.querySelectorAll(sel)[0] || null;
    },
    querySelectorAll(sel) {
      const out = [];
      (function walk(node) {
        for (const child of node.children || []) {
          if (matches(child, sel)) out.push(child);
          walk(child);
        }
      })(el);
      return out;
    },
    dispatch(type, event = {}) {
      for (const fn of listeners.get(type) || []) fn({ target: el, preventDefault() {}, ...event });
    }
  };
  return el;
}

function matches(el, sel) {
  if (!el || !sel) return false;
  if (sel.startsWith("#")) return el.id === sel.slice(1);
  if (sel.startsWith(".")) return el.classList.contains(sel.slice(1));
  if (sel.startsWith("[") && sel.endsWith("]")) {
    const inner = sel.slice(1, -1);
    const key = inner.replace(/^data-/, "").replace(/-([a-z])/g, (_, c) => c.toUpperCase());
    return el.dataset && Object.prototype.hasOwnProperty.call(el.dataset, key);
  }
  return el.tagName === sel.toUpperCase();
}

function textOf(node) {
  return [node.textContent || "", ...(node.children || []).map(textOf)].join(" ");
}

function setupStore(packagesAdapter) {
  let registered = null;
  const storage = createStorage();
  const context = {
    window: {
      localStorage: storage,
      confirm: () => true,
      addEventListener() {},
      NexusAppRegistry: {
        register(app) {
          registered = app;
        }
      }
    },
    document: {
      activeElement: null,
      createElement: tag => makeNode(tag)
    }
  };
  vm.createContext(context);
  vm.runInContext(fs.readFileSync("apps/native-services.js", "utf8"), context);
  vm.runInContext(fs.readFileSync("apps/store-catalog.js", "utf8"), context);
  if (packagesAdapter) {
    context.window.NexusNativeServices.register("packages", packagesAdapter);
  }
  vm.runInContext(fs.readFileSync("apps/software-centre.js", "utf8"), context);
  return { app: registered, context };
}

function mountStore(app) {
  const root = makeNode("section");
  const page = makeNode("div");
  page.id = "storePage";
  const search = makeNode("input");
  search.id = "storeSearch";
  const title = makeNode("h2");
  title.id = "storeViewTitle";
  const back = makeNode("button");
  back.id = "storeBack";
  const message = makeNode("p");
  message.id = "storeMessage";

  const navUpdates = makeNode("button");
  navUpdates.dataset.storeView = "updates";
  const navHome = makeNode("button");
  navHome.dataset.storeView = "home";

  root.append(navHome, navUpdates, back, title, search, page, message);
  const cleanup = app.mount(root, { notify() {}, launchApp() {} });
  return { root, page, search, title, message, navUpdates, cleanup };
}

// 1. Disconnected browser prototype mode
{
  const { app } = setupStore(null);
  assert.ok(app.render().includes("Native package service disconnected"));
  const { root, page, message, navUpdates, cleanup } = mountStore(app);
  root.dispatch("click", { target: navUpdates });
  assert.ok(textOf(page).includes("Update status is unknown."));
  assert.equal(message.textContent, "");
  cleanup();
}

// 2. Connected Linux Mint package service mode
{
  const calls = [];
  const { app } = setupStore({
    sources: () => ({ apt: true, flatpak: true, mintupdate: true }),
    checkUpdates: () => [
      { id: "firefox", name: "Firefox", source: "apt", currentVersion: "130.0", newVersion: "131.0" }
    ],
    search: query => [
      { id: "org.gimp.GIMP", name: "<img src=x>GIMP", description: `Match for ${query}`, source: "flatpak", installed: false, protected: false },
      { id: "systemd", name: "systemd", description: "Init system", source: "apt", installed: true, protected: true }
    ],
    install: (source, id) => {
      calls.push(["install", source, id]);
      return { ok: true, message: `Installed ${id} via ${source}` };
    },
    remove: (source, id) => {
      calls.push(["remove", source, id]);
      return { ok: false, message: "Authentication cancelled" };
    }
  });

  assert.ok(app.render().includes("Native APT / Flatpak connected"));
  const { root, page, search, message, navUpdates, cleanup } = mountStore(app);

  // Check updates view + trigger update
  root.dispatch("click", { target: navUpdates });
  assert.ok(textOf(page).includes("Firefox (APT)"));
  const updateBtn = page.querySelectorAll("button").find(b => b.dataset.storeAction === "native-install");
  assert.ok(updateBtn);
  root.dispatch("click", { target: updateBtn });
  assert.equal(message.textContent, "Installed firefox via apt");

  // Search view + XSS-safe name + protected package disabled check
  search.value = "gimp";
  root.dispatch("input", { target: search });
  const pageText = textOf(page);
  assert.ok(pageText.includes("<img src=x>GIMP"));
  const removeBtn = page.querySelectorAll("button").find(b => b.dataset.storeAction === "native-remove");
  assert.equal(removeBtn.disabled, true);
  cleanup();

  assert.equal(JSON.stringify(calls), JSON.stringify([["install", "apt", "firefox"]]));
}

console.log("PASS NEXUS Store native package adapter and boundary tests");
