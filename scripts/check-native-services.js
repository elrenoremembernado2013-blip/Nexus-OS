#!/usr/bin/env node
"use strict";
const assert = require("node:assert/strict");
const fs = require("node:fs");
const vm = require("node:vm");

const source = fs.readFileSync("apps/native-services.js", "utf8");
const sandbox = { window: {} };
vm.runInNewContext(source, sandbox, { filename: "apps/native-services.js" });

const services = sandbox.window.NexusNativeServices;
const UnavailableError = sandbox.window.NativeIntegrationUnavailableError;
assert.ok(services, "NexusNativeServices should initialize");
assert.ok(UnavailableError, "NativeIntegrationUnavailableError should initialize");

for (const id of ["display", "sound", "network", "bluetooth", "power", "telemetry", "terminal", "packages", "files"]) {
  const state = services.status(id);
  assert.equal(state.serviceId, id);
  assert.equal(state.available, false);
  assert.throws(
    () => services.call(id, "ping"),
    err => err instanceof UnavailableError && err.code === "NATIVE_SERVICE_UNAVAILABLE" && err.serviceId === id
  );
}

assert.throws(() => services.status("unknown-service"), err => err && err.name === "RangeError");
assert.throws(() => services.register("unknown-service", {}), err => err && err.name === "RangeError");
assert.throws(() => services.register("telemetry", null), err => err && err.name === "TypeError");

assert.equal(services.register("telemetry", { ping: () => "pong" }), true);
assert.equal(services.status("telemetry").available, true);
assert.equal(services.call("telemetry", "ping"), "pong");
assert.throws(() => services.register("telemetry", { ping: () => "dup" }), /already registered/);
assert.throws(() => services.call("telemetry", "missingMethod"), err => err && err.name === "TypeError");

assert.equal(services.unregister("telemetry"), true);
assert.equal(services.status("telemetry").available, false);
console.log("PASS native service capability boundary tests");
