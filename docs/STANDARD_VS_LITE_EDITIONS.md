# NEXUS OS Editions & Desktop Architecture Decision (Phase 12)

## Resolution of the Standard Desktop Discrepancy (`xfce` vs `cinnamon`)

- **Why `nexus-os-22.3-xfce-amd64.iso` appeared in Phase 11:**
  Commit `480cc5d` intentionally pinned `linux/config/nexus-system.conf` to `NEXUS_BASE_EDITION=xfce` for the **4 GB RAM / 32 GB eMMC HP Chromebook x360 14b (MADOO)** target (`docs/PLATFORM_ARCHITECTURE.md`).
- **Why Cinnamon is the flagship Standard desktop:**
  Commit `a1738ef` (Phase 2) introduced the full NEXUS desktop identity (`linux/cinnamon/` — 5 coordinated `NEXUS-*` themes, Cinnamon panel/dock controls, workspace animations, Muffin window effects, and wallpaper curation). Phases 7–10 extended `provision-nexus-guest.sh` and XDG launchers to detect Cinnamon automatically, yet `build-nexus-iso.sh` still defaulted solely to `nexus-system.conf` (`xfce`).
- **Decision (Explicit Separation, Zero Silent Overwrites):**
  1. **NEXUS Standard (Cinnamon)** (`--edition standard` / `--edition cinnamon`, `linux/config/nexus-standard-cinnamon.conf`, `linux/config/cinnamon-packages.list`) -> outputs `build/iso/out/nexus-os-22.3-cinnamon-amd64.iso`. Intended full NEXUS experience (`>= 2 GiB` min, `4 GiB` recommended).
  2. **NEXUS Standard Legacy / MADOO Xfce Baseline** (`--edition xfce`, `linux/config/nexus-system.conf`, `linux/config/mint-packages.list`) -> outputs `build/iso/out/nexus-os-22.3-xfce-amd64.iso`. Preserved intact for backward compatibility and MADOO 4 GB / 32 GB testing.
  3. **NEXUS Lite (Openbox + `tint2` + `zram`)** (`linux/lite/build-nexus-lite-iso.sh` or `--edition lite`, `linux/lite/nexus-lite.conf`, `linux/lite/lite-packages.list`) -> outputs `build/iso/out/nexus-os-22.3-lite-amd64.iso`. Isolated work tree (`build/iso/work-lite`) and edition-specific `.build-info.json` so builds never overwrite each other.
