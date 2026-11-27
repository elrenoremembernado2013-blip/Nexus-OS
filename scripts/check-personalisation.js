#!/usr/bin/env node
// Regression tests for Phase 7 personalisation catalog, attribution policy, themes, and profiles.
"use strict";
const assert = require("node:assert/strict");
const fs = require("node:fs");
const vm = require("node:vm");

// 1. Verify linux/cinnamon/wallpapers.json and themes.json consistency
const wallpapersJson = JSON.parse(fs.readFileSync("linux/cinnamon/wallpapers.json", "utf8"));
const themesJson = JSON.parse(fs.readFileSync("linux/cinnamon/themes.json", "utf8"));

for (const key of ["midnight", "nebula", "arctic", "emerald", "solar"]) {
  assert.ok(themesJson[key], `Missing Cinnamon theme: ${key}`);
}

assert.ok(wallpapersJson.categories.length >= 8, "Expected at least 8 wallpaper categories");
for (const wp of wallpapersJson.wallpapers) {
  assert.ok(wp.photographer && wp.sourceName && wp.sourceUrl && wp.license, `Missing attribution on ${wp.id}`);
  assert.ok(wp.imageUrl.startsWith("https://"), `Expected https URL for ${wp.id}`);
}

// 2. Verify apps/personalisation-catalog.js exposes all 5 themes, 6 profiles, and attributed wallpapers
const sandbox = { window: {} };
vm.runInNewContext(fs.readFileSync("apps/personalisation-catalog.js", "utf8"), sandbox, {
  filename: "apps/personalisation-catalog.js"
});
const cat = sandbox.window.NexusPersonalisationCatalog;
assert.ok(cat, "NexusPersonalisationCatalog should register");

for (const key of ["midnight", "nebula", "arctic", "emerald", "solar"]) {
  assert.ok(cat.THEME_PRESETS[key], `Missing catalog theme: ${key}`);
}
for (const profileKey of ["default", "minimal", "gaming", "productivity", "cinematic", "lightweight"]) {
  const p = cat.PROFILES[profileKey];
  assert.ok(p && p.themePreset && p.effectLevel && p.dockPosition, `Incomplete profile: ${profileKey}`);
}
assert.equal(cat.WALLPAPERS.length, wallpapersJson.wallpapers.length);
for (const wp of cat.WALLPAPERS) {
  assert.ok(wp.hd && wp.uhd && wp.photographer && wp.sourceUrl && wp.license, `Missing metadata on ${wp.id}`);
}

console.log("PASS Phase 7 personalisation themes, profiles, and wallpaper attribution tests");
