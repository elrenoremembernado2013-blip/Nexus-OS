#!/usr/bin/env node
"use strict";
const assert = require("node:assert/strict");
const fs = require("node:fs");
const vm = require("node:vm");

const source = fs.readFileSync("apps/calculator.js", "utf8");
const registered = [];
const sandbox = {
  window: {
    NexusAppRegistry: {
      register(app) {
        registered.push(app);
      }
    }
  }
};
vm.runInNewContext(source, sandbox, { filename: "apps/calculator.js" });

const calc = sandbox.window.NexusCalculator;
assert.ok(calc, "NexusCalculator should initialize");
assert.equal(registered.length, 1);
assert.equal(registered[0].id, "calculator");

assert.equal(calc.evaluateExpression("2 + 3 * 4"), 14);
assert.equal(calc.evaluateExpression("(2 + 3) * 4"), 20);
assert.equal(calc.evaluateExpression("-5 + +2"), -3);
assert.equal(calc.evaluateExpression("7.5 / 2.5"), 3);
assert.equal(calc.evaluateExpression(".5 * 4"), 2);
assert.equal(calc.formatResult(calc.evaluateExpression("0.1 + 0.2")), "0.3");
assert.equal(calc.formatResult(-0), "0");

assert.throws(() => calc.evaluateExpression("1 / 0"), /Division by zero/);
assert.throws(() => calc.evaluateExpression("(1 + 2"), /Missing \)/);
assert.throws(() => calc.evaluateExpression("1 + alert(1)"), /Invalid expression/);
assert.throws(() => calc.evaluateExpression(""), /Invalid expression length/);
assert.throws(() => calc.evaluateExpression("1".repeat(121)), /Invalid expression length/);
console.log("PASS Calculator parser and formatter tests");
