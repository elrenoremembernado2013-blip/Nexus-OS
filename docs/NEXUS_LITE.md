# NEXUS Lite — Ultra-Low-RAM Edition (512 MB Experimental / 1 GB / 2 GB+)

## Why NEXUS Lite Exists

Linux Mint Cinnamon is designed for `>= 2–4 GiB` RAM and cannot run comfortably inside `512 MB` of physical memory. **NEXUS Lite** keeps the exact same **Linux Mint 22.3 / Ubuntu 24.04 Noble (`x86_64`)** security, APT signature verification, UFW firewall, and `unattended-upgrades` foundation while replacing Cinnamon/Xfce with **Openbox + `tint2` + `PCManFM` + `LXTerminal` (GNU Bash)** and **zero compositor/blur/Steam/default browser**.

## Three Operating Profiles

| Profile | Desktop | Key Differences | Status |
|---|---|---|---|
| **NEXUS Lite — 512 MB Experimental** (`lite-512`) | Openbox + `tint2` (`2` workspaces) | Zero compositor, no `nm-applet`/browser/Steam at boot, zram swap (`zstd`) | **Experimental** (pending multi-RAM VM verification) |
| **NEXUS Lite — 1 GB** (`lite-1g`) | Openbox + `tint2` (`4` workspaces) | Adds `nm-applet` & comfortable multitasking | **Experimental** (pending VM verification) |
| **NEXUS Standard — 2 GB+** (`standard-2g`) | Cinnamon / Xfce | Full NEXUS desktop, Store, Gaming Hub, and browser | **Standard** (`Development` stage until ISO/VM verified) |

## Browser, Gaming & Installer Limitations

- **Web Browsers:** Excluded by default from `512 MB` (`lite-packages.list` marks `falkon` and `firefox` optional). Modern web apps and HD video require `>= 1–2 GiB` RAM; never compromise browser security updates to save memory.
- **Gaming:** Steam, Proton, and GameMode are excluded from NEXUS Lite and remain exclusive to higher-RAM **NEXUS Standard** systems.
- **Swap & `zram`:** `configure-zram.sh` uses compressed `zstd` RAM swap (`PERCENT=50`, `vm.swappiness=60`) to absorb transient spikes safely without treating swap as equivalent to physical RAM.
- **Low-Memory Installation:** Graphical Ubiquity generally requires `>= 1024 MiB` RAM; `512 MB` systems require enabling `zram` or CLI `debootstrap` installation (`nexus-lite-install.sh`).

## Verification Limits

- **Verified locally & in CI:** `lite-packages.list` validation (`10` core/desktop/nexus + `2` optional packages), `apply-nexus-lite.sh --dry-run` / `--revert` across all 3 profiles, `configure-zram.sh status` & `--dry-run enable`, `memory-audit.sh --json`, `nexus-lite-install.sh --dry-run`, and `build-nexus-lite-iso.sh --dry-run`.
- **Untested (pending QEMU VM suite with `512M / 768M / 1G / 2G / 4G` RAM):** live Openbox boot, idle/app RSS inside a booted Lite ISO, and `512 MB` installation stability. Therefore **512 MB support remains strictly labelled `Experimental`**, not verified.
