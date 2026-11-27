#!/usr/bin/env node
// Regression checks: browser Terminal preview honesty + native PTY session contract.
"use strict";
const assert = require("node:assert/strict");
const fs = require("node:fs");
const vm = require("node:vm");

const source = fs.readFileSync("apps/terminal.js", "utf8");
for (const phrase of [
  "Ubuntu Bash preview",
  "native shell backend not connected",
  "Commands are not executed",
  "Bash unavailable in browser preview",
  "Bash backend unavailable"
]) {
  if (!source.includes(phrase)) throw new Error(`Missing preview boundary text in apps/terminal.js: ${phrase}`);
}
if (/const responses\s*=/.test(source) || /new Date\(\)/.test(source)) {
  throw new Error("Fake demo-command responses must not return in apps/terminal.js.");
}
if (/eval\s*\(|new Function\s*\(/.test(source)) {
  throw new Error("Terminal must not evaluate user input.");
}

function makeFakeElement(tag = "div") {
  const listeners = new Map();
  const children = [];
  return {
    tagName: tag.toUpperCase(),
    className: "",
    textContent: "",
    value: "",
    disabled: false,
    scrollTop: 0,
    scrollHeight: 100,
    children,
    append(...nodes) {
      for (const node of nodes) children.push(node);
    },
    replaceChildren(...nodes) {
      children.length = 0;
      for (const node of nodes) children.push(node);
    },
    addEventListener(type, fn) {
      if (!listeners.has(type)) listeners.set(type, new Set());
      listeners.get(type).add(fn);
    },
    removeEventListener(type, fn) {
      listeners.get(type)?.delete(fn);
    },
    dispatch(type, event = {}) {
      for (const fn of listeners.get(type) || []) fn({ preventDefault() {}, ...event });
    }
  };
}

function loadTerminal(nativeAdapter) {
  let registered = null;
  const nativeServicesCode = fs.readFileSync("apps/native-services.js", "utf8");
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
        return makeFakeElement(tag);
      }
    }
  };
  vm.createContext(context);
  vm.runInContext(nativeServicesCode, context);
  if (nativeAdapter) {
    context.window.NexusNativeServices.register("terminal", nativeAdapter);
  }
  vm.runInContext(source, context);
  return { app: registered, services: context.window.NexusNativeServices };
}

function mountFakeRoot(app) {
  const out = makeFakeElement("div");
  const inp = makeFakeElement("input");
  const send = makeFakeElement("button");
  const interrupt = makeFakeElement("button");
  const mode = makeFakeElement("span");
  const status = makeFakeElement("p");
  const map = new Map([
    ["#terminalOut", out],
    ["#terminalInput", inp],
    ["#terminalSend", send],
    ["#terminalInterrupt", interrupt],
    [".terminal-mode", mode],
    ["#terminalStatus", status]
  ]);
  const root = {
    querySelector(selector) {
      return map.get(selector) || null;
    }
  };
  const cleanup = app.mount(root);
  return { out, inp, send, interrupt, mode, status, cleanup };
}

// 1. Preview mode (no native adapter): commands are never executed
{
  const { app } = loadTerminal(null);
  const html = app.render();
  assert.ok(html.includes("PREVIEW"));
  assert.ok(html.includes("Commands are not executed."));
  const mounted = mountFakeRoot(app);
  mounted.inp.value = "ls -la";
  mounted.send.dispatch("click");
  assert.equal(mounted.inp.value, "");
  assert.equal(mounted.out.children.at(-1).textContent, "Bash backend unavailable — command was not executed.");
  mounted.cleanup();
}

// 2. Native session contract: openSession -> write -> XSS-safe output -> interrupt -> closeSession
{
  const calls = [];
  let callbacks = null;
  const { app } = loadTerminal({
    openSession(opts) {
      callbacks = opts;
      calls.push(["openSession", opts.cols, opts.rows]);
      return { sessionId: "pty-1" };
    },
    write(id, data) {
      calls.push(["write", id, data]);
      callbacks.onOutput("<script>alert(1)</script>");
    },
    interrupt(id) {
      calls.push(["interrupt", id]);
    },
    closeSession(id) {
      calls.push(["closeSession", id]);
    }
  });
  const html = app.render();
  assert.ok(html.includes("CONNECTED"));
  const mounted = mountFakeRoot(app);
  mounted.inp.value = "echo hi";
  mounted.inp.dispatch("keydown", { key: "Enter" });
  assert.equal(mounted.out.children.at(-1).textContent, "<script>alert(1)</script>");
  assert.equal(mounted.out.children.at(-1).className, "terminal-output");
  mounted.interrupt.dispatch("click");
  mounted.cleanup();
  assert.equal(JSON.stringify(calls), JSON.stringify([
    ["openSession", 80, 24],
    ["write", "pty-1", "echo hi\n"],
    ["interrupt", "pty-1"],
    ["closeSession", "pty-1"]
  ]));
}

console.log("PASS Terminal preview boundary and native PTY session contract tests.");
