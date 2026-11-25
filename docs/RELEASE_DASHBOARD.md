# NEXUS OS Release Readiness Dashboard (Phase 12.2)

**Current Release Stage:** `Development` (All 3 ISOs built, GPG/SHA-256 verified, and graphically validated in QEMU/OVMF via GitHub Actions run [`45656960059`](https://github.com/elrenoremembernado2013-blip/Nexus-OS/actions/runs/45656960059); full end-to-end Ubiquity disk install + bare-metal hardware tests remain pending)
**Stable Release Decision:** **HOLD — Not ready for `Stable` release** until interactive/end-to-end disk installation + post-install reboot and physical hardware checks are completed.

## Phase 12.2 Separated Validation Outcomes (Run `45656960059`, Commit `abee847`, `accel=tcg`)

| Edition | RAM Tier | ISO Build & SHA-256 | UEFI/OVMF Boot | LightDM Login | Graphical Session (WM + Panel) | App Windows (`xwininfo`) | 6-Stage RAM (`oom=0`) | ZRAM Pressure | Disposable `/dev/vda` Preflight | End-to-End Disk Install |
|---|---|---|---|---|---|---|---|---|---|---|
| **NEXUS Lite** | `512 MiB` | PASS (`2.84 GB`) | PASS | PASS | PASS (`openbox` + `tint2`) | PASS | PASS (`300s` idle) | PASS (`64 MiB`) | PASS (`lsblk vda`) | Manual / Unverified |
| **NEXUS Lite** | `768 MiB` | PASS | PASS | PASS | PASS (`openbox` + `tint2`) | PASS | PASS (`30s` idle) | PASS (`96 MiB`) | PASS (`lsblk vda`) | Manual / Unverified |
| **NEXUS Lite** | `1024 MiB` | PASS | PASS | PASS | PASS (`openbox` + `tint2`) | PASS | PASS (`300s` idle) | PASS (`96 MiB`) | PASS (`lsblk vda`) | Manual / Unverified |
| **NEXUS Lite** | `2048 MiB` | PASS | PASS | PASS | PASS (`openbox` + `tint2`) | PASS | PASS (`30s` idle) | PASS (`96 MiB`) | PASS (`lsblk vda`) | Manual / Unverified |
| **NEXUS Lite** | `4096 MiB` | PASS | PASS | PASS | PASS (`openbox` + `tint2`) | PASS | PASS (`300s` idle) | PASS (`96 MiB`) | PASS (`lsblk vda`) | Manual / Unverified |
| **NEXUS Standard (Cinnamon)** | `2048 MiB` | PASS (`3.09 GB`) | PASS | PASS | PASS (`cinnamon-session`) | PASS (X11; LLVMpipe render incomplete at `30s`) | PASS (`30s` idle) | N/A (not configured) | PASS (`lsblk vda`) | Manual / Unverified |
| **NEXUS Standard (Cinnamon)** | `4096 MiB` | PASS (`3.09 GB`) | PASS | PASS | PASS (`cinnamon-session`, `96.06%` screen) | PASS | PASS (`300s` idle) | N/A (not configured) | PASS (`lsblk vda`) | Manual / Unverified |
| **MADOO Xfce** | `4096 MiB` | PASS (`3.03 GB`) | PASS | PASS | PASS (`xfce4-session` + `xfce4-panel`, `97.87%` screen) | PASS | PASS (`300s` idle) | N/A (not configured) | PASS (`lsblk vda`) | Manual / Unverified |

## Subsystem Status Matrix

| Subsystem | Status | Verified Evidence | Remaining Manual / Hardware Scope |
|---|---|---|---|
| **Linux Mint 22.3 Foundation** | Verified in ISO & Live VM | GPG-verified Mint 22.3 base ISOs (`27DEB15644C6B3CF3BD7D291300F846BA25BAE09`), `systemd` + `NetworkManager` (`connected`) | Bare-metal firmware & long-run `unattended-upgrades` |
| **Desktop & Shell (3 Editions)** | Verified in Live QEMU | Openbox + `tint2`, Cinnamon (`96.06%` at 4G), Xfce (`97.87%` at 4G) at `1280x800` | Physical GPU compositing (vs software `tcg`/LLVMpipe) |
| **Core Applications & Bridge** | Verified Locally & in Live VM | `pcmanfm`/`nemo`/`thunar`, `lxterminal`/`gnome-terminal`/`xfce4-terminal`, `obconf`/`cinnamon-settings`/`xfce4-settings-manager`, `mousepad`/`xed`; `15` JS + bridge suites | Interactive browser media playback & Flatpak app installs |
| **ZRAM & Low-Memory Support** | Verified in Live VM | `zram0` (`zstd`, `50%` RAM) verified `512M`–`4096M` on Lite with `0` OOM kills across 6 stages + pressure tests | Real web-browsing workload pressure at `512 MiB` |
| **Security & Privacy** | Verified in CI & Scripts | `ufw`, `unattended-upgrades`, zero test services baked into released ISOs (`casper-bottom` test harness injected in ephemeral test initrd only) | UEFI Secure Boot on physical firmware + LUKS install test |
| **Installer & Preflight** | Preflight Verified; Full Install Manual | `nexus-install-preflight` & `/dev/vda` block detection verified in all 8 live VM runs | Unattended or interactive `ubiquity` partitioning + post-install reboot |

## Remaining Steps Before `Stable` Promotion

1. **Interactive / End-to-End Disk Install Verification:** Boot an ISO in QEMU/KVM or bare metal with a `20+ GB` target disk, complete `ubiquity` (for `>= 1024 MiB`) or `sudo nexus-lite-install` (for `512 MiB` target), reboot without the ISO, and verify the installed system.
2. **Physical Hardware Qualification:** Test real Wi-Fi/Bluetooth chipsets, HDA/SOF Chromebook audio (`MADOO`), Vulkan/Proton GPU drivers, and external displays.

See `docs/STANDARD_VS_LITE_EDITIONS.md` and `docs/NEXUS_LITE.md` for full measured RAM profiles and installation instructions.
