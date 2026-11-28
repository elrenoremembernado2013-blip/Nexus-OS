#!/usr/bin/env node
"use strict";
const assert = require("node:assert/strict");
const fs = require("node:fs");
const vm = require("node:vm");
const storage = new Map();
const window = { localStorage: {
  getItem(key) { return storage.has(key) ? storage.get(key) : null; },
  setItem(key, value) { storage.set(key, String(value)); }
}};
vm.runInNewContext(fs.readFileSync("apps/notification-center.js", "utf8"), { window, console, crypto: { randomUUID: (() => { let n = 0; return () => "test-id-" + (++n); })() }, Date, Math, Set, JSON, TypeError, RangeError, Error });
const api = window.NexusNotifications;
assert.equal(api.list().length, 0);
let events = 0; const unsubscribe = api.subscribe(items => { events++; assert.ok(Array.isArray(items)); });
const first = api.add({ title: "Test update", body: "A sample notification", category: "updates" });
assert.equal(first.id, "test-id-1");
assert.equal(api.unreadCount(), 1);
assert.equal(api.list()[0].title, "Test update");
assert.equal(api.markRead(first.id), true);
assert.equal(api.unreadCount(), 0);
assert.equal(api.markRead(first.id), false);
assert.equal(events, 2);
assert.throws(() => api.add({ title: "", body: "invalid" }), /empty or too long/);
api.add({ title: "Second", body: "Body", category: "invalid-category" });
assert.equal(api.list()[0].category, "system");
assert.equal(api.clear(), true);
assert.equal(api.list().length, 0);
assert.equal(events, 4);
unsubscribe();
console.log("PASS notification centre storage, validation, read state, categories, listeners, and clear");
