#!/usr/bin/env node
// Regression checks for System Monitor capability boundary and native telemetry integration.
"use strict";
const assert = require("node:assert/strict");
const fs = require("node:fs");
const vm = require("node:vm");

const monitorSource = fs.readFileSync("apps/system-monitor.js", "utf8");
const nativeSource = fs.readFileSync("apps/native-services.js", "utf8");

function makeElement(tag = "div") {
  const listeners = new Map();
  const children = [];
  return {
    tagName: tag.toUpperCase(),
    className: "",
    textContent: "",
    children,
    setAttribute() {},
    append(...nodes) {
      children.push(...nodes);
    },
    replaceChildren(...nodes) {
      children.length = 0;
      children.push(...nodes);
    },
    addEventListener(type, fn) {
      if (!listeners.has(type)) listeners.set(type, new Set());
      listeners.get(type).add(fn);
    },
    removeEventListener(type, fn) {
      listeners.get(type)?.delete(fn);
    },
    dispatch(type) {
      for (const fn of listeners.get(type) || []) fn();
    }
  };
}

function loadMonitor(telemetryAdapter) {
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
      createElement(tag) {
        return makeElement(tag);
      }
    }
  };
  vm.createContext(context);
  vm.runInContext(nativeSource, context);
  if (telemetryAdapter) {
    context.window.NexusNativeServices.register("telemetry", telemetryAdapter);
  }
  vm.runInContext(monitorSource, context);
  return registered;
}

function mountMonitor(app) {
  const grid = makeElement("div");
  const badge = makeElement("span");
  const boundary = makeElement("div");
  const refresh = makeElement("button");
  const map = new Map([
    ["#monitorGrid", grid],
    ["#monitorStatusBadge", badge],
    ["#monitorBoundary", boundary],
    ["#monitorRefresh", refresh]
  ]);
  const cleanup = app.mount({
    querySelector(sel) {
      return map.get(sel) || null;
    }
  });
  return { grid, badge, boundary, refresh, cleanup };
}

// 1. Unavailable preview mode: never shows synthetic values
{
  const app = loadMonitor(null);
  const html = app.render();
  assert.ok(html.includes("No telemetry source"));
  assert.ok(html.includes("No sample values or synthetic graphs are shown."));
  const { grid, cleanup } = mountMonitor(app);
  assert.equal(grid.children.length, 7);
  for (const card of grid.children) {
    assert.equal(card.children.at(-1).textContent, "Unavailable");
  }
  cleanup();
}

// 2. Connected telemetry mode: renders real snapshot values and refreshes cleanly
{
  let count = 0;
  const app = loadMonitor({
    snapshot() {
      count += 1;
      return {
        processor: { summary: `${count * 12}% used`, detail: "2 cores active" },
        memory: { summary: "1.1 / 3.8 GiB" }
      };
    }
  });
  const html = app.render();
  assert.ok(html.includes("Telemetry connected"));
  const { grid, refresh, cleanup } = mountMonitor(app);
  assert.equal(grid.children[0].children[3].textContent, "12% used");
  assert.equal(grid.children[0].children[2].textContent, "2 cores active");
  assert.equal(grid.children[1].children[3].textContent, "1.1 / 3.8 GiB");
  assert.equal(grid.children[2].children[3].textContent, "Ready");
  refresh.dispatch("click");
  assert.equal(grid.children[0].children[3].textContent, "24% used");
  cleanup();
}

console.log("PASS System Monitor capability boundary and native telemetry tests");
