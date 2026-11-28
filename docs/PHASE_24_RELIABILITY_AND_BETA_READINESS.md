# NEXUS OS — Phase 24: Final Reliability, Cross-Edition Stabilisation & Beta Readiness

**Date:** 2026-11-28  
**Branch:** `arena/f18c36a4-nexus-os` (`main` untouched at `0c05070410c2adaa2f7f2e95d23676380efdcf66`)  
**Scope:** End-to-end code audit and reliability stabilisation across all four NEXUS OS editions (`cinnamon`, `xfce`, `lite-lxqt`, `lite`), the native loopback bridge + desktop shell UI, desktop launchers, installer/first-boot integration, and provisioning scripts.

---

## 1. Defects Identified & Resolved

| # | Area | Root Cause | Resolution | Verification |
|---|---|---|---|---|
| 1 | Native Bridge Terminal (`apps/native-services.js`, `apps/terminal.js`) | `native-services.js` returned an async `Promise` from `openSession` without polling `/api/terminal/read`, while `terminal.js` read `opened?.sessionId` synchronously — causing live bridge sessions to fail immediately. | Added `/api/terminal/read` polling with clean `closeSession` teardown in `apps/native-services.js`; updated `apps/terminal.js` to support both synchronous preview test adapters and Promise-based bridge PTY sessions cleanly. | `scripts/check-terminal-preview.js` (sync), `scripts/check-phase24-reliability.js` (async bridge PTY). |
| 2 | Quantum Deep-Link & Launcher UX (`app.js`, `linux/branding/nexus-launch-app.sh`, `.desktop` entries) | `nexus-quantum.desktop` launched `index.html#quantum`, but `app.js` ignored `window.location.hash` on startup. `Terminal=true` `.desktop` entries and CLI status launchers exited immediately without letting users read output. | Added `openAppFromHash()` + `hashchange` listener in `app.js`; added `run_in_terminal_wait` for non-interactive status CLIs in `nexus-launch-app.sh` (preserving direct `run_in_terminal` for `store`/`firstboot`); added `notify-send` + clear error when no browser is installed for `quantum`; updated `nexus-hw-diagnostics.desktop`, `nexus-recovery.desktop`, and `nexus-security-audit.desktop` to pause for Enter. | `scripts/check-native-launchers.sh`, `scripts/check-phase21-ecosystem.js`, `scripts/check-phase24-reliability.js`. |
| 3 | Lite Openbox Menu & Autostart (`linux/lite/openbox/menu.xml`, `linux/lite/openbox/autostart`) | `menu.xml` invoked `nexus-installer-launcher` without `--launch` (exiting with status 2); `autostart` omitted `/usr/local/bin/nexus-firstboot --autostart` even though pure Openbox does not process `/etc/xdg/autostart/*.desktop`. | Changed Openbox menu entry to `nexus-installer-launcher --launch` and added guarded one-time `/usr/local/bin/nexus-firstboot --autostart &` to `openbox/autostart`. | `scripts/check-phase24-reliability.js`, `scripts/check-phase18-integration.js`. |
| 4 | Lite Openbox Appearance Flag (`linux/lite/apply-nexus-lite.sh`) | `--appearance dark|light` validated the flag and discarded `$2` without mapping `light` to `arctic` or persisting `appearance` in `lite-profile`. | Persisted `APPEARANCE`, defaulted `THEME="arctic"` when `--appearance light` is passed without `--theme`, and wrote `appearance=...` into `lite-profile`. | `scripts/check-phase24-reliability.js`. |
| 5 | Performance Wallpaper Cache Path (`linux/mint/nexus-performance-cli.sh`, `scripts/check-phase20-performance.js`) | `nexus-performance-cli.sh` previewed and cleaned `$XDG_DATA_HOME/nexus-os/wallpapers` instead of `$XDG_CACHE_HOME/nexus-os/wallpapers` used by `nexus-wallpaper-cli.sh` and `apply-nexus-cinnamon.sh`. | Aligned `cleanup_preview` and `cleanup --target wallpapers --confirm` to `$XDG_CACHE_HOME/nexus-os/wallpapers` and updated `check-phase20-performance.js` accordingly. | `scripts/check-phase20-performance.js`. |
| 6 | Gaming / Low-Resource Theme Preservation (`linux/mint/nexus-gaming-cli.sh`, `linux/mint/nexus-performance-cli.sh`) | Toggling `gaming-mode` or `low-resource` on LXQt/Openbox overwrote saved theme/accent/appearance in `lite-profile` (and `nexus-gaming-cli.sh` used `lite-1g` on LXQt `enable`). | Added `lite_saved_args()` to preserve saved `theme`, `accent`, and `appearance` across mode toggles and aligned LXQt `gaming-mode enable` to `lite-512`. | `scripts/check-phase24-reliability.js`. |
| 7 | Cinnamon Wallpaper Sync & Validation (`linux/cinnamon/apply-nexus-cinnamon.sh`) | `--wallpaper-url` skipped image magic-byte validation on HTTPS downloads and did not update `~/.config/nexus-os/wallpaper.conf`. | Added JPEG/PNG/WebP/SVG magic-byte validation before committing cached downloads and persisted `WALLPAPER_ID`, `WALLPAPER_PATH`, and `WALLPAPER_FIT` to `wallpaper.conf`. | `scripts/check-phase24-reliability.js`, `scripts/check-phase17-personalisation.js`. |
| 8 | Edition Detection Typo (`linux/mint/nexus-wallpaper-cli.sh`, `linux/mint/nexus-control-centre-cli.sh`) | `detect_edition` checked `/etc/nexus-os/edition` instead of `/etc/nexus-os-release` (`NEXUS_EDITION=`). | Updated both `detect_edition` paths to parse `NEXUS_EDITION=` from `/etc/nexus-os-release` first (keeping `/etc/nexus-os/edition` as fallback). | `scripts/check-phase24-reliability.js`. |
| 9 | Provisioner UI & Edition Metadata Parity (`linux/mint/provision-nexus-guest.sh`, `linux/lite/provision-nexus-lite.sh`, `linux/lite/scripts/provision-nexus-lite-lxqt.sh`) | `provision-nexus-guest.sh` omitted `NEXUS_EDITION` in `/etc/nexus-os-release`, and none of the standalone guest provisioners staged `/usr/local/share/nexus-os/ui/`. | Added `NEXUS_EDITION="$detected_de"` to `provision-nexus-guest.sh` and staged the offline UI bundle under `/usr/local/share/nexus-os/ui/` across all three provisioners. | `scripts/check-phase24-reliability.js`. |

---

## 2. Verification Summary

All local checks ran after the final Phase 24 code and test edits:

- `PATH="/tmp/sc-tmp/bin:$PATH" npm test` — **PASS** (`bash -n` on 48 scripts, `shellcheck` across all foundation scripts, config/dry-run CLI checks, `check-linux-bridge.py`, `check-native-services-reliability.py`, `check-phase15-integration.py`, `node --check` on all 23 JS files, `check-prototype.sh` including Phases 18–24 and `check-native-launchers.sh`, asset/icon integrity, and no `eval`/`Function` usage).
- `bash linux/test/test-installer-safety.sh` — **PASS** (all preflight, refusal, dual-boot, LUKS, QEMU path/qcow2, and recovery safety assertions).
- `bash linux/security/nexus-security-audit.sh --strict` — **PASS** (exit `0`; `pass: 2`, `warn: 1` for container Debian APT mirrors, `fail: 0`).
- `bash linux/test/run-virtual-qualification.sh --edition lite-lxqt --skip-foundation --out-dir /tmp/p24-qual` — **PASS** (`PASS=10 FAIL=0 BLOCKED=2 NOT TESTED=16`; `qemu-system-x86_64`/`xorriso` are absent in this sandbox and run in GitHub Actions).

### GitHub Actions CI Status

- Prior commit `9e3216111ca2c8bb61e5a627474053addf424e4e`:
  - Foundation CI (`46144398731`): **success**.
  - ISO & QEMU matrix (`46144398688`): all 10 active `Build and verify NEXUS <edition> ISO` steps **succeeded** and entered QEMU/Phase 12.5/Phase 13.0 runs (expected to be superseded by the Phase 24 push due to `concurrency.cancel-in-progress: true`).
  - Baseline full 14-job ISO & QEMU matrix (`46087428882`): **success** across all 4 editions (`lite-lxqt`, `lite`, `cinnamon`, `xfce`).
- Full ISO build + QEMU/OVMF matrix for the Phase 24 commit triggers automatically on push to `arena/f18c36a4-nexus-os`.

---

## 3. Beta Readiness Conclusion

With Phase 24 fixes and regression tests in place, all verified cross-edition scripting, bridge PTY streaming, launcher deep-linking, personalisation state preservation, and installer safety paths pass local automated verification. Full ISO + live QEMU/OVMF validation across all four editions remains tracked by `.github/workflows/iso-and-qemu-validation.yml` upon push.
