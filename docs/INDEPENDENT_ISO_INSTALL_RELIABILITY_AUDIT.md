# NEXUS OS — Independent ISO, Installation & End-to-End Reliability Audit

**Branch:** `arena/f18c36a4-nexus-os`  
**Audit Date:** 2026-11-28  
**Scope:** Base ISO download & GPG verification, all 4 edition ISO builders (`cinnamon`, `xfce`, `lite` Openbox, `lite-lxqt`), live session provisioning & services, disk installation (`nexus-disk-install.sh`, Ubiquity launcher, LUKS2, manual partitioning, dual-boot `--keep-efi`, Legacy BIOS + UEFI), QEMU validation harnesses, and CI workflow gates.

---

## Executive Summary

An independent, adversarial audit of the NEXUS OS ISO pipeline, disk installer, system bridge, and CI validation harness uncovered **8 concrete reliability, security, and failure-masking gaps** across scripts, package manifests, and CI gates. All 8 gaps have been fixed or hardened in the repository and locally verified against `npm test`, `shellcheck`, `linux/test/test-installer-safety.sh`, and `linux/security/nexus-security-audit.sh --repo-only --repo . --strict`.

---

## Findings & Remediations

### 1. Base ISO Download Stalls & Corrupted Partial Resumes (`scripts/download-linux-mint.sh`) — FIXED
- **Root cause:** `curl` used `--retry 8` and `--continue-at -` against a single mirror URL without stall detection (`--speed-limit`/`--speed-time`) or recovery from HTTP 416 / corrupted `.part` state.
- **Fix:** Added `--speed-limit 10240 --speed-time 60`, multi-mirror fallback via `LINUX_MINT_MIRROR_URLS`, automatic clean retry (`rm -f` on `.part`) when resume fails, while preserving `--http1.1`, GPG `VALIDSIG` enforcement, and `rm -f -- "$ISO_PATH"` on hash mismatch.

### 2. CI Failure Masking on Partial Installed Boots & Missing Secure Boot (`iso-and-qemu-validation.yml`, `run-qemu-validation.sh`) — FIXED
- **Root cause:**
  - Historical CI run `46087428882` (`lite-lxqt-main`) recorded `"iboot": "2/3"` (1 of 3 installed boots failed) yet passed the workflow gate because the inline Python gate only checked `installed_boot_successes == 0` on primary tiers and ignored secondary tiers (`512M`, `768M`, `2048M`), failed systemd units, recovery confirmation guards, manual extra-partition preservation, and missing `secure_boot` runs.
  - `run-qemu-validation.sh` Stage 1 boot verification allowed a passing result when `serial.log` was empty/black without requiring non-black VGA pixels, and lacked a `--strict` exit gate.
- **Fix:**
  - Tightened `.github/workflows/iso-and-qemu-validation.yml` across `matrix`, `phase125`, and `phase130` modes to fail on **any** partial boot failure (`installed_boot_successes < installed_boot_attempts`), any `uefi_boot`/`bios_boot`/`live`/`install`/`persistence` failure across every tested RAM tier, non-zero `failed_systemd_units`, missing `recovery` or `manual` preservation flags, failed/unmapped browser benchmarks, or skipped/unsigned Secure Boot chains.
  - Added `--strict` failure gates to `linux/test/run-qemu-validation.sh`, `linux/test/run-phase125-tests.sh`, and `linux/test/run-phase130-tests.sh`, and tightened Stage 1 UEFI/BIOS ISO boot checks to require `non_black_pct > 0`.

### 3. Live & Installed Firewall Disabled by Default (`"firewall": "disabled"`) — FIXED
- **Root cause:** Chroot builds passed `--skip-ufw` to avoid `iptables` kernel-module failures inside unprivileged chroots, leaving `/etc/ufw/ufw.conf` at `ENABLED=no`, and `nexus-disk-install.sh` never enabled UFW on `$TARGET`. As a result, `nexus-security-audit` reported `"firewall": "disabled"` on every live and installed VM in run `46087428882`.
- **Fix:**
  - Added `--ufw-offline` to `linux/mint/provision-nexus-guest.sh`, `linux/lite/provision-nexus-lite.sh`, and `linux/lite/scripts/provision-nexus-lite-lxqt.sh` to set `/etc/ufw/ufw.conf` `ENABLED=yes`, `/etc/default/ufw` `DROP`/`ACCEPT`/`DROP`, and `systemctl enable ufw.service` cleanly inside chroots (preserving `--skip-ufw` for isolated unit tests).
  - Updated `linux/build/build-nexus-iso.sh` to pass `--ufw-offline` during ISO builds.
  - Updated `linux/installer/nexus-disk-install.sh` to persist `ENABLED=yes`, default `DROP`/`ACCEPT`/`DROP`, and `ufw.service` enablement on `$TARGET`.

### 4. Legacy BIOS Installation & `grub-pc-bin` Packaging Gap — FIXED
- **Root cause:** All 5 package manifests only included `grub-efi-amd64-bin` (omitting `grub-pc-bin`), and `nexus-disk-install.sh` hard-coded UEFI `ESP` partitioning and `grub-install --target=x86_64-efi`. Legacy BIOS hardware could boot the hybrid ISO via SeaBIOS/ISOLINUX but could not install a bootable system via `nexus-disk-install.sh`.
- **Fix:**
  - Added `core:grub-pc-bin` to `linux/config/mint-packages.list`, `linux/config/cinnamon-packages.list`, `linux/lite/lite-packages.list`, `linux/lite/manifests/lite-openbox-packages.list`, and `linux/lite/manifests/lite-lxqt-packages.list`.
  - Added `--boot-mode auto|uefi|bios` to `linux/installer/nexus-disk-install.sh` with GPT `bios_grub` (`1MiB–3MiB`, `bios_grub on`) + `grub-install --target=i386-pc` support, guard rejecting invalid combinations (`--boot-mode bios --keep-efi`), and `boot_mode` metadata in `/etc/nexus-installed.json`.

### 5. Missing `cryptsetup` Packages in Standard Cinnamon / Xfce Manifests — FIXED
- **Root cause:** `linux/config/mint-packages.list` and `linux/config/cinnamon-packages.list` omitted `cryptsetup` and `cryptsetup-initramfs`, risking LUKS2 install failures if the base ISO lacked them or purged live packages.
- **Fix:** Added `core:cryptsetup` and `core:cryptsetup-initramfs` to both `linux/config/mint-packages.list` and `linux/config/cinnamon-packages.list`.

### 6. System Bridge Installer Launch & Graphical Blocker Dialog — FIXED
- **Root cause:** `linux/mint/nexus-system-bridge.py` (`ALLOWLISTED_TOOLS["installer"]`) invoked `["nexus-installer-launcher"]` without `--launch`, causing launcher refusal (`exit 1`) whenever invoked from the UI Settings/Welcome installer button. Additionally, `nexus-installer-launcher.sh` only printed to `stderr` when blocking a graphical launch on non-TTY calls (`DISPLAY` set, low RAM or missing root).
- **Fix:** Updated `nexus-system-bridge.py` to pass `["nexus-installer-launcher", "--launch"]`, and added GUI dialog/notification fallbacks (`zenity`, `yad`, `xmessage`, `notify-send`) to `nexus-installer-launcher.sh`.

### 7. Ubiquity GTK Navigation & Lite-LXQt Initial Screen Capture Timing — FIXED
- **Root cause:** In `linux/test/nexus-guest-test.py`, Ubiquity GTK3 screen walkthrough sent `Return` while the Language TreeView held focus, leaving `ubiquity_ui` at `qualification_tier: "launch_only"` across all editions. Separately, `lite-lxqt` captured `desktop_ready` 0.5s after `pcmanfm-qt` mapped its X11 window before the 1920×1080 wallpaper PNG finished decoding on `512M` TCG (`b1_01_desktop_initial` = `0.02%` non-black vs `94.31%` post-close).
- **Fix:** Updated `linux/test/nexus-guest-test.py` to send `Alt+C` (`["alt", "c"]`, GTK `_Continue` accelerator) with `Return` fallback for Ubiquity navigation, and added a 2.5s settle + `xrefresh` guard for `lite-lxqt` prior to `desktop_ready`.

### 8. Browser Benchmark Cold-Start & Software-Rendering Timeout (`nexus-browser-bench.py`) — FIXED
- **Root cause:** Under QEMU software rendering (`llvmpipe`/`bochs-drm`), Falkon (`QtWebEngine`) took ~28s for `webgl.html` and >30s on cold-start `tab_1`, causing `load_ms: null` timeouts on `tab_1`, `tabs_4`, and `tabs_6`.
- **Fix:** Extended per-stage beacon wait from `30s` to `45s` automatically when `not gpu_env["bare_metal_gpu_qualified"]`.

---

## Verification Evidence

### Local Validation (Post-Fix)
- `npm test` (`scripts/check-foundation.sh` including `shellcheck`, Python compile/bridge tests, Phase 23/24/24.1 checks, and `scripts/check-audit-reliability.js`): **PASS**
- `bash linux/test/test-installer-safety.sh` (preflight, refusal guards, `--boot-mode bios`, manual/dual-boot/LUKS2 dry-runs, recovery diagnostics, provisioners): **PASS**
- `bash linux/security/nexus-security-audit.sh --repo-only --repo . --strict`: **PASS** (`pass=2, warn=0, fail=0`)

### Remote CI Validation (`iso-and-qemu-validation.yml`)
- **Run `46160439413`** (`NEXUS checks and browser preview`): **PASS** (`success`).
- **Run `46160439410`** (`iso-and-qemu-validation.yml`, started on `83e709b`): `plan` **PASS**; all 10 active build jobs (`lite-lxqt-*`, `cinnamon-2048`, `lite-openbox-*`) cleared `Download and GPG-verify Linux Mint 22.3` and `Build and verify NEXUS ... ISO` with zero build/verify errors and entered live QEMU / Phase 12.5 / Phase 13.0 execution. Note: local audit fixes from Batches 1–5 will trigger a fresh CI validation run upon push.
