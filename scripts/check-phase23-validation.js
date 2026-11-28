"use strict";

const assert = require("node:assert");
const fs = require("node:fs");
const path = require("node:path");
const { execFileSync } = require("node:child_process");

const ROOT = path.resolve(__dirname, "..");

function read(relPath) {
  return fs.readFileSync(path.join(ROOT, relPath), "utf8");
}

function runCmd(cmd, args, allowFail = false) {
  try {
    return {
      ok: true,
      stdout: execFileSync(cmd, args, { cwd: ROOT, encoding: "utf8" }),
      status: 0,
    };
  } catch (err) {
    if (!allowFail) throw err;
    return {
      ok: false,
      stdout: String(err.stdout || ""),
      stderr: String(err.stderr || ""),
      status: err.status || 1,
    };
  }
}

// 1. ISO Build Provenance, Branding & Verification Pipeline
const buildIsoSh = read("linux/build/build-nexus-iso.sh");
for (const field of [
  '"source_commit":',
  '"source_branch":',
  '"source_dirty":',
  '"ubuntu_codename": "noble"',
  '"package_repositories":',
  '"build_environment":',
  '"checksum_file":',
]) {
  assert(buildIsoSh.includes(field), `build-nexus-iso.sh missing provenance field ${field}`);
}

const applyBrandingSh = read("linux/build/apply-iso-branding.sh");
assert(
  applyBrandingSh.includes('/usr/local/share/nexus-os/ui/index.html'),
  "apply-iso-branding.sh must stage offline NEXUS desktop UI bundle"
);

const verifyIsoSh = read("linux/build/verify-nexus-iso.sh");
assert(
  verifyIsoSh.includes('/usr/local/bin/nexus-system-bridge') &&
    verifyIsoSh.includes('/usr/local/share/nexus-os/ui/index.html'),
  "verify-nexus-iso.sh must check NEXUS native bridge and UI bundle inside squashfs"
);

// Guard against grep -q + pipefail false negatives when checking captured ISO listings.
assert(
  verifyIsoSh.includes('[[ "$sq_list" != *"$req_sq"* ]]') &&
    !verifyIsoSh.includes('grep -Fq "$req_sq"') &&
    !verifyIsoSh.includes('| grep -q'),
  "Squashfs required-file checks must not use grep -q on a piped listing"
);
assert(
  verifyIsoSh.includes('[[ ! "$listing" =~ /boot/grub/efi\\.img|/efi\\.img|/EFI/boot/bootx64\\.efi ]]') &&
    verifyIsoSh.includes('[[ ! "$listing" =~ /isolinux/isolinux\\.bin|/boot/grub/i386-pc/eltorito\\.img ]]'),
  "ISO boot-entry checks must use pipefail-safe matching"
);

for (const args of [
  ["linux/build/build-nexus-iso.sh", "--edition", "cinnamon", "--dry-run"],
  ["linux/build/build-nexus-iso.sh", "--edition", "xfce", "--dry-run"],
  ["linux/lite/build-nexus-lite-iso.sh", "--dry-run"],
  ["linux/lite/scripts/build-nexus-lite-lxqt-iso.sh", "--dry-run"],
  ["linux/build/verify-nexus-iso.sh", "--edition", "cinnamon", "--dry-run"],
  ["linux/build/verify-nexus-iso.sh", "--edition", "xfce", "--dry-run"],
  ["linux/build/verify-nexus-iso.sh", "--edition", "lite", "--dry-run"],
  ["linux/build/verify-nexus-iso.sh", "--edition", "lite-lxqt", "--dry-run"],
]) {
  const res = runCmd("bash", args);
  assert(res.stdout.trim().length > 0, `Expected non-empty dry-run output for ${args.join(" ")}`);
}

// Exercise each complete edition build entry point and assert that the four
// variants resolve to distinct output images (prevents accidental overwrites).
const editionBuilds = [
  {
    name: "Standard Cinnamon",
    args: ["linux/build/build-nexus-iso.sh", "--edition", "cinnamon", "--dry-run"],
    expected: "nexus-os-22.3-cinnamon-amd64.iso",
  },
  {
    name: "XFCE",
    args: ["linux/build/build-nexus-iso.sh", "--edition", "xfce", "--dry-run"],
    expected: "nexus-os-22.3-xfce-amd64.iso",
  },
  {
    name: "Lite Openbox",
    args: ["linux/lite/build-nexus-lite-iso.sh", "--dry-run"],
    expected: "nexus-os-22.3-lite-amd64.iso",
  },
  {
    name: "Lite LXQt",
    args: ["linux/lite/scripts/build-nexus-lite-lxqt-iso.sh", "--dry-run"],
    expected: "nexus-os-22.3-lite-lxqt-amd64.iso",
  },
];
const editionOutputs = new Set();
for (const edition of editionBuilds) {
  const result = runCmd("bash", edition.args);
  assert(
    result.stdout.includes(edition.expected),
    `${edition.name} build entry point must target ${edition.expected}`
  );
  editionOutputs.add(edition.expected);
}
assert.strictEqual(editionOutputs.size, 4, "All four NEXUS editions must have unique ISO output paths");

// Provisioner dry-runs catch missing edition-specific scripts/configuration before
// expensive ISO remastering begins. These commands do not install or change packages.
const provisionerDryRuns = [
  ["linux/mint/provision-nexus-guest.sh", "--dry-run"],
  ["linux/lite/provision-nexus-lite.sh", "--dry-run"],
  ["linux/lite/scripts/provision-nexus-lite-lxqt.sh", "--dry-run"],
];
for (const args of provisionerDryRuns) {
  const result = runCmd("bash", args);
  assert(
    result.stdout.includes("[dry-run]"),
    `Provisioner must expose a safe dry-run: ${args.join(" ")}`
  );
}

// Verify check-build-prereqs.sh --strict reports missing tools/ISO cleanly without placeholder ISOs
const prereqRes = runCmd("bash", ["linux/build/check-build-prereqs.sh", "--edition", "lite", "--strict"], true);
if (!prereqRes.ok) {
  assert(
    prereqRes.stdout.includes("NOT READY") || prereqRes.stdout.includes("[MISSING]"),
    "Strict prereq failure must clearly report missing dependencies"
  );
}

// 2. Four Editions & Lite Bloat Isolation
for (const conf of [
  "linux/config/nexus-system.conf",
  "linux/config/nexus-standard-cinnamon.conf",
  "linux/lite/nexus-lite.conf",
  "linux/lite/nexus-lite-lxqt.conf",
]) {
  const txt = read(conf);
  assert(txt.includes("NEXUS_BASE_DISTRO=linuxmint"), `${conf} missing linuxmint base`);
  assert(txt.includes("NEXUS_BASE_VERSION=22.3"), `${conf} missing 22.3 version`);
  assert(txt.includes("NEXUS_BASE_UBUNTU_CODENAME=noble"), `${conf} missing noble codename`);
  assert(txt.includes("NEXUS_TARGET_ARCH=x86_64"), `${conf} missing x86_64 arch`);
}

for (const manifest of [
  "linux/lite/lite-packages.list",
  "linux/lite/manifests/lite-openbox-packages.list",
  "linux/lite/manifests/lite-lxqt-packages.list",
]) {
  const pkgs = read(manifest)
    .split(/\r?\n/)
    .map((l) => l.trim())
    .filter((l) => l && !l.startsWith("#"));
  for (const banned of ["steam-installer", "wine", "waydroid", "cinnamon-core", "cinnamon-desktop-environment"]) {
    assert(!pkgs.includes(banned), `Lite manifest ${manifest} must not preinstall heavyweight package ${banned}`);
  }
}

// 3. QEMU UEFI + Legacy BIOS Validation & Expanded Guest Service Checks
const qemuDry = runCmd("bash", ["linux/test/run-qemu-validation.sh", "--edition", "lite-lxqt", "--bios-check", "--dry-run"]);
assert(qemuDry.stdout.includes("UEFI (OVMF)"), "QEMU dry-run must describe UEFI (OVMF) mode");
assert(qemuDry.stdout.includes("Legacy BIOS (SeaBIOS"), "QEMU dry-run must describe Legacy BIOS mode");
assert(qemuDry.stdout.includes("build/qemu-test"), "QEMU dry-run must isolate disks under build/qemu-test");

const guestPy = read("linux/test/nexus-guest-test.py");
for (const key of [
  "control_centre_ok",
  "files_jailed_ok",
  "quantum_ok",
  "perf_ok",
  "hw_ok",
  "compat_ok",
  "wallpaper_cli_ok",
  "ui_bundle_present",
  "personalisation_ok",
]) {
  assert(guestPy.includes(key), `nexus-guest-test.py missing Phase 23 verification key ${key}`);
}

// 4. Installer Preflight, Refusal Guards & Recovery Diagnostics
const preflight = JSON.parse(runCmd("bash", ["linux/installer/nexus-install-preflight.sh", "--json"]).stdout);
assert(preflight.arch, "Preflight missing CPU architecture");
assert(preflight.firmware, "Preflight missing firmware mode");
assert(preflight.hardware && typeof preflight.hardware.ram_total_mib === "number", "Preflight missing hardware RAM telemetry");
assert(preflight.secure_boot_status, "Preflight missing secure_boot_status");

const installNoConfirm = runCmd("bash", ["linux/installer/nexus-disk-install.sh", "--disk", "/dev/vda"], true);
assert(!installNoConfirm.ok, "nexus-disk-install.sh must refuse execution without --yes-erase-disk");

const recDiagRaw = runCmd("bash", ["linux/installer/nexus-recovery.sh", "--diagnose", "--json", "--redacted"]).stdout;
const recDiag = JSON.parse(recDiagRaw);
assert.strictEqual(recDiag.read_only, true, "Recovery diagnostics must remain read-only");
assert(typeof recDiag.secure_boot_state === "string", "Recovery diagnostics missing secure_boot_state");
assert(Array.isArray(recDiag.findings), "Recovery diagnostics missing findings list");

// 5. Security Audit & Honest Secure Boot Reporting
const secStatus = JSON.parse(runCmd("bash", ["linux/mint/nexus-security-cli.sh", "status"]).stdout);
assert(secStatus.secure_boot && typeof secStatus.secure_boot.status === "string", "Security CLI missing secure_boot.status");
const hwInv = JSON.parse(runCmd("bash", ["linux/hardware/nexus-hw-inventory.sh", "--json"]).stdout);
assert.strictEqual(hwInv.privacy_redacted, true, "Hardware inventory must be privacy_redacted=true");
assert(hwInv.secure_boot_chain && typeof hwInv.secure_boot_chain.secure_boot_state === "string", "Hardware inventory missing secure_boot_chain");

// 6. Phase 23 Documentation Truthfulness
const doc = read("docs/PHASE_23_BOOTABLE_ISO_VALIDATION.md");
for (const marker of ["PASS", "FAIL", "BLOCKED", "NOT TESTED", "Linux Mint 22.3", "Ubuntu 24.04"]) {
  assert(doc.includes(marker), `docs/PHASE_23_BOOTABLE_ISO_VALIDATION.md missing ${marker}`);
}

console.log("PASS Phase 23 bootable ISO, installer, QEMU BIOS+UEFI, 4-edition, and security checks passed.");
