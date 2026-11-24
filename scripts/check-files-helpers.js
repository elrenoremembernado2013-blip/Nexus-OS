#!/usr/bin/env node
"use strict";
const assert = require("node:assert/strict");
const fs = require("node:fs");
const vm = require("node:vm");

const source = fs.readFileSync("apps/files.js", "utf8");
const sandbox = {
  window: {
    NexusAppRegistry: {
      register() {}
    }
  }
};
vm.runInNewContext(source, sandbox, { filename: "apps/files.js" });

const helpers = sandbox.window.NexusFilesHelpers;
assert.ok(helpers, "NexusFilesHelpers should initialize");

assert.equal(helpers.isValidEntryName("notes.txt"), true);
assert.equal(helpers.isValidEntryName("  project-folder  "), true);
assert.equal(helpers.isValidEntryName(""), false);
assert.equal(helpers.isValidEntryName("   "), false);
assert.equal(helpers.isValidEntryName("."), false);
assert.equal(helpers.isValidEntryName(".."), false);
assert.equal(helpers.isValidEntryName("a/b"), false);
assert.equal(helpers.isValidEntryName("a\\b"), false);
assert.equal(helpers.isValidEntryName(null), false);

console.log("PASS File Manager entry name validation tests");
