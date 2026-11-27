#!/usr/bin/env node
"use strict";
const assert = require("node:assert/strict");
const fs = require("node:fs");
const vm = require("node:vm");

function createStorage(initial = {}) {
  const map = new Map(Object.entries(initial));
  return {
    getItem: key => (map.has(key) ? map.get(key) : null),
    setItem: (key, value) => map.set(key, String(value)),
    removeItem: key => map.delete(key)
  };
}

function loadCatalog(initialStorage = {}) {
  const source = fs.readFileSync("apps/store-catalog.js", "utf8");
  const sandbox = {
    window: {
      localStorage: createStorage(initialStorage),
      addEventListener() {}
    }
  };
  vm.runInNewContext(source, sandbox, { filename: "apps/store-catalog.js" });
  return sandbox.window.NexusApplicationCatalog;
}

const catalog = loadCatalog();
assert.ok(catalog, "NexusApplicationCatalog should initialize");
assert.equal(catalog.getStorageError(), "");
assert.equal(catalog.isTargetInstalled("files"), true);
assert.equal(catalog.isTargetInstalled("calendar"), false);
assert.equal(catalog.canInstall("calendar"), true);
assert.equal(catalog.canRemove("files"), false);

let notifications = 0;
const unsub = catalog.subscribe(() => notifications++);

catalog.install("calendar");
assert.equal(catalog.isTargetInstalled("calendar"), true);
assert.equal(catalog.canRemove("calendar"), true);
assert.equal(notifications, 1);

assert.equal(catalog.toggleWishlist("calendar"), true);
assert.equal(catalog.isWishlisted("calendar"), true);
assert.equal(catalog.toggleWishlist("calendar"), false);
assert.equal(catalog.isWishlisted("calendar"), false);

catalog.remove("calendar");
assert.equal(catalog.isTargetInstalled("calendar"), false);
assert.ok(catalog.getOperations().length >= 2);
unsub();

assert.throws(() => catalog.remove("files"), /cannot be removed/);
assert.throws(() => catalog.install("steam"), /cannot be installed/);

const terminalEntry = catalog.getById("terminal");
assert.ok(!terminalEntry.description.includes("demonstration commands"));
assert.ok(!terminalEntry.permissions.join(" ").includes("fixed demonstration responses"));

const corruptCatalog = loadCatalog({ "nexus-store-state-v1": "{bad json" });
assert.match(corruptCatalog.getStorageError(), /Could not read saved Store data/);
assert.throws(() => corruptCatalog.install("calendar"), /Could not read saved Store data/);

console.log("PASS Store catalog state, persistence, and metadata tests");
