# NEXUS OS — Phase 24.1: CI Failure Diagnosis, ISO Pipeline Repair & Requalification

**Date:** 2026-11-28  
**Branch:** `arena/f18c36a4-nexus-os` (`main` untouched at `0c05070410c2adaa2f7f2e95d23676380efdcf66`)  
**Failed Baseline Run:** GitHub Actions [`46147093987`](https://github.com/elrenoremembernado2013-blip/Nexus-OS/actions/runs/46147093987) on commit `f363cbe6cb997beda33c29fc2ba1c984fc5cebc8`

---

## 1. Original CI Failures (`46147093987`)

- `plan`: **PASS**
- All 12 `iso-and-qemu` jobs (`cinnamon`, `cinnamon-2048`, `xfce`, `lite-openbox-compare`, `lite-openbox-browser-bench`, `lite-lxqt-main`, `lite-lxqt-512`, `lite-lxqt-768`, `lite-lxqt-1024`, `lite-lxqt-installer-luks`, `lite-lxqt-browser-bench`, `lite-lxqt-phase130`): **FAIL** at Step 7 (`Build and verify NEXUS <edition> ISO`).
  - Steps 1–6 (checkout, disk reclaim, dependency installation, script/manifest/security validation, and Linux Mint 22.3 base ISO download + GPG verification) **passed**.
  - Steps 8–10 (QEMU RAM matrix, Phase 12.5, Phase 13.0) were **skipped** due to the upstream ISO build failure.
- `compare-lite-report`: **FAIL** downstream because `!cancelled()` allowed it to run after upstream ISO/QEMU jobs failed, producing missing Openbox/LXQt JSON errors and a redundant `if: always()` artifact upload failure.

---

## 2. Precise Root Cause & Evidence

In Phase 24 (`897c640` / `f363cbe`), all three edition provisioners (`linux/mint/provision-nexus-guest.sh`, `linux/lite/provision-nexus-lite.sh`, and `linux/lite/scripts/provision-nexus-lite-lxqt.sh`) were updated to stage the offline NEXUS desktop shell UI bundle from `$REPO_ROOT`:

- `$REPO_ROOT/index.html` -> `/usr/local/share/nexus-os/ui/index.html`
- `$REPO_ROOT/app.js` -> `/usr/local/share/nexus-os/ui/app.js`
- `$REPO_ROOT/styles.css` -> `/usr/local/share/nexus-os/ui/styles.css`
- `$REPO_ROOT/apps` -> `/usr/local/share/nexus-os/ui/apps`
- `$REPO_ROOT/assets` -> `/usr/local/share/nexus-os/ui/assets`

However, `linux/build/build-nexus-iso.sh` (used by all four editions: `cinnamon`, `xfce`, `lite`, `lite-lxqt`) staged **only** `linux/`, `LICENSE`, and `docs/` into `$squash_root/tmp/nexus-repo/` before entering chroot:

```bash
mkdir -p -- "$squash_root/tmp/nexus-repo"
cp -a "$REPO_ROOT/linux" "$squash_root/tmp/nexus-repo/linux"
cp -a "$REPO_ROOT/LICENSE" "$squash_root/tmp/nexus-repo/LICENSE"
cp -a "$REPO_ROOT/docs" "$squash_root/tmp/nexus-repo/docs"
```

Inside the chroot, `$REPO_ROOT` resolved to `/tmp/nexus-repo`. Because `index.html`, `app.js`, `styles.css`, `apps/`, and `assets/` were absent from `/tmp/nexus-repo`, `install -m 0644 "$REPO_ROOT/index.html" ...` exited non-zero immediately under `set -euo pipefail` across all four editions before `apply-iso-branding.sh`, `mksquashfs`, `xorriso`, or `verify-nexus-iso.sh` could run.

---

## 3. Fixes Implemented

| File | Change |
|---|---|
| `linux/build/build-nexus-iso.sh` | Validated and staged `index.html`, `app.js`, `styles.css`, `apps/`, and `assets/` alongside `linux/`, `LICENSE`, and `docs/` into `$squash_root/tmp/nexus-repo/`. Enabled `set -eEuo pipefail` with `CURRENT_STAGE` tracking and an `on_error()` `ERR` trap emitting `BUILD STAGE FAILED: stage=... edition=... exit=... out_iso=... iso_exists=... iso_size=... cmd=...`. Updated `--dry-run` output accordingly. |
| `linux/lite/build-nexus-lite-iso.sh` | Passed `--edition lite` on `--check` (`check-build-prereqs.sh --edition lite`) for parity with `lite-lxqt`. |
| `linux/build/verify-nexus-iso.sh` | Added `VERIFY STAGE FAILED` diagnostics, verified `build-info.json` `edition` and `output_iso` match `--edition` and the target ISO path, and verified `/usr/local/share/nexus-os/ui/{index.html,app.js,styles.css,apps/terminal.js}` exist in `filesystem.squashfs`. |
| `.github/workflows/iso-and-qemu-validation.yml` | Separated `build_cmd` and `verify-nexus-iso.sh` exit-code reporting in `Build and verify NEXUS <edition> ISO` with explicit `NEXUS-ISO-BUILD-FAIL-*` and `NEXUS-ISO-VERIFY-FAIL-*` annotations (reporting edition, command, rc, output path, `iso_exists`, `iso_bytes`, and log tail). Gated `compare-lite-report` on `if: ${{ success() && (...) }}` and changed its upload step from `if: always()` to `if: success()` so upstream ISO build failures are never obscured while missing-input diagnostics remain strict when upstream succeeds. |
| `scripts/check-phase24-1-iso-pipeline.js` & `scripts/check-prototype.sh` | Added Phase 24.1 regression suite reproducing the chroot staging gap and testing all 4 edition entry points, edition package/config isolation, `apply-iso-branding.sh` across all 4 editions, `verify-nexus-iso.sh` failure paths (missing ISO, <500 MiB ISO, SHA-256 mismatch, edition mismatch), missing-tool `check-build-prereqs.sh --strict`, non-root `build-nexus-iso.sh` refusal, and workflow gating/diagnostics. |

---

## 4. Local & Host Verification Status

- `PATH="/tmp/sc-tmp/bin:$PATH" npm test`: **PASS** (bash syntax on 48 scripts, ShellCheck, `check-linux-bridge.py`, `check-native-services-reliability.py`, `check-phase15-integration.py`, `node --check` on 23 JS files, `check-prototype.sh` including Phases 18–24.1 and `check-native-launchers.sh`).
- `bash linux/test/test-installer-safety.sh`: **PASS**.
- `bash linux/security/nexus-security-audit.sh --strict`: **PASS** (`pass: 2`, `warn: 1` for container Debian APT mirrors, `fail: 0`).
- `bash linux/test/run-virtual-qualification.sh --edition lite-lxqt --skip-foundation --out-dir /tmp/p241-qual`: **PASS** (`PASS=10 FAIL=0 BLOCKED=2 NOT TESTED=16`; `xorriso`, `mksquashfs`, `unsquashfs`, and `qemu-system-x86_64` are not installed in this container sandbox).
- Four-edition live ISO remastering (`cinnamon`, `xfce`, `lite-lxqt`, `lite`) and QEMU/OVMF RAM matrix qualification run in GitHub Actions (`.github/workflows/iso-and-qemu-validation.yml`) on push because container sandboxes lack root ISO remastering/KVM/QEMU tooling.

---

## 5. Remaining Blockers

- Live ISO builds and QEMU/OVMF execution cannot run locally inside the unprivileged container sandbox (`xorriso`, `mksquashfs`, `unsquashfs`, `qemu-system-x86_64` absent; root required for `mount --bind`/`chroot`) and are validated via GitHub Actions `.github/workflows/iso-and-qemu-validation.yml`.
