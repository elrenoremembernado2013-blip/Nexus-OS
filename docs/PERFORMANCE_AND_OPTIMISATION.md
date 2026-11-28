# NEXUS OS — Performance Optimisation, Performance Centre & Low-Resource Mode

## Overview

Phase 20 optimises NEXUS OS across all four editions (`cinnamon`, `xfce`, `lite-lxqt`, `lite`) while preserving security (`ufw`, `polkit`, `unattended-upgrades`, `NetworkManager`), accessibility, and visual clarity.

## Key Optimisations

1. **System Telemetry Bridge (`linux/mint/nexus-system-bridge.py`)**
   - **Non-blocking delta CPU calculation**: Repeated `/api/telemetry` polls compare against `_LAST_CPU_SAMPLE` instead of sleeping 80 ms synchronously on every request (first sample falls back to a 0.08 s measurement; subsequent polls complete in ~21.5 ms vs ~87.4 ms baseline in loopback testing).
   - **Bounded UID→username cache (`_UID_NAME_CACHE`, max 256 entries)**: Eliminates repeated `pwd.getpwuid()` syscalls when reading `/proc/[pid]/status`.
   - **Expanded telemetry**: Exposes `swap_used_mib` / `swap_total_mib` / `swap_percent`, `uptime_seconds`, PCI GPU driver + sysfs `gpu_busy_percent` when available, and `/proc/diskstats` cumulative read/write MiB.
   - **Authenticated Performance endpoints**:
     - `GET /api/performance/overview`
     - `POST /api/performance/low-resource`
     - `POST /api/performance/startup`
     - `POST /api/performance/cleanup`

2. **Desktop Shell & Launcher (`app.js`)**
   - `renderLauncher()` caches launcher `<button>` + `<img>` DOM nodes in `launcherButtonMap` (with `loading="lazy"` and `decoding="async"`) and toggles visibility on search input rather than rebuilding the launcher DOM on every keystroke.
   - `NexusDesktopShell.setLowResourceMode()` / `isLowResourceMode()` syncs the Control Centre power toggle (`desktop.lightweight`, `body.low-resource-mode`), `apps/system-monitor.js`, and the Linux `nexus-performance-cli.sh` helper without requiring a reboot.

3. **NEXUS Performance Centre (`apps/system-monitor.js`)**
   - Preserves strict honest-boundary semantics: shows `Unavailable` and zero synthetic graphs when disconnected.
   - Uses a strictly bounded circular history buffer (`MAX_HISTORY = 24`) for lightweight SVG sparklines (CPU %, RAM %).
   - Auto-refresh is off by default, clears intervals on unmount, and throttles from `5s` to `15s` when Low-Resource Mode is enabled.
   - Includes **Boot & Startup Apps** (`systemd-analyze` timing + reversible user-level `~/.config/autostart/*.desktop` `Hidden=true` overrides, refusing to disable essential `polkit`/`nm-applet` units), **Storage & Safe Cleanup** (preview sizes first, explicit confirmation required, never touches user documents or active wallpaper), and **Edition Recommendations**.

4. **Gaming & Steam Diagnostics (`linux/mint/nexus-gaming-cli.sh` & `apps/gaming.js`)**
   - Detects rotational HDD vs SSD/NVMe root storage, sysfs GPU `gpu_busy_percent` when exposed, Steam launch option hints (`gamemoderun %command%`, `mangohud %command%`), and per-edition compositor fullscreen unredirection guidance without fabricating FPS or compatibility claims.

5. **Safe Performance & Cleanup CLI (`linux/mint/nexus-performance-cli.sh`)**
   - `overview`: JSON memory/ZRAM, uptime, `systemd-analyze` boot timing, startup entries, storage devices, safe cache sizes, and edition recommendations.
   - `low-resource <enable|disable|status>`: Reversible user-level toggle; never disables `ufw`, `polkit`, `unattended-upgrades`, or `NetworkManager`.
   - `cleanup --target <thumbnails|wallpapers|mesa|apt> --confirm`: Cleans only regenerable caches and refuses execution without `--confirm`.
