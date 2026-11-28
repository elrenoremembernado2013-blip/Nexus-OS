# NEXUS OS Four-Edition ISO Qualification, Testing & Glitch-Fix Report

- **Branch:** `arena/f18c36a4-nexus-os` (`main` untouched at `0c05070410c2adaa2f7f2e95d23676380efdcf66`)
- **Base Commit Audited:** `6d6deecf71a9cbbada2a352747329abd444ec49c` (with full 12-job completed baseline CI run on `3ebd89dda1e1c27506d4e74cc3d08786abb4b2c4`)
- **Validation Date:** `2026-11-28` (UTC)
- **Status Vocabulary:** `PASS`, `FAIL`, `BLOCKED`, `NOT TESTED`

---

## 1. Provenance, CI Runs & Sandbox Artifact Access Note

| Artifact / Evidence Source | Reference / Commit | Current State | Verification Scope |
|---|---|---|---|
| Baseline Full-Matrix CI Run | [`46087428882`](https://github.com/elrenoremembernado2013-blip/Nexus-OS/actions/runs/46087428882) (`3ebd89d`) | `PASS` (12/12 matrix/phase jobs + `compare-lite-report` succeeded) | Full ISO builds, `verify-nexus-iso.sh`, QEMU OVMF UEFI + 3-reboot + LUKS2 + manual/recovery + dual-boot + Secure Boot + browser bench + `NEXUS-16-SVC` telemetry |
| Pre-Fix Head CI Run | [`46142043533`](https://github.com/elrenoremembernado2013-blip/Nexus-OS/actions/runs/46142043533) (`6d6deec`) | `plan` `PASS`; 10 jobs reached ISO build / QEMU execution (`in_progress`, 2 `queued`) at report cutoff | Verified `6d6deec` builds & enters QEMU across editions; superseded upon pushing the fix commit to `arena/f18c36a4-nexus-os` (`concurrency.cancel-in-progress: true`) |
| Prototype CI Run | [`46142043513`](https://github.com/elrenoremembernado2013-blip/Nexus-OS/actions/runs/46142043513) (`6d6deec`) | `PASS` | Full Node/JS prototype & foundation syntax checks |
| Local Sandbox Suite + Live Bridge | Current fix commit on `arena/f18c36a4-nexus-os` | `PASS` | `npm test` (with `shellcheck`), `npm run check:prototype`, `test-installer-safety.sh`, `nexus-security-audit.sh --repo-only --strict`, `check-native-launchers.sh`, `run-virtual-qualification.sh --edition lite-lxqt`, live loopback `nexus-system-bridge.py` test |
| Direct Artifact Binary Downloads | `productionresultssa1.blob.core.windows.net` | `BLOCKED` (in this sandbox) | Sandbox outbound egress is restricted to `github.com`, `codeload.github.com`, `api.github.com`, `registry.npmjs.org`, `pypi.org`, `files.pythonhosted.org`; raw `.iso` / `.png` / `.log` zip downloads fail with `EOF` in-sandbox, so CI ISO/QEMU metrics are taken directly from `api.github.com` check-run annotations (`NEXUS-ISO-*`, `NEXUS-124-*`, `NEXUS-16-SVC-*`, `NEXUS-125-*`, `NEXUS-130-*`). |

> **Truthfulness guarantee:** Zero test results are invented or interpolated. Raw ISO binary inspection inside this sandbox is `BLOCKED` by egress filtering, and bare-metal physical hardware tests are `NOT TESTED` (QEMU TCG + OVMF virtualized results are never treated as physical hardware compatibility).

---

## 2. Independent Four-Edition ISO Build & Isolation Matrix

All four editions build from verified Linux Mint 22.3 (`noble` / `x86_64`) upstream ISOs via `linux/build/build-nexus-iso.sh` with distinct config files, package manifests, output filenames, squashfs payloads, and SHA-256 checksums:

| Edition | Config & Provisioner | Output ISO Filename (Observed CI Sizes & SHA-256 from `46087428882`) | DE / WM / Panel | Packages (Essential + Optional) | Lite Bloat Exclusion | Status |
|---|---|---|---|---|---|---|
| **NEXUS Standard — Cinnamon** | `linux/config/nexus-standard-cinnamon.conf` + `provision-nexus-guest.sh` | `nexus-os-22.3-cinnamon-amd64.iso` (`3,089,281,024` B, SHA-256 `72d1f8c79bf4a63cf54958241cbd91baace52558ccc78a84df5085ae3c12d82d`) | Cinnamon / Muffin / Cinnamon panel | 21 + 9 | N/A (Flagship full desktop) | `PASS` |
| **NEXUS XFCE** | `linux/config/nexus-system.conf` + `provision-nexus-guest.sh` | `nexus-os-22.3-xfce-amd64.iso` (`3,030,503,424` B, SHA-256 `ebf931657b4a0ee3f6c5b9c7e267411bbf6f4f22806952d0d5bad4390b1ac17b`) | XFCE / Xfwm4 / `xfce4-panel` | 20 + 9 | No Cinnamon shell | `PASS` |
| **NEXUS Lite — LXQt** | `linux/lite/nexus-lite-lxqt.conf` + `provision-nexus-lite-lxqt.sh` | `nexus-os-22.3-lite-lxqt-amd64.iso` (`2,874,503,168` B, SHA-256 `c64f732fc1b31e093e28f8c6bf618048de83e6c71af08d62c93ab3f2e7fbb1fc`) | LXQt / Openbox / `lxqt-panel` | 49 + 4 | Zero `steam-installer`, `wine`, `waydroid`, `cinnamon*`, `firefox`, `libreoffice`, `thunderbird`, `xfce4-*`; `--purge-bloat` enforced | `PASS` |
| **NEXUS Lite — Openbox** | `linux/lite/nexus-lite.conf` + `provision-nexus-lite.sh` | `nexus-os-22.3-lite-amd64.iso` (`2,843,742,208` B, SHA-256 `441edc58914412014bbba1de5d7cff88c28ad62a45c02db2d6462a388233a8f8`) | Openbox / `tint2` | 37 + 3 | Zero `steam-installer`, `wine`, `waydroid`, `cinnamon*`, `firefox`, `libreoffice`, `thunderbird`, `xfce4-*`; `--purge-bloat` enforced | `PASS` |

- **Production/Test Separation (`verify-nexus-iso.sh` + `nexus-security-audit.sh`):** Verified zero `nexus-test*`, `casper-test*`, `99nexus_test_harness`, or `org.nexus.test.0` references exist in production ISO initramfs or squashfs (`PASS` in CI `verify-nexus-iso.sh` and local `nexus-security-audit.sh --strict`).
- **Squashfs Payload Verification (`verify-nexus-iso.sh`):** Confirmed `/usr/local/bin/nexus-system-bridge`, `/etc/systemd/user/nexus-system-bridge.service`, and `/usr/local/share/nexus-os/ui/index.html` exist in all built ISOs (`PASS`).

---

## 3. VM Boot, Graphical Desktop & Persistence Matrix (QEMU TCG)

| Edition & RAM | UEFI Live Boot | Legacy BIOS Boot | Live Desktop & Apps | Installed Boots (No ISO) | Persistence Across Reboots | Screenshot `non_black_pct` Notes (Pre-Fix CI `46087428882`) |
|---|---|---|---|---|---|---|
| **Standard Cinnamon** (`2048M` / `4096M`) | `PASS` (`1/1` / `3/3`) | Catalog `PASS`; QEMU runtime `NOT TESTED` (`--bios-check` not passed in CI) | `PASS` (`nemo`, `gnome-terminal`, `cinnamon-settings`, `xed` verified) | `PASS` (`3/3` at both 2048M & 4096M, `err=0`, `fail_u=0`) | `PASS` | **Glitch found & fixed:** `b1_01_desktop_initial` = `0.0%` and installed Boot 1–2 apps = `0.03%` due to X11/Cinnamon screensaver/DPMS blanking + single-channel R sampling; jumped to `96.64%–97.95%` on key wake. |
| **XFCE** (`2048M` / `4096M`) | `PASS` (`1/1` / `3/3`) | Catalog `PASS`; QEMU runtime `NOT TESTED` | `PASS` (`thunar`, `xfce4-terminal`, `xfce4-settings-manager`, `xed` verified) | `PASS` (`3/3` at 4096M, `err=0`, `fail_u=0`) | `PASS` | **Glitch found & fixed:** Live `b1_01_desktop_initial` & `b1_06_post_close` = `0.0%` (Boot 1 initial `0.03%`, Boot 2/3 `4.15%`) due to DPMS/screensaver blanking after `wm_ready`. |
| **Lite LXQt** (`512M` / `768M` / `1024M` / `2048M` / `4096M`) | `PASS` (`3/3` at 512M/1024M; `1/1` at 768M/2048M/4096M) | Catalog `PASS`; QEMU runtime `NOT TESTED` | `PASS` (`pcmanfm-qt`, `qterminal`, `lxqt-config`, `featherpad` verified) | `PASS` at `512M` (`3/3`), `768M` (`3/3`), `1024M` (`3/3`); `2/3` at `2048M` (cold Boot 3 incomplete in `46087428882`) | `PASS` | **Glitch found & fixed:** Live `b1_01_desktop_initial` = `0.02%` (768M installed = `0.02%`) because `pcmanfm-qt` pointed to `.svg` wallpaper without `libqt5svg5` + dark `#070b16` stops; fixed with crisp `wallpaper-nexus-obsidian.png`. Also fixed `fb_auto=False` -> `True`. |
| **Lite Openbox** (`512M` / `768M` / `1024M` / `2048M` / `4096M`) | `PASS` (`3/3` at 512M/1024M; `1/1` at 768M/2048M/4096M) | Catalog `PASS`; QEMU runtime `NOT TESTED` | `PASS` (`pcmanfm`, `lxterminal`, `obconf`, `mousepad` verified) | `PASS` (`3/3` at `1024M`, `err=0`, `fail_u=0`) | `PASS` | `100.0%` initial desktop, `99.92%–99.98%` apps (`1024M` live `b1_06_post_close` hit `0.0%` DPMS edge case; fixed in guest blanking guard). Also fixed `fb_auto=False` and `WALLPAPER_FIT` persistence. |

- **Legacy BIOS Status Explanation:** All four ISOs include verified El Torito BIOS bootloaders (`isolinux/isolinux.bin` verified by `verify-nexus-iso.sh`) and `run-qemu-validation.sh --bios-check` dry-run wiring is verified (`PASS`), while actual SeaBIOS QEMU matrix boots were not enabled in CI run `46087428882` (`NOT TESTED`).

---

## 4. RAM & Performance Matrix (`46087428882` QEMU TCG Telemetry)

| Edition | RAM Tier | Boot & Usability | Live Login Used (MiB) | Live Idle Used (MiB) | Live Swap / ZRAM (MiB / Ratio) | Live CPU Idle (%) | WM / Panel Ready (s) | OOM Kills | Tier Classification |
|---|---|---|---|---|---|---|---|---|---|
| **Cinnamon** | `2048 MiB` | `PASS` (boots & installs; tight headroom) | `433` | `897` | `0` / `N/A` | `0.0%` | `27.3s` / `67.3s` | `0` | **Minimum Bootable** |
| **Cinnamon** | `4096 MiB` | `PASS` (responsive multi-app & installer) | `513` | `969` | `0` / `N/A` | `0.0%` | `32.3s` / `77.4s` | `0` | **Recommended** |
| **XFCE** | `2048 MiB` | `PASS` (comfortable live & app usage) | `390` | `711` | `0` / `N/A` | `0.0%` | `30.7s` / `52.9s` | `0` | **Minimum Bootable** |
| **XFCE** | `4096 MiB` | `PASS` (smooth multi-reboot & installer) | `518` | `793` | `0` / `N/A` | `1.0%` | — | `0` | **Recommended** |
| **Lite LXQt** | `512 MiB` | `PASS` (slow startup; heavy ZRAM swap) | `187` | `268` | `158` / `4.43x` (`PASS`) | `0.0%` | `103.1s` / `141.7s` | `0` | **Minimum Experimental** |
| **Lite LXQt** | `768 MiB` | `PASS` (desktop & install ok; ZRAM active) | `340` | `402` | `121` / `4.06x` (`PASS`) | `0.0%` | `81.6s` / `100.9s` | `0` | Usable Light |
| **Lite LXQt** | `1024 MiB` | `PASS` (minimal swap; fast installed reboots) | `383` | `544` | `2` / `3.62x` (`PASS`) | `0.0%` | `47.9s` / `59.2s` | `0` | **Recommended Lite** |
| **Lite LXQt** | `2048 MiB` | `PASS` live (`2/3` inst boots in `46087428882`) | `398` | `571` | `1` / `2.79x` (`PASS`) | `0.0%` | `38.2s` / `48.8s` | `0` | Comfortable + Browser |
| **Lite LXQt** | `4096 MiB` | `PASS` (zero swap pressure) | `515` | `646` | `0` / `—` (`PASS`) | `0.0%` | `35.8s` / `46.2s` | `0` | Full Desktop Headroom |
| **Lite Openbox** | `512 MiB` | `PASS` (fastest 512 MiB boot; ZRAM active) | `208` | `234` | `127` / `4.34x` (`PASS`) | `1.0%` | `29.6s` / `49.1s` | `0` | **Minimum Experimental** |
| **Lite Openbox** | `768 MiB` | `PASS` | `334` | `381` | `40` / `4.47x` (`PASS`) | `0.0%` | `23.2s` / `40.4s` | `0` | Usable Ultra-Light |
| **Lite Openbox** | `1024 MiB` | `PASS` (3/3 live & 3/3 installed reboots) | `375` | `459` | `1` / `3.09x` (`PASS`) | `0.0%` | `23.1s` / `38.0s` | `0` | **Recommended Lite** |
| **Lite Openbox** | `2048 MiB` | `PASS` | `388` | `483` | `1` / `2.79x` (`PASS`) | `0.0%` | `23.2s` / `38.3s` | `0` | Comfortable + Browser |
| **Lite Openbox** | `4096 MiB` | `PASS` | `533` | `571` | `0` / `—` (`PASS`) | `0.0%` | `19.0s` / `33.7s` | `0` | Full Desktop Headroom |

- **Browser Benchmark (`1024M` / `2048M` / `4096M`, `46087428882`):** Both `falkon` and `firefox` ran 1–6 tabs with `0` OOM kills and `0` crashes on both Lite LXQt and Lite Openbox (`PASS`); at `1024M`, `firefox` completed 6/6 tabs (`234–800 MiB` RSS, `~249 MiB` ZRAM) while `falkon` completed 1–2/6 timed loads cleanly under `30s` TCG limit.

---

## 5. Disposable-Disk Installer & Recovery Matrix

All disk operations run strictly against disposable QEMU `qcow2` disks (`build/qemu-test/`); host disks are never touched (`test-installer-safety.sh` enforces path containment, symlink rejection, and `--yes-erase-disk`).

| Scenario | Evidence Source | Key Verified Behaviour | Status |
|---|---|---|---|
| **Blank Disk Guided Install & Reboot** | `46087428882` (all 4 editions) | Partitioned `/dev/vda`, installed system, removed ISO, booted `/dev/vda`, `mint_user_absent=true` | `PASS` |
| **Manual 3-Partition GPT & Data Preservation** | `46087428882` (`140800209290`) | Custom ESP + root + `nexus_data` (`/dev/vda3`); `preserve-check.txt` survived install & boot | `PASS` |
| **Interrupted-Install Recovery & Safety Guard** | `46087428882` (`140800209290`) + `test-installer-safety.sh` | Refused unconfirmed disk wipe (`refused_without_confirm=true`); cleaned dirty mount and installed cleanly (`failed_systemd_units=0`) | `PASS` |
| **LUKS2 Full-Disk Encryption** | `46087428882` (`140800209290`) | `cryptsetup` prompt seen, wrong passphrase rejected, correct passphrase unlocked `nexus_crypt`, `crypttab` + recovery guide present, persisted across 2 boots | `PASS` |
| **UEFI Secure Boot (`enabled`)** | `46087428882` (`140800209329`) | `secure_boot_state=enabled`, signed PE verified on `shimx64.efi`, `grubx64.efi`, and kernel; booted installed system (`failed_systemd_units=0`) | `PASS` |
| **Simulated Windows/NTFS Dual-Boot** | `46087428882` (`140800209329`) | Preflight detected NTFS; `EFI/Microsoft/Boot/bootmgfw.efi` + `dualboot-ntfs-marker.txt` + `winload.efi` preserved during install & post-boot | `PASS` |
| **Ubiquity GUI Multi-Screen Navigation** | `46087428882` (`cinnamon`, `xfce`, `lite-lxqt`, `lite`) | Launched `ubiquity` (`b1_ub_01_language`..`b1_ub_04_partman` screenshots `94%–98%`); full end-to-end GUI click-through install inside Ubiquity itself is `NOT TESTED` (CLI/automated install uses `nexus-disk-install.sh`) | `PASS` (launch) / `NOT TESTED` (E2E Ubiquity click-through) |

---

## 6. Desktop UI, Core Apps & Native Services Matrix

| Component | Verification Method | Evidence | Status |
|---|---|---|---|
| **Loopback Bridge (`nexus-system-bridge.py`)** | CI `NEXUS-16-SVC` (all 4 editions) + Live sandbox daemon test | Bound strictly to `127.0.0.1` (`wildcard_socket_found=false`), runtime file `0o600`, `401` on missing token or non-loopback `Origin`, `400` with explicit message on missing/unknown tools | `PASS` |
| **Terminal (Real GNU Bash PTY)** | CI `NEXUS-16-SVC` (`pty_bash_ok=true`, `5.2.21(1)-release`) + `npm test` | Real `pty.openpty` + `/bin/bash -i`, disconnect & reap tested | `PASS` |
| **File Manager (`$HOME`-Jailed)** | CI `NEXUS-16-SVC` (`files_jailed_ok=true`) + Live sandbox daemon test | CRUD inside `$HOME` ok; `/etc/passwd`, `.ssh/id_rsa`, `.gnupg/pubring.kbx` all rejected with `HTTP 403` | `PASS` |
| **NEXUS Store** | CI `NEXUS-16-SVC` (`store_sources_ok=true`) + `npm test` | Real `apt`/`flatpak`/`pkexec` detection; protected packages & invalid IDs blocked; lightweight Lite editions omit preinstalled `falkon`/`firefox`/`steam` and report honest install instructions | `PASS` |
| **Quantum** | CI `NEXUS-16-SVC` (`quantum_ok=true`) + `verify-nexus-iso.sh` (`ui/index.html`) | Notes JSON persistence verified; offline UI bundle staged at `/usr/local/share/nexus-os/ui/` | `PASS` |
| **Settings & Control Centre** | CI `NEXUS-16-SVC` (`settings_tools_ok=true`, `settings_launch_ok=true`, `control_centre_ok=true`) + `check-native-launchers.sh` | Edition-specific native launchers (`cinnamon-settings`, `xfce4-settings-manager`, `lxqt-config`, `obconf`) verified | `PASS` |
| **Gaming Hub & Compatibility Centre** | CI `NEXUS-16-SVC` (`gaming_status_ok=true`, `compat_ok=true`) + Live sandbox daemon test | Honest hardware/Vulkan/Steam reporting (`steam_installed=false`, `vulkan=available/unavailable`); `/api/compat/inspect?path=/etc/passwd` rejected `403`; invalid `.exe` launch rejected `400` | `PASS` |
| **Hardware Compatibility & Diagnostics** | CI `NEXUS-16-SVC` (`hw_ok=true`) + Live sandbox daemon test | `privacy_redacted=true`; `privacy_audit.passed=true`; untestable physical components honestly reported as `Unable to test` / `untested` | `PASS` |

---

## 7. Security & Reliability Audit

- `bash linux/security/nexus-security-audit.sh --repo-only --repo . --strict`: `PASS` (`pass=2, warn=0, fail=0`; zero test-only artifacts in production `linux/` directories; installer enforces `--yes-erase-disk` and avoids hardcoded passwords).
- `bash linux/test/test-installer-safety.sh`: `PASS` (37/37 safety, refusal, containment, LUKS, dual-boot, and read-only recovery assertions).
- `PATH="/tmp/sc-tmp/bin:$PATH" npm test` (Foundation + ShellCheck + Prototype + Phase 23): `PASS` (0 errors, 0 ShellCheck warnings).
- Live `nexus-system-bridge.py` audit: `PASS` (`127.0.0.1` only, `0o600` runtime file, `X-Nexus-Token` + `Origin` validation -> `401`, `$HOME` jailing + `.ssh`/`.gnupg`/`.pki`/`.aws`/`.kube` protection -> `403`, zero unhandled crashes or unexpected listeners).

---

## 8. Glitches Found, Root Causes, Minimal Fixes & Regression Tests

1. **Lite LXQt Black/Unrendered Wallpaper (`0.02%` non-black screen):**
   - **Root Cause:** `linux/lite/lxqt/pcmanfm-qt/settings.conf` referenced `wallpaper-nexus-obsidian.svg` while `lite-lxqt-packages.list` uses `--no-install-recommends` without `libqt5svg5`/`libqt6svg6`, and the SVG used `#070b16`–`#081020` dark stops.
   - **Fix:** Added crisp `1920x1080` rendered PNG `linux/lite/lxqt/wallpaper-nexus-obsidian.png` and updated `pcmanfm-qt/settings.conf`, `linux/lite/scripts/provision-nexus-lite-lxqt.sh`, and `linux/build/apply-iso-branding.sh` to install and use it.
2. **Repeated First-Boot Terminal Popup & Lite Autostart Parity (`fb_auto=False`):**
   - **Root Cause:** `linux/branding/nexus-firstboot.desktop` launched `nexus-launch-app firstboot` (spawning an interactive terminal prompt on every login without checking `firstboot-done`), and Lite provisioners omitted `/etc/xdg/autostart/nexus-firstboot.desktop`.
   - **Fix:** Added `--autostart` one-shot guard to `linux/mint/nexus-firstboot.sh`, updated `linux/branding/nexus-firstboot.desktop` to `Exec=/usr/local/bin/nexus-firstboot --autostart --non-interactive --mark-done` (`Terminal=false`), and staged it in `provision-nexus-lite.sh` and `provision-nexus-lite-lxqt.sh`.
3. **Cinnamon & XFCE Screen Blanking / RGB Screenshot Undercount (`0.0%` / `0.03%`):**
   - **Root Cause:** `nexus-guest-test.py` ran `xset s off -dpms` once before `cinnamon-screensaver`/`xfce4-power-manager` finished initializing (and never re-woke DPMS after the 300s idle probe), while `qemu-graphical-runner.py` checked only `rgb[::30]` (Red channel only) and captured `b*_01_desktop_initial` immediately after `nudge_mouse()` without settle time.
   - **Fix:** Added `disable_screen_blanking(sess, edition)` (`xset s off s noblank -dpms; xset s reset; xset dpms force on` + Cinnamon `gsettings` + XFCE `xfconf-query`) across `wm_ready`, `panel_ready`, and post-idle in `linux/test/nexus-guest-test.py` (plus `offline_ui_present` & `nexus_cli_tools_ok` checks), and fixed `qemu-graphical-runner.py` to sample all 3 RGB channels (`max(R,G,B) > 8`) with a `0.5s` settle after `nudge_mouse()`.
4. **LXQt Palette Customizer Key Mismatch:**
   - **Root Cause:** `linux/lite/scripts/apply-nexus-lite-lxqt.sh` substituted nonexistent `highlight_color=`/`window_color=` keys instead of `[Palette]` `active_colors`/`inactive_colors` in `lxqt.conf`.
   - **Fix:** Updated `apply-nexus-lite-lxqt.sh` to update `[Palette]` colors and `icon_theme`/`theme` cleanly for accent and `--appearance light`.
5. **Lite Openbox Wallpaper Fit Mode Not Persisted:**
   - **Root Cause:** `linux/lite/openbox/autostart` read `WALLPAPER_PATH` from `wallpaper.conf` but ignored `WALLPAPER_FIT`, always invoking `feh --bg-fill`.
   - **Fix:** Updated `linux/lite/openbox/autostart` to read and apply `WALLPAPER_FIT` (`centered`, `wallpaper`, `stretched`, `scaled`, `zoom`).
6. **Regression Coverage:** Added automated regression assertions for all 5 fixes in `scripts/check-phase23-validation.js` (section `7. Four-Edition Glitch Fix Regression Checks`); all pass via `npm test`.
7. **Open Item Watched for Post-Fix CI:** In baseline `46087428882`, `lite-lxqt-main` at `2048 MiB` recorded `iboot=2/3` (Boots 1–2 passed warm cycle; cold Boot 3 did not complete within window). Re-validation on the post-fix CI run will confirm cold Boot 3 status on `6d6deec+fixes`.

---

## 9. Bare-Metal Physical Hardware & External Limitations

- **Physical Hardware (`NOT TESTED`):** Bare-metal GPU acceleration (Intel/AMD/NVIDIA), physical Wi-Fi WPA2/WPA3, Bluetooth audio/pairing, Chromebook/laptop SOF UCM audio & internal mics, physical multi-touch touchpads, ACPI suspend/resume (`S3`/`s2idle`), physical battery curves, physical OEM NVRAM Secure Boot quirks, and physical Chromebook eMMC installs are **`NOT TESTED`** (never claimed from QEMU).
- **Sandbox Network Boundary (`BLOCKED`):** Direct download of CI `.iso`/`.png`/`.log` artifacts from `productionresultssa1.blob.core.windows.net` is `BLOCKED` inside this sandbox's outbound allowlist; full ISO verification & QEMU execution run on GitHub-hosted runners via `.github/workflows/iso-and-qemu-validation.yml`.
