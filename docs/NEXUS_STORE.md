# NEXUS Store Architecture & Capability Boundary (Phase 3)

## Overview

NEXUS Store consists of two intentionally separated layers:

1. **Desktop UI & Local Catalogue (`apps/store-catalog.js`, `apps/software-centre.js`)**:
   - Navigation for **Home**, **Discover**, **Apps**, **Games**, **Categories**, **Collections**, **My Library**, **Wishlist**, **Downloads**, **Updates**, **Developer Hub**, **Search** (`Ctrl/Cmd+K`), and **Application details**.
   - Browser-local registration for bundled NEXUS apps (such as `NEXUS Calendar`) without inventing ratings, download percentages, sizes, or version numbers.
   - Connects to a host package service via `window.NexusNativeServices` (`"packages"`) only when a trusted Linux runtime registers that adapter.

2. **Linux Mint Package Backend (`linux/mint/nexus-store-cli.sh`)**:
   - Wraps genuine **APT** (`apt-cache`, `apt-get`, `apt`, `dpkg-query`, `apt-mark`) and **Flatpak** (`flatpak`) commands on Linux Mint.
   - Validates every APT package name (`^[a-z0-9][a-z0-9+.-]{0,127}$`) and Flatpak app ID (`^[A-Za-z0-9_.-]{3,128}$` with domain separator).
   - Refuses removal of protected Linux Mint / NEXUS base packages (`apt`, `systemd`, `ufw`, `mintsystem`, `mintupdate`, `linux-*`, `xfwm4`, `cinnamon`, etc.).
   - Uses `pkexec` (Polkit) for APT mutations so GUI/user actions never bypass system authentication or store hardcoded credentials.
   - Respects Linux Mint's `mintupdate` workflow rather than silently altering repository lists or disabling security protections.

## Native `"packages"` Service Contract

When a trusted NEXUS host runtime registers `"packages"` with `window.NexusNativeServices.register("packages", adapter)`, `apps/software-centre.js` consumes:

- `sources()`: returns `{ apt: boolean, flatpak: boolean, mintupdate: boolean }`
- `search(query)`: returns array of `{ id, name, description, category, source, version, installed, protected }`
- `checkUpdates()`: returns array of `{ id, name, source, currentVersion, newVersion }`
- `install(id, source)`: performs authenticated installation and returns `{ ok, message }`
- `remove(id, source)`: performs authenticated removal (non-protected packages only)

When `"packages"` is unregistered (the default browser prototype), the Store stays in honest prototype mode (`Native package service disconnected` and `Update status is unknown.`).

## Verification & Current Limits

- **Verified:** Static checks, `--help`/`--dry-run` CLI checks, input-injection rejection, protected-package refusal (`systemd`, `apt`), and Node tests covering both disconnected prototype mode and mocked `"packages"` adapter integration (`scripts/check-store-catalog.js`, `scripts/check-store-native.js`).
- **Not yet tested on live Linux Mint:** Actual `apt-get` / `pkexec` / `flatpak` package installation, removal, and `apt list --upgradable` update flows inside a booted Mint guest.
