#!/usr/bin/env node
// Static regression checks: browser Terminal must remain an honest non-executing preview.
"use strict";
const fs = require("node:fs");
const source = fs.readFileSync("app.js", "utf8");
const terminalView = source.slice(source.indexOf('if(app==="terminal")'), source.indexOf('if(app==="calculator")', source.indexOf('if(app==="terminal")')));
const terminalWireStart = source.indexOf('if(app==="terminal"){const inp=');
const terminalWireEnd = source.indexOf('\nif(app==="calculator")', terminalWireStart);
if (!terminalView || terminalWireStart < 0 || terminalWireEnd < 0) throw new Error("Terminal view or handler not found.");
const terminalWire = source.slice(terminalWireStart, terminalWireEnd);
for (const phrase of ["Ubuntu Bash preview", "native shell backend not connected", "Commands are not executed", "Bash unavailable in browser preview"]) {
  if (!terminalView.includes(phrase)) throw new Error(`Missing preview boundary text: ${phrase}`);
}
if (!terminalWire.includes("Bash backend unavailable")) throw new Error("Terminal submit handler must report unavailable Bash.");
if (/const responses\s*=/.test(terminalWire) || /new Date\(\)/.test(terminalWire)) throw new Error("Fake demo-command responses must not return.");
if (/eval\s*\(|new Function\s*\(/.test(terminalWire)) throw new Error("Terminal must not evaluate user input.");
console.log("PASS Terminal clearly identifies preview mode and does not simulate or execute commands.");
