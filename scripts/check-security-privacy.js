#!/usr/bin/env node
// Regression tests for Phase 5 Security & Privacy overview and honest boundary reporting.
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
    append(...nodes) {
      children.push(...nodes);
    },
    addEventListener(type, fn) {
      if (!listeners.has(type)) listeners.set(type, new Set());
      listeners.get(type).add(fn);
    }
  };
}

function collectText(node) {
  return [node.textContent || "", ...(node.children || []).map(collectText)].join(" ");
}

function mountPrivacy(adapter) {
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
      createElement: tag => makeNode(tag),
      createTextNode: text => ({ nodeType: 3, textContent: String(text) })
    }
  };
  vm.createContext(context);
  vm.runInContext(nativeSource, context);
  if (adapter) {
    context.window.NexusNativeServices.register("privacy-security", adapter);
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
  return main.children.find(page => page.dataset.settingsPage === "privacy");
}

// 1. Disconnected browser prototype: all security rows must report Unavailable
{
  const privacyPage = mountPrivacy(null);
  const text = collectText(privacyPage);
  assert.ok(text.includes("Security & privacy overview"));
  assert.ok(text.includes("No synthetic security score is shown"));
  const dl = privacyPage.children[3].children[1];
  const dds = dl.children.filter(el => el.tagName === "DD");
  assert.equal(dds.length, 7);
  for (const dd of dds) {
    assert.equal(dd.textContent, "Unavailable");
  }
}

// 2. Connected Linux Mint security service: renders real statuses, warnings, and Flatpak distinction
{
  const privacyPage = mountPrivacy({
    overview() {
      return {
        firewall: { status: "enabled" },
        security_updates: { status: "attention_required" },
        disk_encryption: { status: "disabled" },
        secure_boot: { status: "unavailable" },
        devices: { status: "unavailable" },
        startup_apps: [{ file: "nexus-firstboot.desktop", name: "NEXUS OS First-Boot Setup", enabled: true }],
        warnings: ["Test security warning"]
      };
    }
  });
  const dl = privacyPage.children[3].children[1];
  const dds = dl.children.filter(el => el.tagName === "DD").map(el => el.textContent);
  assert.equal(JSON.stringify(dds), JSON.stringify([
    "Enabled",
    "Attention required",
    "Disabled",
    "Unavailable",
    "Flatpak portals · APT unsandboxed",
    "Unavailable",
    "1 entries"
  ]));
  assert.ok(collectText(privacyPage).includes("Test security warning"));
}

console.log("PASS Phase 5 Security & Privacy overview and boundary tests");
