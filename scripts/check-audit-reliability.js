#!/usr/bin/env node
'use strict';

const assert = require('assert');
const fs = require('fs');
const path = require('path');
const { execFileSync } = require('child_process');

const repoRoot = path.resolve(__dirname, '..');

function read(rel) {
  return fs.readFileSync(path.join(repoRoot, rel), 'utf8');
}

function runBash(rel, args = []) {
  return execFileSync('bash', [path.join(repoRoot, rel), ...args], {
    cwd: repoRoot,
    encoding: 'utf8',
  });
}

// 1. Download script reliability: stall detection, fallback mirrors, corrupt .part retry
const dl = read('scripts/download-linux-mint.sh');
assert(dl.includes('--speed-limit'), 'download-linux-mint.sh must enforce curl --speed-limit');
assert(dl.includes('--speed-time'), 'download-linux-mint.sh must enforce curl --speed-time');
assert(dl.includes('LINUX_MINT_MIRROR_URLS'), 'download-linux-mint.sh must support mirror fallbacks');
assert(dl.includes('rm -f -- "$PART_PATH"') || dl.includes('rm -f -- "$PART_FILE"') || dl.includes('rm -f --'), 'download-linux-mint.sh must clear stale .part files on resume failure');

// 2. Package manifests: BIOS fallback (grub-pc-bin) across all 4 editions + cryptsetup for Standard editions
for (const manifest of [
  'linux/config/mint-packages.list',
  'linux/config/cinnamon-packages.list',
  'linux/lite/lite-packages.list',
  'linux/lite/manifests/lite-openbox-packages.list',
  'linux/lite/manifests/lite-lxqt-packages.list',
]) {
  const txt = read(manifest);
  assert(txt.includes('core:grub-pc-bin'), `${manifest} must include core:grub-pc-bin for Legacy BIOS installs`);
}
for (const stdManifest of [
  'linux/config/mint-packages.list',
  'linux/config/cinnamon-packages.list',
]) {
  const txt = read(stdManifest);
  assert(txt.includes('core:cryptsetup'), `${stdManifest} must include core:cryptsetup for LUKS2`);
  assert(txt.includes('core:cryptsetup-initramfs'), `${stdManifest} must include core:cryptsetup-initramfs for LUKS2`);
}

// 3. Offline UFW firewall defaults in all 3 provisioners & ISO builder
for (const prov of [
  'linux/mint/provision-nexus-guest.sh',
  'linux/lite/provision-nexus-lite.sh',
  'linux/lite/scripts/provision-nexus-lite-lxqt.sh',
]) {
  const dry = runBash(prov, ['--dry-run', '--ufw-offline']);
  assert(dry.includes('provisioning complete') || dry.includes('Dry-run'), `${prov} --ufw-offline dry-run must complete cleanly`);
  const src = read(prov);
  assert(src.includes('UFW_OFFLINE=true') && src.includes('ENABLED=yes') && src.includes('ufw.service'), `${prov} must configure /etc/ufw/ufw.conf ENABLED=yes and ufw.service in --ufw-offline mode`);
}
const isoDry = runBash('linux/build/build-nexus-iso.sh', ['--edition', 'cinnamon', '--dry-run']);
assert(isoDry.includes('grub-pc-bin') && isoDry.includes('cryptsetup') && isoDry.includes('cryptsetup-initramfs'), 'cinnamon dry-run plan must include grub-pc-bin and cryptsetup packages');
const isoBuilder = read('linux/build/build-nexus-iso.sh');
assert(isoBuilder.includes('--ufw-offline'), 'build-nexus-iso.sh must pass --ufw-offline during chroot provisioning');

// 4. Legacy BIOS + target UFW support in disk installer & launcher GUI warning
const diskScript = read('linux/installer/nexus-disk-install.sh');
assert(diskScript.includes('--boot-mode'), 'nexus-disk-install.sh must support --boot-mode');
assert(diskScript.includes('grub-install') && diskScript.includes('--target=i386-pc'), 'nexus-disk-install.sh must support i386-pc Legacy BIOS GRUB install');
assert(diskScript.includes('/etc/ufw/ufw.conf'), 'nexus-disk-install.sh must persist UFW enabled state in installed target');
const launcher = read('linux/installer/nexus-installer-launcher.sh');
assert(launcher.includes('zenity') && launcher.includes('notify-send'), 'nexus-installer-launcher.sh must provide GUI notification on graphical launch block');

// 5. System bridge installer tool invokes --launch
const bridge = read('linux/mint/nexus-system-bridge.py');
assert(bridge.includes('["nexus-installer-launcher", "--launch"]'), 'nexus-system-bridge.py must pass --launch to nexus-installer-launcher');

// 6. Strict CI & QEMU runner gates (no partial-boot or missing-Secure-Boot masking)
const wf = read('.github/workflows/iso-and-qemu-validation.yml');
assert(wf.includes('installed_boot_successes", 0) < r.get("installed_boot_attempts", 0)'), 'CI workflow must fail on partial installed boot failures (e.g. 2/3)');
assert(wf.includes('if not sb.get("tested"):'), 'CI workflow must fail if Secure Boot test was skipped');
const runner = read('linux/test/run-qemu-validation.sh');
assert(runner.includes('--strict'), 'run-qemu-validation.sh must support --strict mode');
assert(read('linux/test/run-phase125-tests.sh').includes('--strict'), 'run-phase125-tests.sh must support --strict mode');
assert(read('linux/test/run-phase130-tests.sh').includes('--strict'), 'run-phase130-tests.sh must support --strict mode');

// 7. Guest test & browser bench reliability improvements
const guestTest = read('linux/test/nexus-guest-test.py');
assert(guestTest.includes('["alt", "c"]'), 'nexus-guest-test.py must use Alt+C GTK accelerator for Ubiquity Continue navigation');
const bench = read('linux/test/nexus-browser-bench.py');
assert(bench.includes('tab_wait_sec = 45 if sw_mode else 30'), 'nexus-browser-bench.py must extend per-tab timeout under software rendering');

console.log('PASS audit reliability & installation checks');
