#!/usr/bin/env node
"use strict";
const assert = require("node:assert/strict");
const fs = require("node:fs");
const vm = require("node:vm");

function makeElement(tagName = "div") {
  const listeners = new Map();
  const children = [];
  const attrs = new Map();
  const classes = new Set();
  return {
    tagName: tagName.toUpperCase(),
    children,
    value: "",
    textContent: "",
    className: "",
    disabled: false,
    classList: {
      add: c => classes.add(c),
      remove: c => classes.delete(c),
      contains: c => classes.has(c)
    },
    setAttribute: (k, v) => attrs.set(k, String(v)),
    getAttribute: k => attrs.get(k) || null,
    addEventListener: (type, fn) => {
      if (!listeners.has(type)) listeners.set(type, []);
      listeners.get(type).push(fn);
    },
    dispatchEvent: event => {
      (listeners.get(event.type) || []).forEach(fn => fn(event));
    },
    append: (...nodes) => children.push(...nodes),
    replaceChildren: (...nodes) => {
      children.length = 0;
      children.push(...nodes);
    },
    focus: () => {},
    querySelector: () => makeElement("button")
  };
}

function loadCalendar(initialStorage = {}) {
  const store = new Map(Object.entries(initialStorage));
  let registeredApp = null;
  const document = {
    createElement: tag => makeElement(tag)
  };
  const sandbox = {
    document,
    window: {
      localStorage: {
        getItem: key => (store.has(key) ? store.get(key) : null),
        setItem: (key, value) => store.set(key, String(value))
      },
      NexusAppRegistry: {
        register(app) {
          registeredApp = app;
        }
      }
    }
  };
  const source = fs.readFileSync("apps/calendar.js", "utf8");
  vm.runInNewContext(source, sandbox, { filename: "apps/calendar.js" });
  return { app: registeredApp, store };
}

const { app, store } = loadCalendar();
assert.equal(app.id, "calendar");
assert.ok(app.render().includes("nexus-calendar"));

const els = {
  "#calendarGrid": makeElement("div"),
  "#calendarMonthLabel": makeElement("h3"),
  "#calendarAgendaTitle": makeElement("h3"),
  "#calendarSelectedDate": makeElement("p"),
  "#calendarStatus": makeElement("p"),
  "#calendarEventList": makeElement("ul"),
  "#calendarEventTitle": makeElement("input"),
  "#calendarEventForm": makeElement("form"),
  "#calendarPrevious": makeElement("button"),
  "#calendarNext": makeElement("button")
};
const root = {
  querySelector: sel => els[sel] || makeElement("div")
};

app.mount(root);
assert.equal(els["#calendarStatus"].textContent, "");
assert.ok(els["#calendarGrid"].children.length > 28);

els["#calendarEventTitle"].value = "Mint QEMU verification";
els["#calendarEventForm"].dispatchEvent({ type: "submit", preventDefault() {} });
const saved = JSON.parse(store.get("nexus-calendar-events-v1"));
assert.equal(saved.length, 1);
assert.equal(saved[0].title, "Mint QEMU verification");
assert.equal(els["#calendarEventList"].children.length, 1);

const corrupt = loadCalendar({ "nexus-calendar-events-v1": "not-json" });
const submitBtn = makeElement("button");
const corruptEls = {
  "#calendarGrid": makeElement("div"),
  "#calendarMonthLabel": makeElement("h3"),
  "#calendarAgendaTitle": makeElement("h3"),
  "#calendarSelectedDate": makeElement("p"),
  "#calendarStatus": makeElement("p"),
  "#calendarEventList": makeElement("ul"),
  "#calendarEventTitle": makeElement("input"),
  "#calendarEventForm": { ...makeElement("form"), querySelector: () => submitBtn },
  "#calendarPrevious": makeElement("button"),
  "#calendarNext": makeElement("button")
};
corrupt.app.mount({ querySelector: sel => corruptEls[sel] || makeElement("div") });
assert.match(corruptEls["#calendarStatus"].textContent, /Could not load saved events/);
assert.equal(submitBtn.disabled, true);

console.log("PASS Calendar mount, event persistence, and error recovery tests");
