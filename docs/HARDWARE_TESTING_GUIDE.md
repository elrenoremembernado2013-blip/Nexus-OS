# NEXUS OS Bare-Metal Hardware Qualification & Contribution Guide (Phase 13.0)

> **Critical Safety Warning:**
> - **NEVER** use your primary personal computer or your personal Chromebook (including HP Chromebook x360 14b) as a disposable disk-install, wipe, partitioning, LUKS, or firmware-modification target.
> - Destructive installer, dual-boot, LUKS, and bootloader tests must run **only** on disposable QEMU/OVMF virtual disks or dedicated, backed-up spare test hardware.
> - NEXUS hardware qualification scripts (`nexus-hw-inventory`, `nexus-hw-diagnostics`, `nexus-hw-qualify`, `nexus-browser-qualify`) **never** format drives, repartition disks, install an OS, flash BIOS/UEFI, alter or disable Secure Boot, modify bootloader configuration, run destructive storage tests, record microphone audio, log Wi-Fi SSIDs/passwords, or auto-upload reports.

---

## 1. Two-Stage Guided Hardware Test Programme (`nexus-hw-qualify`)

Every NEXUS OS edition (`cinnamon`, `xfce`, `lite`, `lite-lxqt`) ships `/usr/local/bin/nexus-hw-inventory`, `/usr/local/bin/nexus-hw-diagnostics`, `/usr/local/bin/nexus-hw-qualify`, `/usr/local/bin/nexus-browser-qualify`, and `/usr/local/bin/nexus-security-audit`.

### Stage A — Read-Only Preflight (Default)

Boot a live NEXUS OS USB session on spare test hardware (no disk writes) and run Stage A:

```bash
nexus-hw-qualify --stage a --export ~/nexus-hw-report
```

What Stage A does:
- Detects virtual machine (`qemu_ovmf_tcg` / `virtual_machine`) vs bare metal (`bare_metal_or_host`) and flags Chromebook DMI boards with a safety reminder.
- Inspects CPU architecture/category (`intel_x86_64` / `amd_x86_64` / `virtual_or_emulated`), RAM, UEFI & Secure Boot state (`efivars` / `mokutil`), signed boot chain (`shimx64.efi`, `grubx64.efi`, `vmlinuz-*`, `sbverify`), storage drivers (`nvme`, `ahci`, `mmc_block`), GPU drivers + DRM/Mesa/GLX/Vulkan ICDs (`hardware_acceleration`: `genuine_hardware_gpu_driver_bound` vs `software_llvmpipe_or_virtual`), NetworkManager/Wi-Fi/Bluetooth readiness (zero SSIDs/MACs), PipeWire/PulseAudio/ALSA/SOF firmware status (zero audio capture), touchpads, USB controllers, batteries, and exposed suspend modes (`/sys/power/state`, `/sys/power/mem_sleep`) **without triggering suspend**.
- Exports `nexus-diagnostics.json`, `nexus-diagnostics.md`, and `nexus-hw-contribution-template.json` into `~/nexus-hw-report`, running an automated `privacy_audit` self-check.

### Stage B — Manually Authorized Individual Tests

Each Stage B test prints a **pre-run safety explanation** (`WILL DO` / `WILL NOT DO`) and **refuses to run** without explicit confirmation (`--confirm-test <name>` or `--interactive` `yes`). Preview any test safely first with `--dry-run`:

```bash
nexus-hw-qualify --run-test gpu --dry-run
nexus-hw-qualify --run-test gpu --confirm-test gpu --export ~/nexus-hw-report
nexus-hw-qualify --run-test wifi --confirm-test wifi --export ~/nexus-hw-report
nexus-hw-qualify --run-test bluetooth --confirm-test bluetooth --export ~/nexus-hw-report
nexus-hw-qualify --run-test audio-output --confirm-test audio-output --export ~/nexus-hw-report
nexus-hw-qualify --run-test microphone --confirm-test microphone --export ~/nexus-hw-report
nexus-hw-qualify --run-test touchpad --confirm-test touchpad --export ~/nexus-hw-report
nexus-hw-qualify --run-test usb --confirm-test usb --export ~/nexus-hw-report
nexus-hw-qualify --run-test battery --confirm-test battery --export ~/nexus-hw-report
```

- **`all-safe`:** Runs all non-suspending Stage B checks (`gpu`, `wifi`, `bluetooth`, `audio-output`, `microphone`, `touchpad`, `usb`, `battery`) after explicit `--confirm-test all-safe`.
- **`microphone` safety rule:** Only inspects ALSA `arecord -l`, PipeWire/PulseAudio source metadata, and SOF firmware counts; **never records audio**.
- **`suspend` safety rule:** Never included in Stage A or `all-safe`. Only runs when explicitly authorized via `nexus-hw-qualify --run-test suspend --confirm-test suspend` on spare bare-metal hardware (skipped automatically inside VMs).

---

## 2. Physical-GPU Browser Qualification (`nexus-browser-qualify`)

QEMU/OVMF tests run under `bochs-drm` + Mesa `llvmpipe` software rendering and **do not** measure physical GPU acceleration. On a physical machine booted into any of the four editions (`cinnamon`, `xfce`, `lite`, `lite-lxqt`), install optional `falkon` and/or `firefox` and run:

```bash
nexus-browser-qualify --dry-run
nexus-browser-qualify --edition lite-lxqt --browsers falkon,firefox --confirm --out ~/nexus-hw-report/browser-gpu.json
```

Measured fields per browser:
- `gpu_environment`: active PCI GPU driver (`i915`, `xe`, `amdgpu`, `nvidia`), `glx_renderer`, and `acceleration_mode` (`hardware_gpu` vs `software_llvmpipe_or_virtual`).
- `startup_sec`, `window_mapped`, and per-stage (`1`, `2`, `4`, `6` tabs) page load ms, browser RSS, total RAM used, swap/ZRAM ratio, CPU %, and OOM delta.
- `webgl_probe` (`webgl2`/`webgl1`, `WEBGL_debug_renderer_info`, `requestAnimationFrame` FPS).
- `video_probe` (`H.264`, `VP9`, `VP8`, `AV1` `HTMLMediaElement.canPlayType` support + frame-loop FPS).
- `post_close` RSS & system memory recovery.
- **Current Physical-GPU Status:** **`NOT TESTED`** across all 4 editions until bare-metal submissions are reviewed.

---

## 3. Manual Installer & Ubiquity GUI Checklist (Spare Disks Only)

While automated QEMU tests cover `nexus-disk-install` guided, manual partitioning, interrupted recovery, simulated dual-boot (`--keep-efi` + NTFS/ESP preservation), and LUKS2 cold-boot unlock, the interactive GTK **Ubiquity** wizard screens still require manual verification on spare test hardware:
1. Launch `nexus-installer-launcher` in a live session (`>= 1024 MiB` RAM) on spare test hardware.
2. Verify Ubiquity "Something else" manual partition table display, EFI selection, dual-boot `os-prober` entry detection, and interactive LUKS+LVM passphrase entry (`partman-auto-crypto`).
3. Verify Legacy BIOS / MBR boot behavior separately if testing non-UEFI hardware (`nexus-disk-install.sh` requires UEFI `x86_64-efi`; Legacy BIOS/MBR remains `NOT TESTED`).

---

## 4. Privacy Review & Contributing to `hw-compatibility-db.json`

1. Generate the contribution template:
   ```bash
   nexus-hw-diagnostics --contribute-template > ~/nexus-hw-report/contribution.json
   ```
2. **Mandatory Human Privacy Review before sharing:** Inspect every line of `contribution.json`, `nexus-diagnostics.json`, and `browser-gpu.json` to verify there are **zero**:
   - Hardware serial numbers, motherboard/disk UUIDs, or WWNs
   - MAC addresses or Bluetooth device addresses
   - Local usernames, `/home/<name>` paths, or machine hostnames
   - External IP addresses, Wi-Fi SSIDs, BSSIDs, passwords, or LUKS passphrases
3. Fill out `manual_checklist` (`pass` / `fail` / `partial` / `untested`) and `browser_gpu_qualification` honestly based only on what you directly observed.
4. Submit a pull request or issue attaching the reviewed JSON; maintainers audit each submission before updating `linux/hardware/hw-compatibility-db.json` (`auto_upload` is permanently `false`).
