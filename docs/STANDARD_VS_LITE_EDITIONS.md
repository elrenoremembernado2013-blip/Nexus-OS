# NEXUS OS Editions & Desktop Architecture Decision (Phase 12–12.4)

## Edition Separation & Phase 12.4 Dual-Tier Lite Strategy

All NEXUS OS editions share the **Linux Mint 22.3 / Ubuntu 24.04 Noble (`x86_64`)** foundation (`ufw`, `unattended-upgrades`, signed APT repos, `NetworkManager`, `nexus-install-preflight`, `nexus-hw-diagnostics`, `nexus-security-audit`) while keeping configs, manifests, `work-*` build trees, and output ISOs strictly isolated:

1. **NEXUS Standard (Cinnamon)** (`--edition cinnamon` / `standard`, `linux/config/nexus-standard-cinnamon.conf`, `linux/config/cinnamon-packages.list`) -> `nexus-os-22.3-cinnamon-amd64.iso` (`3.09 GB`). Full desktop identity (`5` themes, dock/compositor effects); `>= 2 GiB` entry floor (`llvmpipe` caveat), `4 GiB` recommended.
2. **NEXUS Standard Legacy / MADOO Xfce Baseline** (`--edition xfce`, `linux/config/nexus-system.conf`, `linux/config/mint-packages.list`) -> `nexus-os-22.3-xfce-amd64.iso` (`3.03 GB`). Preserved for MADOO `4 GB / 32 GB` Chromebook qualification and lightweight Xfce workloads.
3. **NEXUS Lite — LXQt Candidate (Primary `>= 1 GiB` Lite Edition)** (`--edition lite-lxqt`, `linux/lite/nexus-lite-lxqt.conf`, `linux/lite/manifests/lite-lxqt-packages.list`, `linux/lite/scripts/build-nexus-lite-lxqt-iso.sh`) -> `nexus-os-22.3-lite-lxqt-amd64.iso` (`2.87 GB`). Curated **LXQt + Openbox WM + `PCManFM-Qt` + `QTerminal` + `FeatherPad` + `Qps` + ZRAM** delivering modern desktop ergonomics (`521 MiB` live idle / `549–564 MiB` installed idle at `1 GiB`, `+62–83 MiB` over Openbox).
4. **NEXUS Lite — Openbox Ultra-Minimal (`512–768 MiB` Fallback)** (`--edition lite`, `linux/lite/nexus-lite.conf`, `linux/lite/lite-packages.list`, `linux/lite/build-nexus-lite-iso.sh`) -> `nexus-os-22.3-lite-amd64.iso` (`2.84 GB`). Preserved intact for ultra-low-memory `512–768 MiB` hardware where saving `~40–62 MiB` RAM and `~55 MiB` ZRAM swap matters most.
