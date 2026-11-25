#!/usr/bin/env node
// Tests for Settings system integration sections and native service availability reporting.
"use strict";
const assert = require("node:assert/strict");
const fs = require("node:fs");
const vm = require("node:vm");

const nativeSource = fs.readFileSync("apps/native-services.js", "utf8");
const sectionsSource = fs.readFileSync("apps/settings-sections.js", "utf8");

function makeNode(tag = "div") {
  const children = [];
  const attrs = {};
  const listeners = new Map();
  return {
    tagName: tag.toUpperCase(),
    className: "",
    type: "",
    id: "",
    textContent: "",
    dataset: {},
    children,
    setAttribute(k, v) {
      attrs[k] = String(v);
    },
    getAttribute(k) {
      return attrs[k];
    },
    append(...nodes) {
      children.push(...nodes);
    },
    addEventListener(type, fn) {
      if (!listeners.has(type)) listeners.set(type, new Set());
      listeners.get(type).add(fn);
    },
    dispatch(type) {
      for (const fn of listeners.get(type) || []) fn();
    }
  };
}

function runWithServices(serviceIds = []) {
  let enhancement = null;
  const context = {
    window: {
      NexusAppRegistry: {
        registerSettingsEnhancement(fn) {
          enhancement = fn;
        }
      }
    },
    document: {
      createElement(tag) {
        return makeNode(tag);
      },
      createTextNode(text) {
        return { nodeType: 3, textContent: String(text) };
      }
    }
  };
  vm.createContext(context);
  vm.runInContext(nativeSource, context);
  for (const id of serviceIds) {
    context.window.NexusNativeServices.register(id, {
      openControl(sectionId) {
        context.__openedControls = context.__openedControls || [];
        context.__openedControls.push([id, sectionId]);
      }
    });
  }
  vm.runInContext(sectionsSource, context);

  const sidebar = makeNode("div");
  const main = makeNode("div");
  enhancement({
    querySelector(sel) {
      if (sel === ".settings-sidebar") return sidebar;
      if (sel === ".settings-main") return main;
      return null;
    }
  });
  return { sidebar, main, context };
}

{
  const { sidebar, main } = runWithServices([]);
  assert.equal(sidebar.children.length, 8);
  assert.equal(main.children.length, 8);
  for (const page of main.children) {
    const statusBadge = page.children[2].children[0];
    assert.equal(statusBadge.textContent, "Not connected");
  }
}

{
  const { main, context } = runWithServices(["network", "power"]);
  const byId = Object.fromEntries(main.children.map(page => [page.dataset.settingsPage, page]));
  assert.equal(byId.network.children[2].children[0].textContent, "Connected");
  assert.equal(byId.power.children[2].children[0].textContent, "Connected");
  assert.equal(byId.display.children[2].children[0].textContent, "Not connected");
  byId.network.children[2].children[3].dispatch("click");
  assert.equal(JSON.stringify(context.__openedControls), JSON.stringify([["network", "network"]]));
}

console.log("PASS Settings system integration section boundary tests");
