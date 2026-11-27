#!/usr/bin/env node
// Isolated lifecycle tests for the NEXUS app registry (no browser required).
"use strict";
const assert = require("node:assert/strict");
const fs = require("node:fs");
const vm = require("node:vm");

const source = fs.readFileSync("apps/app-registry.js", "utf8");
const sandbox = { window: {} };
vm.runInNewContext(source, sandbox, { filename: "apps/app-registry.js" });
const registry = sandbox.window.NexusAppRegistry;
assert.ok(registry, "registry should initialize");

const rootA = {}, rootB = {};
const calls = [];
registry.register({
  id: "lifecycle-test",
  name: "Lifecycle test",
  render() {},
  mount(root) {
    calls.push("mount:" + (root === rootA ? "A" : "B"));
    return () => calls.push("cleanup:" + (root === rootA ? "A" : "B"));
  }
});
assert.equal(registry.mountApp("lifecycle-test", rootA), true);
assert.equal(registry.mountApp("lifecycle-test", rootB), true);
assert.equal(registry.mountApp("lifecycle-test", rootA), true, "remount should succeed");
assert.deepEqual(calls, ["mount:A", "mount:B", "cleanup:A", "mount:A"]);

assert.equal(registry.unmountRoot(rootA), true);
assert.equal(registry.unmountRoot(rootA), false, "unmount should be idempotent");
assert.deepEqual(calls.slice(-1), ["cleanup:A"]);
registry.unmountApp("lifecycle-test");
assert.deepEqual(calls.slice(-1), ["cleanup:B"]);
assert.equal(registry.unmountRoot(rootB), false);

assert.throws(() => registry.register({ id: "invalid id" }), /NEXUS app requires/);
assert.throws(() => registry.register({ id: "lifecycle-test", name: "Duplicate", render() {}, mount() {} }), /already registered/);
assert.equal(registry.mountApp("unknown-app", {}, {}), false);
console.log("PASS app registry independent-instance lifecycle tests");
