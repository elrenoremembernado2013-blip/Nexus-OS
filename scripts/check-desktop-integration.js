#!/usr/bin/env node
"use strict";

const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");

const rootDir = path.resolve(__dirname, "..");

// Lightweight spec-faithful DOM implementation for integration testing index.html + app.js + all apps/*.js.
function parseTagAttrs(attrText) {
  const attrs = new Map();
  const re = /([a-zA-Z_:][\w:.-]*)(?:\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s"'=<>`]+)))?/g;
  let match;
  while ((match = re.exec(attrText)) !== null) {
    const key = match[1].toLowerCase();
    const val = match[2] ?? match[3] ?? match[4] ?? "";
    attrs.set(key, decodeHtml(val));
  }
  return attrs;
}

function decodeHtml(str) {
  return String(str)
    .replace(/&amp;/g, "&")
    .replace(/&lt;/g, "<")
    .replace(/&gt;/g, ">")
    .replace(/&quot;/g, '"')
    .replace(/&#39;/g, "'");
}

const VOID_TAGS = new Set(["area", "base", "br", "col", "embed", "hr", "img", "input", "link", "meta", "param", "source", "track", "wbr"]);

function createDomEnvironment(htmlText) {
  const consoleErrors = [];
  const doc = {
    body: null,
    documentElement: null,
    activeElement: null,
    _listeners: new Map(),
    createElement(tag) {
      return new MockElement(tag.toLowerCase(), doc);
    },
    createTextNode(text) {
      return new MockText(text);
    },
    getElementById(id) {
      return doc.documentElement ? findFirst(doc.documentElement, el => el.id === id) : null;
    },
    querySelector(selector) {
      return doc.documentElement ? querySelector(doc.documentElement, selector) : null;
    },
    querySelectorAll(selector) {
      return doc.documentElement ? querySelectorAll(doc.documentElement, selector) : [];
    },
    addEventListener(type, fn) {
      if (!doc._listeners.has(type)) doc._listeners.set(type, new Set());
      doc._listeners.get(type).add(fn);
    },
    removeEventListener(type, fn) {
      doc._listeners.get(type)?.delete(fn);
    },
    dispatchEvent(event) {
      event.target = event.target || doc.body;
      const list = [...(doc._listeners.get(event.type) || [])];
      list.forEach(fn => fn(event));
      return !event.defaultPrevented;
    }
  };

  class MockText {
    constructor(text) {
      this.nodeType = 3;
      this._text = String(text ?? "");
      this.parentNode = null;
    }
    get textContent() {
      return this._text;
    }
    set textContent(v) {
      this._text = String(v ?? "");
    }
    remove() {
      if (this.parentNode) {
        const idx = this.parentNode.childNodes.indexOf(this);
        if (idx >= 0) this.parentNode.childNodes.splice(idx, 1);
        this.parentNode = null;
      }
    }
  }

  class MockClassList {
    constructor(el) {
      this.el = el;
    }
    _tokens() {
      return (this.el._attrs.get("class") || "").split(/\s+/).filter(Boolean);
    }
    _save(tokens) {
      this.el._attrs.set("class", tokens.join(" "));
    }
    add(...names) {
      const tokens = this._tokens();
      names.forEach(n => {
        if (n && !tokens.includes(n)) tokens.push(n);
      });
      this._save(tokens);
    }
    remove(...names) {
      const set = new Set(names);
      this._save(this._tokens().filter(t => !set.has(t)));
    }
    contains(name) {
      return this._tokens().includes(name);
    }
    toggle(name, force) {
      const has = this.contains(name);
      const next = force === undefined ? !has : Boolean(force);
      if (next && !has) this.add(name);
      else if (!next && has) this.remove(name);
      return next;
    }
  }

  function makeDatasetProxy(el) {
    return new Proxy({}, {
      get(_, prop) {
        if (typeof prop !== "string") return undefined;
        const attr = "data-" + prop.replace(/[A-Z]/g, m => "-" + m.toLowerCase());
        return el._attrs.has(attr) ? el._attrs.get(attr) : undefined;
      },
      set(_, prop, value) {
        const attr = "data-" + prop.replace(/[A-Z]/g, m => "-" + m.toLowerCase());
        el._attrs.set(attr, String(value));
        return true;
      },
      deleteProperty(_, prop) {
        const attr = "data-" + prop.replace(/[A-Z]/g, m => "-" + m.toLowerCase());
        el._attrs.delete(attr);
        return true;
      }
    });
  }

  class MockElement {
    constructor(tagName, ownerDocument) {
      this.nodeType = 1;
      this.tagName = tagName.toUpperCase();
      this._tag = tagName.toLowerCase();
      this.ownerDocument = ownerDocument;
      this.parentNode = null;
      this.childNodes = [];
      this._attrs = new Map();
      this._listeners = new Map();
      this.classList = new MockClassList(this);
      this.dataset = makeDatasetProxy(this);
      this._value = "";
      this.checked = false;
      this.disabled = false;
      this.hidden = false;
      this.open = false;
      this.tabIndex = -1;
      this.offsetWidth = 800;
      this.offsetHeight = 520;
      this.clientWidth = 1280;
      this.clientHeight = 800;
      this.scrollTop = 0;
      this.scrollHeight = 0;
      this.style = {
        _props: new Map(),
        setProperty(k, v) { this._props.set(k, String(v)); },
        getPropertyValue(k) { return this._props.get(k) || ""; },
        cssText: ""
      };
    }
    get id() { return this._attrs.get("id") || ""; }
    set id(v) { this._attrs.set("id", String(v)); }
    get className() { return this._attrs.get("class") || ""; }
    set className(v) { this._attrs.set("class", String(v)); }
    get value() {
      if (this._tag === "select") {
        const opts = this.querySelectorAll("option");
        const selected = opts.find(o => o.selected);
        return selected ? selected.value : (this._value || (opts[0]?.value ?? ""));
      }
      return this._value;
    }
    set value(v) {
      this._value = String(v ?? "");
      if (this._tag === "select") {
        this.querySelectorAll("option").forEach(o => { o.selected = (o.value === this._value); });
      }
    }
    get children() {
      return this.childNodes.filter(n => n.nodeType === 1);
    }
    get childElementCount() {
      return this.children.length;
    }
    get firstElementChild() {
      return this.children[0] || null;
    }
    get textContent() {
      return this.childNodes.map(c => c.textContent).join("");
    }
    set textContent(v) {
      this.childNodes = [];
      if (v !== undefined && v !== null && String(v) !== "") {
        this.append(new MockText(String(v)));
      }
    }
    get innerHTML() {
      return this.childNodes.map(c => c.nodeType === 3 ? c.textContent : `<${c._tag}>${c.innerHTML}</${c._tag}>`).join("");
    }
    set innerHTML(html) {
      this.childNodes = [];
      parseHtmlFragment(String(html || ""), this, this.ownerDocument);
    }
    setAttribute(name, val) {
      const k = String(name).toLowerCase();
      this._attrs.set(k, String(val));
      if (k === "value") this._value = String(val);
      if (k === "disabled") this.disabled = true;
      if (k === "hidden") this.hidden = true;
      if (k === "selected") this.selected = true;
      if (k === "checked") this.checked = true;
    }
    getAttribute(name) {
      const k = String(name).toLowerCase();
      return this._attrs.has(k) ? this._attrs.get(k) : null;
    }
    hasAttribute(name) {
      return this._attrs.has(String(name).toLowerCase());
    }
    removeAttribute(name) {
      const k = String(name).toLowerCase();
      this._attrs.delete(k);
      if (k === "disabled") this.disabled = false;
      if (k === "hidden") this.hidden = false;
    }
    append(...nodes) {
      nodes.forEach(n => {
        if (typeof n === "string") n = new MockText(n);
        if (!n) return;
        n.remove?.();
        n.parentNode = this;
        this.childNodes.push(n);
      });
    }
    prepend(...nodes) {
      for (let i = nodes.length - 1; i >= 0; i--) {
        let n = nodes[i];
        if (typeof n === "string") n = new MockText(n);
        if (!n) continue;
        n.remove?.();
        n.parentNode = this;
        this.childNodes.unshift(n);
      }
    }
    replaceChildren(...nodes) {
      this.childNodes.forEach(c => { c.parentNode = null; });
      this.childNodes = [];
      this.append(...nodes);
    }
    remove() {
      if (this.parentNode) {
        const idx = this.parentNode.childNodes.indexOf(this);
        if (idx >= 0) this.parentNode.childNodes.splice(idx, 1);
        this.parentNode = null;
      }
    }
    contains(target) {
      let cur = target;
      while (cur) {
        if (cur === this) return true;
        cur = cur.parentNode;
      }
      return false;
    }
    matches(selector) {
      return selector.split(",").some(part => matchSimpleChain(this, part.trim()));
    }
    closest(selector) {
      let cur = this;
      while (cur && cur.nodeType === 1) {
        if (cur.matches(selector)) return cur;
        cur = cur.parentNode;
      }
      return null;
    }
    querySelector(selector) {
      return querySelector(this, selector);
    }
    querySelectorAll(selector) {
      return querySelectorAll(this, selector);
    }
    addEventListener(type, fn) {
      if (!this._listeners.has(type)) this._listeners.set(type, new Set());
      this._listeners.get(type).add(fn);
    }
    removeEventListener(type, fn) {
      this._listeners.get(type)?.delete(fn);
    }
    dispatchEvent(event) {
      event.target = event.target || this;
      let cur = this;
      while (cur) {
        event.currentTarget = cur;
        const handlers = [...(cur._listeners?.get(event.type) || [])];
        for (const fn of handlers) fn(event);
        if (event.cancelBubble) break;
        cur = event.bubbles === false ? null : cur.parentNode;
      }
      if (!event.cancelBubble && event.bubbles !== false && this.ownerDocument) {
        this.ownerDocument.dispatchEvent(event);
      }
      return !event.defaultPrevented;
    }
    click() {
      if (this.disabled) return;
      this.dispatchEvent(makeEvent("click", { bubbles: true }));
    }
    focus() {
      this.ownerDocument.activeElement = this;
    }
    showModal() { this.open = true; }
    close() {
      this.open = false;
      this.dispatchEvent(makeEvent("close", { bubbles: false }));
    }
    getBoundingClientRect() {
      return { left: 120, top: 80, width: this.offsetWidth || 800, height: this.offsetHeight || 520 };
    }
    setPointerCapture() {}
    releasePointerCapture() {}
  }

  function makeEvent(type, opts = {}) {
    return {
      type,
      bubbles: opts.bubbles !== false,
      defaultPrevented: false,
      cancelBubble: false,
      preventDefault() { this.defaultPrevented = true; },
      stopPropagation() { this.cancelBubble = true; },
      ...opts
    };
  }

  function matchSinglePart(el, part) {
    if (!part || el.nodeType !== 1) return false;
    let remaining = part;
    const notMatches = [];
    remaining = remaining.replace(/:not\(([^)]+)\)/g, (_, inner) => {
      notMatches.push(inner.trim());
      return "";
    });
    for (const neg of notMatches) {
      if (matchSinglePart(el, neg)) return false;
    }
    const attrMatches = [];
    remaining = remaining.replace(/\[([^\]]+)\]/g, (_, inner) => {
      attrMatches.push(inner.trim());
      return "";
    });
    const tagMatch = remaining.match(/^([a-zA-Z0-9_-]+|\*)/);
    if (tagMatch) {
      if (tagMatch[1] !== "*" && el._tag !== tagMatch[1].toLowerCase()) return false;
      remaining = remaining.slice(tagMatch[0].length);
    }
    const tokens = remaining.match(/[#.][a-zA-Z0-9_-]+/g) || [];
    if (tokens.join("") !== remaining) return false;
    for (const tok of tokens) {
      if (tok.startsWith("#") && el.id !== tok.slice(1)) return false;
      if (tok.startsWith(".") && !el.classList.contains(tok.slice(1))) return false;
    }
    for (const rawAttr of attrMatches) {
      const eq = rawAttr.indexOf("=");
      if (eq < 0) {
        if (!el.hasAttribute(rawAttr)) return false;
      } else {
        const key = rawAttr.slice(0, eq).trim();
        const val = rawAttr.slice(eq + 1).trim().replace(/^['"]|['"]$/g, "");
        if (el.getAttribute(key) !== val) return false;
      }
    }
    return true;
  }

  function splitSelectorChain(selector) {
    const parts = [];
    let current = "";
    let depth = 0;
    let quote = "";
    for (const ch of selector.trim()) {
      if (quote) {
        current += ch;
        if (ch === quote) quote = "";
      } else if (ch === '"' || ch === "'") {
        quote = ch;
        current += ch;
      } else if (ch === "[" || ch === "(") {
        depth++;
        current += ch;
      } else if (ch === "]" || ch === ")") {
        if (depth > 0) depth--;
        current += ch;
      } else if (/\s/.test(ch) && depth === 0) {
        if (current) {
          parts.push(current);
          current = "";
        }
      } else {
        current += ch;
      }
    }
    if (current) parts.push(current);
    return parts;
  }

  function matchSimpleChain(el, selector) {
    const parts = splitSelectorChain(selector);
    if (!parts.length) return false;
    if (!matchSinglePart(el, parts[parts.length - 1])) return false;
    let cur = el.parentNode;
    for (let i = parts.length - 2; i >= 0; i--) {
      while (cur && (cur.nodeType !== 1 || !matchSinglePart(cur, parts[i]))) {
        cur = cur.parentNode;
      }
      if (!cur) return false;
      cur = cur.parentNode;
    }
    return true;
  }

  function walkElements(root, fn) {
    for (const child of root.childNodes) {
      if (child.nodeType === 1) {
        fn(child);
        walkElements(child, fn);
      }
    }
  }

  function findFirst(root, pred) {
    let found = null;
    walkElements(root, el => {
      if (!found && pred(el)) found = el;
    });
    return found;
  }

  function querySelectorAll(root, selector) {
    const selectors = selector.split(",").map(s => s.trim()).filter(Boolean);
    const results = [];
    walkElements(root, el => {
      if (selectors.some(sel => matchSimpleChain(el, sel))) results.push(el);
    });
    return results;
  }

  function querySelector(root, selector) {
    const selectors = selector.split(",").map(s => s.trim()).filter(Boolean);
    return findFirst(root, el => selectors.some(sel => matchSimpleChain(el, sel)));
  }

  function parseHtmlFragment(html, container, ownerDocument) {
    const stack = [container];
    const tokenRe = /<!--[\s\S]*?-->|<\/([a-zA-Z0-9-]+)\s*>|<([a-zA-Z0-9-]+)([^>]*?)(\/?)\s*>|([^<]+)/g;
    let m;
    while ((m = tokenRe.exec(html)) !== null) {
      if (m[1]) {
        const closeTag = m[1].toLowerCase();
        while (stack.length > 1 && stack[stack.length - 1]._tag !== closeTag) {
          stack.pop();
        }
        if (stack.length > 1) stack.pop();
      } else if (m[2]) {
        const tag = m[2].toLowerCase();
        const attrs = parseTagAttrs(m[3] || "");
        const selfClose = Boolean(m[4]) || VOID_TAGS.has(tag);
        const el = new MockElement(tag, ownerDocument);
        attrs.forEach((v, k) => el.setAttribute(k, v));
        stack[stack.length - 1].append(el);
        if (!selfClose && tag !== "script" && tag !== "style") {
          stack.push(el);
        }
      } else if (m[5]) {
        const txt = decodeHtml(m[5]);
        if (txt) stack[stack.length - 1].append(new MockText(txt));
      }
    }
  }

  const htmlRoot = new MockElement("html", doc);
  const bodyMatch = htmlText.match(/<body[^>]*>([\s\S]*)<\/body>/i);
  const body = new MockElement("body", doc);
  htmlRoot.append(body);
  doc.documentElement = htmlRoot;
  doc.body = body;
  doc.activeElement = body;
  if (bodyMatch) {
    parseHtmlFragment(bodyMatch[1].replace(/<script[\s\S]*?<\/script>/gi, ""), body, doc);
  }

  return { doc, consoleErrors, makeEvent, MockElement };
}

function makeMemoryStorage() {
  const store = new Map();
  return {
    getItem(k) { return store.has(k) ? store.get(k) : null; },
    setItem(k, v) { store.set(String(k), String(v)); },
    removeItem(k) { store.delete(k); },
    clear() { store.clear(); }
  };
}

function bootDesktop(initialStorage = {}, extraOptions = {}) {
  const indexHtml = fs.readFileSync(path.join(rootDir, "index.html"), "utf8");
  const { doc, consoleErrors, makeEvent } = createDomEnvironment(indexHtml);
  const storage = makeMemoryStorage();
  Object.entries(initialStorage).forEach(([k, v]) => storage.setItem(k, v));

  const windowListeners = new Map();
  let nextTimerId = 1;
  const activeIntervals = new Set();
  const openedPopups = [];
  let popupMode = extraOptions.popupMode || "allow";
  let promptQueue = [...(extraOptions.prompts || [])];
  let confirmResult = extraOptions.confirmResult ?? true;

  class MockBlob {
    constructor(parts = [], opts = {}) {
      this.parts = parts;
      this.type = opts.type || "";
      this.size = parts.reduce((sum, p) => sum + String(p).length, 0);
    }
  }

  class SandboxURL extends URL {
    static createObjectURL() { return `blob:nexus-mock-${Math.random().toString(36).slice(2)}`; }
    static revokeObjectURL() {}
  }

  const windowObj = {
    document: doc,
    localStorage: storage,
    innerWidth: 1280,
    innerHeight: 800,
    Blob: MockBlob,
    URL: SandboxURL,
    matchMedia() {
      return { matches: false, addEventListener() {}, removeEventListener() {} };
    },
    requestAnimationFrame(fn) {
      fn();
      return 1;
    },
    setInterval(fn, ms) {
      const id = nextTimerId++;
      activeIntervals.add({ id, fn, ms });
      return id;
    },
    clearInterval(id) {
      for (const entry of activeIntervals) {
        if (entry.id === id) activeIntervals.delete(entry);
      }
    },
    setTimeout(fn) {
      return 1;
    },
    clearTimeout() {},
    open(url, target, features) {
      openedPopups.push({ url, target, features });
      if (popupMode === "block") return null;
      return { opener: windowObj };
    },
    confirm() { return confirmResult; },
    prompt() { return promptQueue.length ? promptQueue.shift() : null; },
    addEventListener(type, fn) {
      if (!windowListeners.has(type)) windowListeners.set(type, new Set());
      windowListeners.get(type).add(fn);
    },
    removeEventListener(type, fn) {
      windowListeners.get(type)?.delete(fn);
    },
    dispatchEvent(event) {
      (windowListeners.get(event.type) || []).forEach(fn => fn(event));
    }
  };

  if (extraOptions.corruptIndexedDB) {
    windowObj.indexedDB = {
      open() {
        const req = {};
        queueMicrotask(() => {
          req.result = {
            objectStoreNames: { contains: () => true },
            transaction() {
              return {
                objectStore() {
                  return {
                    get() {
                      const getReq = {};
                      queueMicrotask(() => {
                        getReq.result = { notABlob: true, type: "image/png" };
                        getReq.onsuccess?.();
                      });
                      return getReq;
                    }
                  };
                }
              };
            },
            close() {}
          };
          req.onsuccess?.();
        });
        return req;
      }
    };
  }

  const sandbox = {
    window: windowObj,
    document: doc,
    navigator: {},
    Blob: MockBlob,
    URL: windowObj.URL,
    localStorage: storage,
    console: {
      log() {},
      warn() {},
      error(...args) { consoleErrors.push(args.map(String).join(" ")); }
    },
    Date,
    Math,
    Number,
    String,
    Boolean,
    Array,
    Object,
    Set,
    Map,
    Error,
    TypeError,
    Promise,
    JSON,
    RegExp,
    Intl,
    setTimeout: windowObj.setTimeout,
    clearTimeout: windowObj.clearTimeout,
    setInterval: windowObj.setInterval,
    clearInterval: windowObj.clearInterval
  };
  windowObj.window = windowObj;
  windowObj.console = sandbox.console;

  const context = vm.createContext(sandbox);
  const scripts = [...indexHtml.matchAll(/<script[^>]+src="([^"]+)"/g)].map(m => m[1]);
  assert.ok(scripts.includes("app.js"), "index.html must load app.js");

  for (const rel of scripts) {
    if (rel === "app.js" && typeof extraOptions.beforeAppJs === "function") {
      extraOptions.beforeAppJs(windowObj);
    }
    const code = fs.readFileSync(path.join(rootDir, rel), "utf8");
    vm.runInContext(code, context, { filename: rel });
  }

  return {
    window: windowObj,
    document: doc,
    storage,
    consoleErrors,
    activeIntervals,
    openedPopups,
    setPopupMode(mode) { popupMode = mode; },
    pushPrompt(...vals) { promptQueue.push(...vals); },
    makeEvent
  };
}

(async () => {
// 1. All 12 registered apps: launch, minimize, restore, maximize, resize-clamp, close, focus recovery, reopen
{
  const env = bootDesktop();
  const { window: win, document: doc, makeEvent } = env;
  const expectedApps = [
    "files", "calendar", "software", "monitor", "notes", "settings",
    "browser", "terminal", "calculator", "gaming", "welcome", "quantum"
  ];
  assert.deepEqual(Array.from(win.NexusAppRegistry.list(), a => a.id).sort(), [...expectedApps].sort());

  // Verify every launcher entry resolves to a registered app and valid icon
  const launcherApps = win.NexusApplicationCatalog.getLauncherApps();
  assert.ok(launcherApps.length >= 11);
  launcherApps.forEach(entry => {
    assert.ok(win.NexusAppRegistry.get(entry.launchTarget), `Launcher entry ${entry.id} -> ${entry.launchTarget} must be registered`);
    assert.ok(fs.existsSync(path.join(rootDir, entry.icon)), `Launcher icon must exist: ${entry.icon}`);
  });

  // Verify every dock & shortcut icon in index.html maps to a registered app
  doc.querySelectorAll(".dock-app[data-app], .shortcut[data-app]").forEach(btn => {
    assert.ok(win.NexusAppRegistry.get(btn.dataset.app), `Shell button data-app=${btn.dataset.app} must be registered`);
  });

  // Calendar is bundled/internal until added from NEXUS Store: verify gating then install
  win.NexusDesktopShell.openApp("calendar");
  assert.equal(win.NexusWindowManager.getActive(), null, "Uninstalled internal app must not open before Store add");
  win.NexusApplicationCatalog.install("calendar");

  // Launch each app via desktop shell, verify lifecycle, close, and reopen
  for (const appId of expectedApps) {
    win.NexusDesktopShell.openApp(appId);
    const active = win.NexusWindowManager.getActive();
    assert.equal(active.appId, appId, `${appId} should be active after open`);
    const winEl = doc.getElementById(active.id);
    assert.ok(winEl, `${appId} window element must exist`);

    // Minimize -> restore -> maximize -> viewport resize clamp -> close -> reopen
    win.NexusWindowManager.minimize(active.id);
    assert.equal(win.NexusWindowManager.get(active.id).state, "minimized");
    win.NexusWindowManager.restore(active.id);
    assert.equal(win.NexusWindowManager.get(active.id).state, "normal");

    winEl.style.left = "990px";
    winEl.style.top = "680px";
    win.innerWidth = 640;
    win.innerHeight = 480;
    doc.getElementById("windowLayer").clientWidth = 640;
    doc.getElementById("windowLayer").clientHeight = 480;
    win.dispatchEvent(makeEvent("resize", { bubbles: false }));
    assert.ok(parseFloat(winEl.style.left) <= 640, `${appId} left position should clamp on viewport shrink`);

    // Close via Alt+F4
    doc.dispatchEvent(makeEvent("keydown", { key: "F4", altKey: true }));
    assert.equal(win.NexusWindowManager.get(active.id), null, `${appId} should close on Alt+F4`);
    assert.notEqual(doc.activeElement, doc.body, `Focus must not drop to body after closing ${appId}`);

    // Reopen cleanly
    win.NexusDesktopShell.openApp(appId);
    const reopened = win.NexusWindowManager.getActive();
    assert.equal(reopened.appId, appId, `${appId} should reopen cleanly`);
    win.NexusWindowManager.close(reopened.id);
  }
  assert.equal(env.consoleErrors.length, 0, `Unexpected console errors during full app lifecycle: ${env.consoleErrors.join("; ")}`);
  console.log("PASS Desktop integration: all 12 apps launch, minimize/restore, clamp on resize, close with focus recovery, and reopen");
}

// 2. Fault isolation: crashing app render/mount & throwing control listener do not break desktop or other apps
{
  const env = bootDesktop({}, {
    beforeAppJs(win) {
      const origGet = win.NexusAppRegistry.get;
      const origMount = win.NexusAppRegistry.mountApp;
      win.NexusAppRegistry.get = id => {
        if (id === "notes") return { id: "notes", name: "Notes", render() { throw new Error("boom-render <script>"); }, mount() {} };
        return origGet.call(win.NexusAppRegistry, id);
      };
      win.NexusAppRegistry.mountApp = (id, root, ctx) => {
        if (id === "monitor") throw new Error("boom-mount");
        return origMount.call(win.NexusAppRegistry, id, root, ctx);
      };
    }
  });
  const { window: win, document: doc } = env;

  win.NexusDesktopShell.openApp("notes");
  const w1 = win.NexusWindowManager.getActive();
  assert.equal(w1.appId, "notes");
  assert.ok(doc.getElementById(w1.id).textContent.includes("boom-render <script>"));

  win.NexusDesktopShell.openApp("monitor");
  const w2 = win.NexusWindowManager.getActive();
  assert.equal(w2.appId, "monitor");
  assert.ok(doc.getElementById(w2.id).textContent.includes("boom-mount"));

  // Other apps still work cleanly
  win.NexusDesktopShell.openApp("calculator");
  assert.equal(win.NexusWindowManager.getActive().appId, "calculator");

  // Throwing control listener doesn't break other listeners
  let secondListenerCalled = false;
  win.NexusDesktopShell.onControlChange(() => { throw new Error("listener-crash"); });
  win.NexusDesktopShell.onControlChange(() => { secondListenerCalled = true; });
  doc.querySelector('[data-toggle="power"]').click();
  assert.equal(secondListenerCalled, true);

  win.NexusWindowManager.close(w1.id);
  win.NexusWindowManager.close(w2.id);
  assert.ok(env.consoleErrors.length >= 3, "Fault isolation should log errors while staying alive");
  console.log("PASS Fault isolation: crashing app render/mount and control listeners do not break desktop shell");
}

// 3. Per-app regression assertions (Browser, Calculator, Notes, Calendar, Files, Terminal, Store, Settings, Quantum)
{
  const env = bootDesktop();
  const { window: win, document: doc, makeEvent } = env;

  // Browser: popup blocked + unsafe scheme rejection + duplicate bookmark & removal
  win.NexusDesktopShell.openApp("browser");
  const bw = doc.getElementById(win.NexusWindowManager.getActive().id);
  env.setPopupMode("block");
  bw.querySelector("#browserUrl").value = "https://example.org";
  bw.querySelector("#browserGo").click();
  assert.ok(bw.querySelector("#browserMsg").textContent.includes("Popup blocked"));

  bw.querySelector("#browserUrl").value = "javascript:alert(1)";
  bw.querySelector("#browserGo").click();
  assert.ok(bw.querySelector("#browserMsg").textContent.includes("Only HTTP and HTTPS"));
  assert.equal(env.openedPopups.length, 1, "Unsafe scheme must not open or trigger search");

  bw.querySelector("#browserBookmarkAdd").click(); // default linuxmint.com already saved? check with example.org
  bw.querySelector("#browserUrl").value = "https://example.org";
  bw.querySelector("#browserBookmarkAdd").click();
  assert.ok(bw.querySelector("#browserMsg").textContent.includes("Bookmarked"));
  bw.querySelector("#browserBookmarkAdd").click();
  assert.ok(bw.querySelector("#browserMsg").textContent.includes("already saved"));
  const removeBtn = bw.querySelector('[aria-label="Remove bookmark https://example.org/"]');
  assert.ok(removeBtn);
  removeBtn.click();
  assert.ok(bw.querySelector("#browserMsg").textContent.includes("Removed bookmark"));
  win.NexusWindowManager.close(win.NexusWindowManager.getActive().id);

  // Calculator: scientific notation chaining + division by zero + 'c' clear
  win.NexusDesktopShell.openApp("calculator");
  const cw = doc.getElementById(win.NexusWindowManager.getActive().id);
  const press = k => cw.querySelector(`[data-calc="${k}"]`).click();
  "0.0000001".split("").forEach(press);
  press("=");
  assert.equal(cw.querySelector("#calcDisplay").value, "1e-7");
  press("×");
  press("2");
  press("=");
  assert.equal(cw.querySelector("#calcDisplay").value, "2e-7");
  cw.querySelector(".window-content").dispatchEvent(makeEvent("keydown", { key: "c" }));
  assert.equal(cw.querySelector("#calcDisplay").value, "0");
  press("5");
  press("÷");
  press("0");
  press("=");
  assert.equal(cw.querySelector("#calcDisplay").value, "Error");
  win.NexusWindowManager.close(win.NexusWindowManager.getActive().id);

  // Notes: Ctrl+S save & persistence across close/reopen
  win.NexusDesktopShell.openApp("notes");
  let nw = doc.getElementById(win.NexusWindowManager.getActive().id);
  const notesArea = nw.querySelector("#notesText");
  notesArea.value = "Saved audit note";
  const ctrlS = makeEvent("keydown", { key: "s", ctrlKey: true });
  notesArea.dispatchEvent(ctrlS);
  assert.equal(ctrlS.defaultPrevented, true);
  assert.equal(nw.querySelector("#notesStatus").textContent, "Saved locally");
  win.NexusWindowManager.close(win.NexusWindowManager.getActive().id);
  win.NexusDesktopShell.openApp("notes");
  nw = doc.getElementById(win.NexusWindowManager.getActive().id);
  assert.equal(nw.querySelector("#notesText").value, "Saved audit note");
  win.NexusWindowManager.close(win.NexusWindowManager.getActive().id);

  // Files: invalid folder name gives status error
  win.NexusDesktopShell.openApp("files");
  const fw = doc.getElementById(win.NexusWindowManager.getActive().id);
  env.pushPrompt("bad/folder");
  fw.querySelector("#filesNewFolder").disabled = false;
  fw.querySelector("#filesNewFolder").click();
  assert.ok(fw.querySelector("#filesStatus").classList.contains("error"));
  win.NexusWindowManager.close(win.NexusWindowManager.getActive().id);

  // Terminal: null openSession fallback + 500-line output cap
  win.NexusNativeServices.register("terminal", {
    openSession() { return null; },
    write() {},
    interrupt() {},
    closeSession() {}
  });
  win.NexusDesktopShell.openApp("terminal");
  let tw = doc.getElementById(win.NexusWindowManager.getActive().id);
  assert.equal(tw.querySelector(".terminal-mode").textContent, "PREVIEW");
  assert.equal(tw.querySelector("#terminalInterrupt").disabled, true);
  win.NexusWindowManager.close(win.NexusWindowManager.getActive().id);
  win.NexusNativeServices.unregister("terminal");

  let termCallbacks = null;
  win.NexusNativeServices.register("terminal", {
    openSession(opts) { termCallbacks = opts; return "pty-cap-1"; },
    write() {},
    interrupt() {},
    closeSession() {}
  });
  win.NexusDesktopShell.openApp("terminal");
  tw = doc.getElementById(win.NexusWindowManager.getActive().id);
  for (let i = 0; i < 550; i++) termCallbacks.onOutput(`line-${i}`);
  assert.ok(tw.querySelector("#terminalOut").childElementCount <= 500, "Terminal output DOM must be capped at 500 lines");
  win.NexusWindowManager.close(win.NexusWindowManager.getActive().id);
  win.NexusNativeServices.unregister("terminal");

  // Store: welcome in System Tools + listener isolation
  const welcomeEntry = win.NexusApplicationCatalog.getById("welcome");
  assert.equal(welcomeEntry.category, "System Tools");
  assert.ok(win.NexusApplicationCatalog.categories.includes(welcomeEntry.category));

  // Settings: resetPreferences clears presets/dock/rotation/favourites + keyboard fav toggle
  win.NexusDesktopShell.openApp("settings");
  const sw = doc.getElementById(win.NexusWindowManager.getActive().id);
  const favBtn = sw.querySelector('[data-wallpaper-fav="alpine"]');
  favBtn.dispatchEvent(makeEvent("keydown", { key: "Enter" }));
  assert.equal(favBtn.getAttribute("aria-pressed"), "true");
  sw.querySelector('[data-theme-preset="nebula"]').click();
  assert.equal(doc.getElementById("desktop").dataset.nexusTheme, "nebula");
  const baselineIntervals = env.activeIntervals.size;
  const rotSel = sw.querySelector("#wallpaperRotationSelect");
  rotSel.value = "30";
  rotSel.dispatchEvent(makeEvent("change"));
  assert.equal(env.activeIntervals.size, baselineIntervals + 1);
  sw.querySelector("#resetPreferences").click();
  for (let i = 0; i < 8; i++) await Promise.resolve();
  assert.equal(favBtn.getAttribute("aria-pressed"), "false");
  assert.equal(doc.getElementById("desktop").dataset.nexusTheme, undefined);
  assert.equal(env.activeIntervals.size, baselineIntervals);
  win.NexusWindowManager.close(win.NexusWindowManager.getActive().id);

  // Quantum: guide submit preserves focus on #quantumGuideInput
  win.NexusDesktopShell.openApp("quantum");
  const qw = doc.getElementById(win.NexusWindowManager.getActive().id);
  qw.querySelector('[data-quantum-view="guide"]').click();
  const guideInput = qw.querySelector("#quantumGuideInput");
  guideInput.value = "hadamard";
  qw.querySelector(".quantum-guide-form").dispatchEvent(makeEvent("submit"));
  assert.equal(doc.activeElement.id, "quantumGuideInput");
  win.NexusWindowManager.close(win.NexusWindowManager.getActive().id);

  assert.equal(env.consoleErrors.length, 0, `Unexpected console errors: ${env.consoleErrors.join("; ")}`);
  console.log("PASS App regression suite: Browser, Calculator, Notes, Files, Terminal, Store, Settings, Quantum");
}

// 4. Corrupted storage recovery across apps (non-array favourites, bad JSON calendar/store/quantum, corrupt wallpaper blob)
{
  const env = bootDesktop({
    "nexus-wallpaper": "custom",
    "nexus-wallpaper-favourites": "123",
    "nexus-calendar-events-v1": "{corrupt",
    "nexus-store-state-v1": "{\"version\":999}",
    "nexus-quantum-progress-v1": "{bad-json"
  }, { corruptIndexedDB: true });
  const { window: win, document: doc } = env;
  ["settings", "software", "quantum"].forEach(appId => {
    win.NexusDesktopShell.openApp(appId);
    const active = win.NexusWindowManager.getActive();
    assert.equal(active.appId, appId);
    win.NexusWindowManager.close(active.id);
  });
  // Mount calendar directly to verify corrupted calendar event storage recovery
  const calEl = doc.createElement("div");
  const calApp = win.NexusAppRegistry.get("calendar");
  calEl.innerHTML = calApp.render();
  win.NexusAppRegistry.mountApp("calendar", calEl, { notify() {}, desktopShell: win.NexusDesktopShell });
  assert.ok(calEl.querySelector("#calendarStatus").classList.contains("error"));
  assert.equal(calEl.querySelector("form button").disabled, true);
  win.NexusAppRegistry.unmountRoot(calEl);
  assert.equal(env.consoleErrors.length, 0, `Corrupted storage caused console error: ${env.consoleErrors.join("; ")}`);
  console.log("PASS Corrupted storage recovery: Settings, Calendar, Store, and Quantum recover safely");
}

// 5. Native Linux .desktop launcher parity across Cinnamon, Xfce, Lite Openbox, and Lite LXQt
{
  const desktopDir = path.join(rootDir, "linux", "branding", "applications");
  const files = fs.readdirSync(desktopDir).filter(f => f.endsWith(".desktop")).sort();
  assert.equal(files.length, 11, "Expected 11 .desktop launcher files");
  const contents = new Map();
  for (const file of files) {
    const text = fs.readFileSync(path.join(desktopDir, file), "utf8");
    assert.match(text, /^\[Desktop Entry\]/m, `${file} missing [Desktop Entry]`);
    assert.match(text, /^Type=Application$/m, `${file} missing Type=Application`);
    assert.match(text, /^Name=.+$/m, `${file} missing Name=`);
    assert.match(text, /^Exec=.+$/m, `${file} missing Exec=`);
    assert.match(text, /^Icon=.+$/m, `${file} missing Icon=`);
    contents.set(file, text);
  }
  const launcherPath = path.join(rootDir, "linux", "branding", "nexus-launch-app.sh");
  const launcher = fs.readFileSync(launcherPath, "utf8");
  const expectedCommands = {
    files: ["nemo", "pcmanfm-qt", "pcmanfm", "thunar"],
    terminal: ["qterminal", "lxterminal", "gnome-terminal", "xfce4-terminal", "x-terminal-emulator"],
    monitor: ["gnome-system-monitor", "qps", "lxtask", "xfce4-taskmanager"],
    settings: ["cinnamon-settings", "xfce4-settings-manager", "lxqt-config", "obconf-qt", "obconf"],
    store: ["mintinstall", "qterminal", "lxterminal", "gnome-terminal", "xfce4-terminal", "x-terminal-emulator"]
  };
  const expectedTargets = {
    "nexus-files.desktop": "files",
    "nexus-terminal.desktop": "terminal",
    "nexus-system-monitor.desktop": "monitor",
    "nexus-settings.desktop": "settings",
    "nexus-store.desktop": "store"
  };
  for (const [file, target] of Object.entries(expectedTargets)) {
    assert.match(contents.get(file), new RegExp("^Exec=/usr/local/bin/nexus-launch-app " + target + "$", "m"), `${file} must call the shared launcher dispatcher`);
    for (const command of expectedCommands[target]) {
      assert.ok(launcher.includes(command), `Native launcher dispatcher missing ${command} for ${target}`);
    }
  }
  console.log("PASS Linux .desktop launcher dispatcher parity across Cinnamon, Xfce, Lite Openbox, and Lite LXQt");
}
})().catch(error => {
  console.error(error);
  process.exit(1);
});
