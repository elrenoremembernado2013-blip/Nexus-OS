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

// The official Mint ISO download must tolerate flaky CI mirror streams without
// weakening authenticity checks: HTTP/1.1, retries, resumable partial downloads,
// and removal of a checksum-invalid final file before a later retry.
const mintDownload = read("scripts/download-linux-mint.sh");
assert(
  mintDownload.includes("--http1.1") &&
    mintDownload.includes("--retry 8") &&
    mintDownload.includes("--continue-at -"),
  "Mint ISO download must use HTTP/1.1, retries, and resume interrupted transfers"
);
assert(
  mintDownload.includes('rm -f -- "$ISO_PATH"') &&
    mintDownload.includes("The manifest signature and ISO checksum both verified."),
  "Mint ISO download must discard checksum-invalid files and retain signature/hash verification"
);

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

// 7. Four-Edition Glitch Fix Regression Checks
const os = require("os");
const tmpCfg = fs.mkdtempSync(path.join(os.tmpdir(), "nexus-glitch-reg-"));
try {
  // 7a. Lite LXQt PNG wallpaper & pcmanfm-qt config (avoids missing Qt SVG plugin black screen)
  const lxqtPng = fs.readFileSync(path.join(ROOT, "linux/lite/lxqt/wallpaper-nexus-obsidian.png"));
  assert(lxqtPng.subarray(0, 8).equals(Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a])), "Lite LXQt wallpaper PNG signature invalid");
  const pcmanCfg = read("linux/lite/lxqt/pcmanfm-qt/settings.conf");
  assert(pcmanCfg.includes("wallpaper-nexus-obsidian.png"), "pcmanfm-qt settings.conf must use PNG wallpaper");
  assert(read("linux/lite/scripts/provision-nexus-lite-lxqt.sh").includes("wallpaper-nexus-obsidian.png"), "LXQt provisioner must install PNG wallpaper");
  assert(read("linux/build/apply-iso-branding.sh").includes("wallpaper-nexus-obsidian.png"), "ISO branding must stage LXQt PNG wallpaper");

  // 7b. apply-nexus-lite-lxqt.sh updates [Palette] accent & light appearance cleanly
  const lxqtRes = execFileSync("bash", ["linux/lite/scripts/apply-nexus-lite-lxqt.sh", "--profile", "lite-1g", "--theme", "emerald", "--appearance", "light"], {
    cwd: ROOT,
    env: { ...process.env, XDG_CONFIG_HOME: tmpCfg },
    encoding: "utf8",
  });
  assert(lxqtRes.includes("Applied NEXUS Lite LXQt profile"), "apply-nexus-lite-lxqt.sh failed");
  const appliedLxqtConf = fs.readFileSync(path.join(tmpCfg, "lxqt/lxqt.conf"), "utf8");
  assert(appliedLxqtConf.includes("#34d399") && appliedLxqtConf.includes("theme=light"), "apply-nexus-lite-lxqt.sh must update [Palette] accent and light theme");

  // 7c. First-boot autostart runs once cleanly via --autostart and skips subsequent logins
  const fbDesktop = read("linux/branding/nexus-firstboot.desktop");
  assert(fbDesktop.includes("--autostart") && fbDesktop.includes("Terminal=false"), "nexus-firstboot.desktop must use --autostart without spawning terminal popup");
  for (const prov of ["linux/lite/provision-nexus-lite.sh", "linux/lite/scripts/provision-nexus-lite-lxqt.sh", "linux/mint/provision-nexus-guest.sh"]) {
    assert(read(prov).includes("nexus-firstboot.desktop"), `${prov} must stage nexus-firstboot.desktop`);
  }
  const fb1 = execFileSync("bash", ["linux/mint/nexus-firstboot.sh", "--autostart", "--skip"], {
    cwd: ROOT,
    env: { ...process.env, XDG_CONFIG_HOME: tmpCfg },
    encoding: "utf8",
  });
  assert(fb1.includes("Recorded first-boot preference"), "First --autostart run must write firstboot-done marker");
  const fb2 = execFileSync("bash", ["linux/mint/nexus-firstboot.sh", "--autostart"], {
    cwd: ROOT,
    env: { ...process.env, XDG_CONFIG_HOME: tmpCfg },
    encoding: "utf8",
  });
  assert.strictEqual(fb2.trim(), "", "Subsequent --autostart run must exit quietly without re-applying");

  // 7d. Lite Openbox autostart respects saved WALLPAPER_FIT
  const obAuto = read("linux/lite/openbox/autostart");
  assert(obAuto.includes("WALLPAPER_FIT=") && obAuto.includes("--bg-center"), "Openbox autostart must honor WALLPAPER_FIT");

  // 7e. QMP screenshot analyzer checks all 3 RGB channels & guest test disables screen blanking
  assert(guestPy.includes("disable_screen_blanking") && guestPy.includes("offline_ui_present") && guestPy.includes("nexus_cli_tools_ok"), "nexus-guest-test.py missing blanking/CLI parity checks");
  const rgbStats = execFileSync("python3", ["-c", `
import importlib.util
from pathlib import Path
spec = importlib.util.spec_from_file_location("qgr", "linux/test/qemu-graphical-runner.py")
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)
tmp = Path("${tmpCfg}")
for tag, rgb, expected in [("blue", bytes([4, 10, 48] * 400), 100.0), ("black", bytes([0, 0, 0] * 400), 0.0)]:
    ppm = tmp / f"{tag}.ppm"
    png = tmp / f"{tag}.png"
    ppm.write_bytes(b"P6\\n20 20\\n255\\n" + rgb)
    res = mod.ppm_to_png_and_stats(ppm, png)
    assert res["non_black_pct"] == expected, (tag, res)
print("OK_RGB_STATS")
`], { cwd: ROOT, encoding: "utf8" });
  assert(rgbStats.includes("OK_RGB_STATS"), "qemu-graphical-runner.py RGB stats check failed");
} finally {
  fs.rmSync(tmpCfg, { recursive: true, force: true });
}

console.log("PASS Phase 23 bootable ISO, installer, QEMU BIOS+UEFI, 4-edition, and security checks passed.");
