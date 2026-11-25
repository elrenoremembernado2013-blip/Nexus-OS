#!/usr/bin/env node
"use strict";
const assert = require("node:assert/strict");
const fs = require("node:fs");
const vm = require("node:vm");

// 1. Single-qubit engine tests
const engineSource = fs.readFileSync("apps/quantum-engine.js", "utf8");
const engineSandbox = { window: {} };
vm.runInNewContext(engineSource, engineSandbox, { filename: "apps/quantum-engine.js" });
const engine = engineSandbox.window.NexusQuantumEngine;
assert.ok(engine, "NexusQuantumEngine should initialize");

const initial = engine.createState();
assert.deepEqual(
  JSON.parse(JSON.stringify(engine.probabilities(initial))),
  { zero: 1, one: 0 }
);

const plus = engine.applyGate(initial, "H");
const plusProbs = engine.probabilities(plus);
assert.ok(Math.abs(plusProbs.zero - 0.5) < 1e-12);
assert.ok(Math.abs(plusProbs.one - 0.5) < 1e-12);

const restored = engine.applyGate(plus, "H");
const restoredProbs = engine.probabilities(restored);
assert.ok(Math.abs(restoredProbs.zero - 1) < 1e-12);
assert.ok(Math.abs(restoredProbs.one) < 1e-12);

const oneState = engine.applyGate(initial, "X");
assert.ok(Math.abs(engine.probabilities(oneState).one - 1) < 1e-12);

const minus = engine.applyGate(plus, "Z");
assert.ok(minus.beta.re < 0, "Z should flip the phase sign of |1>");
assert.ok(Math.abs(engine.probabilities(minus).zero - 0.5) < 1e-12);
assert.ok(Math.abs(engine.probabilities(minus).one - 0.5) < 1e-12);

// Boundary measurements
assert.equal(engine.measure(initial, 0).outcome, 0);
assert.equal(engine.measure(initial, 1).outcome, 0);
assert.equal(engine.measure(oneState, 0).outcome, 1);
assert.equal(engine.measure(oneState, 1).outcome, 1);
assert.equal(engine.measure(plus, 0.49).outcome, 0);
assert.equal(engine.measure(plus, 0.5).outcome, 1);

assert.throws(() => engine.applyGate(initial, "CNOT"), err => err && err.name === "RangeError");
assert.throws(() => engine.measure(initial, -0.01), err => err && err.name === "RangeError");
assert.throws(() => engine.measure(initial, 1.01), err => err && err.name === "RangeError");
assert.throws(() => engine.measure(initial, Number.NaN), err => err && err.name === "RangeError");

// Repeated gate normalization stability
let drifted = engine.createState();
for (let i = 0; i < 1001; i++) {
  drifted = engine.applyGate(drifted, "H");
}
const driftProbs = engine.probabilities(drifted);
assert.ok(Math.abs(driftProbs.zero + driftProbs.one - 1) < 1e-9);
assert.ok(Math.abs(driftProbs.zero - 0.5) < 1e-9);

// 2. Content, answers, XP deduplication, malformed state recovery, and offline guide
const contentSource = fs.readFileSync("apps/quantum-content.js", "utf8");
const contentSandbox = { window: {} };
vm.runInNewContext(contentSource, contentSandbox, { filename: "apps/quantum-content.js" });
const content = contentSandbox.window.NexusQuantumContent;
assert.ok(content, "NexusQuantumContent should initialize");

const trackTitles = content.getTracks().map(t => t.title);
for (const expected of ["Quantum Basics", "Spanish Basics", "French Basics", "Python Basics"]) {
  assert.ok(trackTitles.includes(expected), `Missing track: ${expected}`);
}

assert.equal(content.normalizeAnswer("  GrAcIaS  "), "gracias");
assert.equal(content.checkAnswer("es-greetings", "  GRACIAS ").correct, true);
assert.equal(content.checkAnswer("fr-greetings", "Merci").correct, true);
assert.equal(content.checkAnswer("py-variables", "5").correct, true);
assert.equal(content.checkAnswer("q-hadamard", "x").correct, false);
assert.throws(() => content.checkAnswer("unknown-lesson", "1"), err => err && err.name === "RangeError");

let progress = content.createEmptyProgress();
const firstComplete = content.completeLesson(progress, "q-qubit");
assert.equal(firstComplete.awardedXp, 10);
assert.equal(firstComplete.progress.xp, 10);
const duplicateComplete = content.completeLesson(firstComplete.progress, "q-qubit");
assert.equal(duplicateComplete.awardedXp, 0);
assert.equal(duplicateComplete.progress.xp, 10);

assert.throws(() => content.completeLesson(progress, "missing-lesson"), err => err && err.name === "RangeError");
assert.throws(() => content.parseProgress("{bad-json"), err => err && err.name === "SyntaxError");
assert.throws(() => content.parseProgress({ version: 2, completedLessonIds: [], xp: 0 }), /unsupported/);
assert.throws(() => content.parseProgress({ version: 1, completedLessonIds: ["nonexistent"], xp: 10 }), /unsupported/);

const emptyGuide = content.queryGuide("", "q-qubit");
assert.equal(emptyGuide.mode, "prompt");
assert.ok(emptyGuide.body.length > 0);
const hadamardGuide = content.queryGuide("hadamard");
assert.equal(hadamardGuide.mode, "glossary");

// 3. UI registration, safe text handling, Store catalog, and script load order
function makeEl(tag = "div") {
  const listeners = new Map();
  const children = [];
  const attrs = new Map();
  const classes = new Set();
  const obj = {
    tagName: tag.toUpperCase(),
    children,
    style: {},
    dataset: {},
    value: "",
    textContent: "",
    type: "",
    id: "",
    className: "",
    classList: {
      add: c => classes.add(c),
      remove: c => classes.delete(c),
      toggle: (c, force) => (force === undefined ? (classes.has(c) ? classes.delete(c) : classes.add(c)) : (force ? classes.add(c) : classes.delete(c))),
      contains: c => classes.has(c)
    },
    setAttribute: (k, v) => attrs.set(k, String(v)),
    getAttribute: k => attrs.get(k) || null,
    addEventListener: (type, fn) => {
      if (!listeners.has(type)) listeners.set(type, []);
      listeners.get(type).push(fn);
    },
    dispatchEvent: ev => (listeners.get(ev.type) || []).forEach(fn => fn(ev)),
    append: (...nodes) => children.push(...nodes),
    replaceChildren: (...nodes) => {
      children.length = 0;
      children.push(...nodes);
    }
  };
  Object.defineProperty(obj, "innerHTML", {
    set() {
      throw new Error("innerHTML must not be used for dynamic Quantum content");
    },
    get() {
      return "";
    }
  });
  return obj;
}

const uiSource = fs.readFileSync("apps/quantum.js", "utf8");
let registeredQuantum = null;
const viewTabs = ["learn", "lab", "languages", "coding", "guide"].map(id => {
  const b = makeEl("button");
  b.dataset.quantumView = id;
  return b;
});
const bodyNode = makeEl("div");
const xpNode = makeEl("span");
const completedNode = makeEl("span");
const statusNode = makeEl("p");

const uiSandbox = {
  document: {
    createElement: tag => makeEl(tag),
    createTextNode: text => ({ textContent: String(text) })
  },
  window: {
    localStorage: {
      getItem: () => "{corrupted",
      setItem: () => {}
    },
    NexusQuantumEngine: engine,
    NexusQuantumContent: content,
    NexusAppRegistry: {
      register(app) {
        registeredQuantum = app;
      }
    }
  }
};
vm.runInNewContext(uiSource, uiSandbox, { filename: "apps/quantum.js" });
assert.ok(registeredQuantum && registeredQuantum.id === "quantum" && registeredQuantum.name === "Quantum");

const rendered = registeredQuantum.render();
for (const label of ["Learn", "Quantum Lab", "Languages", "Coding", "Guide"]) {
  assert.ok(rendered.includes(label), `Missing view tab in render(): ${label}`);
}

const mockRoot = {
  querySelector: sel => ({
    "#quantumBody": bodyNode,
    "#quantumXp": xpNode,
    "#quantumCompleted": completedNode,
    "#quantumStorageStatus": statusNode
  }[sel] || makeEl("div")),
  querySelectorAll: sel => (sel === "[data-quantum-view]" ? viewTabs : [])
};
registeredQuantum.mount(mockRoot, {});
assert.match(statusNode.textContent, /Could not load saved progress/);
assert.equal(xpNode.textContent, "0 XP");

// Verify XSS payload stays plain text inside Guide
const xssPayload = "<script>alert(1)</script>";
const guideOutput = content.queryGuide(xssPayload);
assert.equal(guideOutput.mode, "unmatched");
viewTabs.find(t => t.dataset.quantumView === "guide").dispatchEvent({ type: "click" });
const guideForm = bodyNode.children.find(c => c.tagName === "FORM");
assert.ok(guideForm, "Guide view should render a lookup form");
const guideInput = guideForm.children[0];
guideInput.value = xssPayload;
guideForm.dispatchEvent({ type: "submit", preventDefault() {} });
const guideCard = bodyNode.children.find(c => c.className.includes("quantum-guide-card"));
assert.ok(guideCard.children.some(c => c.textContent.includes(xssPayload)));

// Verify Store catalog entry and index.html load order
const catalogSource = fs.readFileSync("apps/store-catalog.js", "utf8");
const catalogSandbox = {
  window: {
    localStorage: { getItem: () => null, setItem: () => {} },
    addEventListener() {}
  }
};
vm.runInNewContext(catalogSource, catalogSandbox, { filename: "apps/store-catalog.js" });
const quantumEntry = catalogSandbox.window.NexusApplicationCatalog.getById("quantum");
assert.ok(quantumEntry, "Store catalog should include quantum");
assert.equal(quantumEntry.launchTarget, "quantum");
assert.equal(quantumEntry.installMode, "system");
assert.equal(quantumEntry.installedByDefault, true);
assert.equal(quantumEntry.icon, "assets/icons/quantum.svg");

const html = fs.readFileSync("index.html", "utf8");
const idxEngine = html.indexOf('src="apps/quantum-engine.js"');
const idxContent = html.indexOf('src="apps/quantum-content.js"');
const idxApp = html.indexOf('src="apps/quantum.js"');
const idxShell = html.indexOf('src="app.js"');
assert.ok(idxEngine > 0 && idxEngine < idxContent && idxContent < idxApp && idxApp < idxShell, "Quantum script load order invalid");

console.log("PASS Quantum engine, curriculum, progress, XSS safety, and catalog checks");
