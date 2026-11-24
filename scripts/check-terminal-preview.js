#!/usr/bin/env node
// Static regression checks: browser Terminal must remain an honest non-executing preview.
"use strict";
const fs = require("node:fs");

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
console.log("PASS Terminal clearly identifies preview mode and does not simulate or execute commands.");
