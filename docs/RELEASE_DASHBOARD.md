# NEXUS OS Release Readiness Dashboard (Phase 12.3)

**Current Release Stage:** `Development` / `Alpha` (ISO build + production/test separation + live ISO graphical boot + Ubiquity UI launch + automated GPT/UEFI disk installation onto disposable `qcow2` + 3-reboot ISO-free installed-system & persistence validation passed across all 3 editions in GitHub Actions run [`45722286627`](https://github.com/elrenoremembernado2013-blip/Nexus-OS/actions/runs/45722286627), commit `efc6c01`).
**Stable Release Decision:** **HOLD — Not ready for `Stable` release.** Physical bare-metal hardware qualification, interactive manual Ubiquity partition/LUKS UI walkthroughs, and real-world heavy desktop/browser workloads remain untested.

## Phase 12.3 Separated Validation Matrix (Run `45722286627`, Commit `efc6c01`, `accel=tcg`)

Live ISO tests, installer tests, and ISO-free installed-disk boots are tracked separately so a passing live boot can never imply installation or installed-system success.

| Edition | RAM Tier | ISO Build & Test-Leak Check | Live ISO Boots | Ubiquity GTK UI | Disposable `/dev/vda` Install (`nexus-disk-install`) | Installed Boots (No ISO: 2x Warm + 1x Cold) | Persistence Across Reboots | Installed RAM / Swap / OOM (`7_post_close`) | Edition Stage Assessment |
|---|---|---|---|---|---|---|---|---|---|
| **NEXUS Lite** | `512 MiB` | PASS (`2.84 GB`, 0 test leaks) | `3/3` PASS (`99.96–100%`) | Skipped (`<850 MiB`; CLI path) | `2/2` PASS (`840.4s`, EFI OK) | `3/3` PASS (`vda`, `no_iso`, `99.99–100%`) | PASS (`persist=true`) | `237–258 MiB` used, `100–175 MiB` ZRAM swap, `0` OOM | **Experimental** (verified in QEMU; heavy apps/browser unsupported at 512 MiB) |
| **NEXUS Lite** | `768 MiB` | PASS | `1/1` PASS (`99.98–100%`) | Skipped (`<850 MiB`) | `1/1` PASS (`832.5s`, EFI OK) | `3/3` PASS (`vda`, `no_iso`, `99.99–100%`) | PASS (`persist=true`) | `407–428 MiB` used, `48–66 MiB` ZRAM swap, `0` OOM | **Alpha** |
| **NEXUS Lite** | `1024 MiB` | PASS | `3/3` PASS (`99.98–100%`) | PASS (`99.98%`) | `1/1` PASS (`836.6s`, EFI OK) | `3/3` PASS (`vda`, `no_iso`, `99.99%`) | PASS (`persist=true`) | `465–516 MiB` used, `0` swap, `0` OOM | **Alpha** (Verified QEMU minimum recommended for Lite) |
| **NEXUS Lite** | `2048 MiB` | PASS | `1/1` PASS (`99.98–100%`) | PASS (`99.98%`) | `1/1` PASS (`851.1s`, EFI OK) | `3/3` PASS (`vda`, `no_iso`, `99.93–99.99%`) | PASS (`persist=true`) | `527–554 MiB` used, `0` swap, `0` OOM | **Alpha** |
| **NEXUS Standard (Cinnamon)** | `2048 MiB` | PASS (`3.09 GB`, 0 test leaks) | `1/1` PASS (X11; see LLVMpipe note) | PASS (`96.63%`) | `1/1` PASS (`945.3s`, EFI OK) | `3/3` PASS (`vda`, `no_iso`) | PASS (`persist=true`) | `0` OOM (LLVMpipe slow under `-vga std` `30s`) | **Development / Entry Floor** (requires >=90s settle or GPU accel; >=4 GiB recommended) |
| **NEXUS Standard (Cinnamon)** | `4096 MiB` | PASS (`3.09 GB`, 0 test leaks) | `3/3` PASS (`96.63–97.83%`) | PASS (`96.63%`) | `2/2` PASS (`961.7s`, EFI OK) | `3/3` PASS (`vda`, `no_iso`) | PASS (`persist=true`) | `1079 MiB` used (`Boot 1`), `0` swap, `0` OOM | **Alpha** (Recommended floor `4096 MiB`) |
| **MADOO Xfce** | `4096 MiB` | PASS (`3.03 GB`, 0 test leaks) | `3/3` PASS (`98.01–100%`) | PASS (`98.11%`) | `2/2` PASS (`1188.8s`, EFI OK) | `3/3` PASS (`vda`, `no_iso`, `98.01–100%`) | PASS (`persist=true`) | `853–889 MiB` used, `0` swap, `0` OOM | **Alpha** (Hardware-dependent on real Chromebook) |

## Evidence Classification & Known Issues

| Area | Classification | Verified Evidence | Open Issues & Untested Scope |
|---|---|---|---|
| **Production / Test Separation** | **Verified** | `verify-nexus-iso.sh` unpacks every ISO `initrd` (`unmkinitramfs`) and `filesystem.squashfs` (`unsquashfs -l`) and fails if `nexus-test-agent`, `casper-test-hook`, or `/usr/local/libexec/nexus-test` appear. | N/A |
| **Automated Disk Installer (`nexus-disk-install.sh`)** | **Verified in QEMU** | `10/10` installs on disposable `/dev/vda` (`GPT` 512 MiB FAT32 ESP + ext4 root, UUID `fstab`, UEFI `grub-install --no-nvram` + `EFI/BOOT/BOOTX64.EFI` + `EFI/ubuntu/grub.cfg`, `casper` purge, zero hardcoded passwords). | Interactive Ubiquity "Something else" manual partitioning and LUKS passphrase entry remain untested in headless CI. |
| **Installed First Boot, Multi-Reboot & Persistence** | **Verified in QEMU** | `21/21` ISO-free OVMF boots (`2x` warm reboot + `1x` cold boot per config); `findmnt /` on `/dev/vda2`, `/rofs` absent, `NetworkManager` `connected`, `0` failed systemd units, marker + `~/Documents` file persisted across reboots. | `lite-512M` cold boot & `lite-1024M` boot 1 logged `28` `journalctl -p err` entries with `0` failed units (`0` errors on all other boots). `xfce`/`cinnamon` `windows_closed_cleanup` returned `false` due to resident desktop/tray window IDs even though RAM returned to baseline. |
| **Cinnamon `2048 MiB` Rendering** | **Root-Caused / Partially Verified** | `glxinfo` confirmed `llvmpipe (LLVM 20.1.2, 256 bits)`, `Accelerated: no`, `1966 MiB` unified memory. At `30s` idle under `-vga std` + `accel=tcg`, Muffin/Clutter shader warmup had not flushed (`0.03%` on both `2048M` live and `4096M` Boot 1), then jumped to `96.63%` ~25s later; `-vga virtio` at `90s` rendered `96.65–96.7%`. | Not an OOM bug (`0` OOM kills), but software OpenGL compositing imposes high CPU load (`100%`) and multi-second initial frame latency without 3D GPU acceleration. |
| **Physical Hardware (`MADOO` & PCs)** | **Hardware-Dependent / Untested** | QEMU `q35` + VirtIO (`vda`, `virtio-net-pci`, `1280x800` OVMF) only. | Real Intel/AMD/NVIDIA GPUs, Wi-Fi/Bluetooth chipsets, Chromebook SOF audio (`MADOO`), Secure Boot hardware keys, and sleep/resume. |

See `docs/NEXUS_LITE.md`, `docs/HARDWARE_COMPATIBILITY.md`, `docs/INSTALLER_ARCHITECTURE.md`, and `docs/ISO_BUILD.md` for full RAM stage tables and reproduction commands.
