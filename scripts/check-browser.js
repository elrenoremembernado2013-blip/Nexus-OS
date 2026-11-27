#!/usr/bin/env node
"use strict";
const assert = require("node:assert/strict");
const fs = require("node:fs");
const vm = require("node:vm");

const source = fs.readFileSync("apps/browser.js", "utf8");
const sandbox = {
  URL,
  window: {
    NexusAppRegistry: {
      register() {}
    }
  }
};
vm.runInNewContext(source, sandbox, { filename: "apps/browser.js" });

const browser = sandbox.window.NexusBrowser;
assert.ok(browser, "NexusBrowser should initialize");

assert.equal(browser.validateExternalUrl("https://example.com"), "https://example.com/");
assert.equal(browser.validateExternalUrl("http://example.com/test?q=1"), "http://example.com/test?q=1");
assert.equal(browser.validateExternalUrl("example.com"), "https://example.com/");
assert.equal(browser.validateExternalUrl("  linuxmint.com/verify.php  "), "https://linuxmint.com/verify.php");

assert.equal(browser.validateExternalUrl("javascript:alert(1)"), null);
assert.equal(browser.validateExternalUrl("data:text/html,<script>alert(1)</script>"), null);
assert.equal(browser.validateExternalUrl("file:///etc/passwd"), null);
assert.equal(browser.validateExternalUrl("ftp://example.com"), null);
assert.equal(browser.validateExternalUrl("https://bad host"), null);
assert.equal(browser.validateExternalUrl(""), null);
assert.equal(browser.validateExternalUrl("http://"), null);
assert.equal(browser.buildSearchUrl("linux mint xfce", "duckduckgo"), "https://duckduckgo.com/?q=linux%20mint%20xfce");
assert.equal(browser.buildSearchUrl("nexus", "wikipedia"), "https://en.wikipedia.org/wiki/Special:Search?search=nexus");
assert.equal(browser.buildSearchUrl("   "), null);
console.log("PASS Browser external URL and search URL validation tests");
