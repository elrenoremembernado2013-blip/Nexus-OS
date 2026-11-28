#!/usr/bin/env node
// Regression tests for personalisation catalog, 7 wallpaper categories, attribution policy, themes, and profiles.
"use strict";
const assert = require("node:assert/strict");
const fs = require("node:fs");
const vm = require("node:vm");

// 1. Verify linux/config/wallpapers.json, linux/cinnamon/wallpapers.json, and themes.json consistency
const sharedWallpapersJson = JSON.parse(fs.readFileSync("linux/config/wallpapers.json", "utf8"));
const cinnamonWallpapersJson = JSON.parse(fs.readFileSync("linux/cinnamon/wallpapers.json", "utf8"));
const themesJson = JSON.parse(fs.readFileSync("linux/cinnamon/themes.json", "utf8"));

assert.deepEqual(sharedWallpapersJson, cinnamonWallpapersJson, "Shared wallpapers.json and Cinnamon wallpapers.json must match");

for (const key of ["midnight", "nebula", "arctic", "emerald", "solar"]) {
  assert.ok(themesJson[key], `Missing Cinnamon theme: ${key}`);
}

const requiredCategories = ["cinematic", "nature", "architecture", "abstract", "sci-fi", "minimal", "gaming"];
assert.deepEqual(sharedWallpapersJson.categoryKeys, requiredCategories, "Expected canonical 7 wallpaper categoryKeys");
assert.equal(sharedWallpapersJson.categories.length, 7, "Expected 7 canonical wallpaper categories");

for (const catKey of requiredCategories) {
  const matches = sharedWallpapersJson.wallpapers.filter(wp => wp.categoryKey === catKey);
  assert.ok(matches.length >= 2, `Expected at least 2 real wallpapers in category: ${catKey}`);
}

for (const wp of sharedWallpapersJson.wallpapers) {
  assert.ok(wp.photographer && wp.sourceName && wp.sourceUrl && wp.license, `Missing attribution on ${wp.id}`);
  assert.ok(wp.imageUrl.startsWith("https://"), `Expected https imageUrl for ${wp.id}`);
  assert.ok(wp.hdUrl && wp.hdUrl.startsWith("https://"), `Expected https hdUrl for ${wp.id}`);
  assert.ok(wp.sourceUrl.startsWith("https://"), `Expected https sourceUrl for ${wp.id}`);
  assert.deepEqual(wp.editions, ["cinnamon", "xfce", "lite-lxqt", "lite"], `Expected 4-edition support on ${wp.id}`);
}

// 2. Verify apps/personalisation-catalog.js exposes all 5 themes, 6 profiles, 7 categories, and attributed wallpapers
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
assert.deepEqual([...cat.WALLPAPER_CATEGORIES.map(c => c.key)], requiredCategories);
assert.equal(cat.WALLPAPERS.length, sharedWallpapersJson.wallpapers.length);
for (const wp of cat.WALLPAPERS) {
  const jsonWp = sharedWallpapersJson.wallpapers.find(item => item.id === wp.id);
  assert.ok(jsonWp, `Catalog wallpaper ${wp.id} missing from wallpapers.json`);
  assert.equal(wp.category, jsonWp.categoryKey);
  assert.equal(wp.sourceUrl, jsonWp.sourceUrl);
  assert.ok(wp.hd && wp.uhd && wp.thumb && wp.photographer && wp.sourceUrl && wp.license, `Missing metadata on ${wp.id}`);
  assert.deepEqual([...wp.editions], ["cinnamon", "xfce", "lite-lxqt", "lite"]);
}

console.log("PASS Phase 17 personalisation themes, profiles, 7-category wallpaper ecosystem, and attribution tests");
