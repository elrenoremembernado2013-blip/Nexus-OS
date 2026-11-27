# NEXUS OS Cinnamon Desktop Integration (Phase 2)

This directory (`linux/cinnamon/`) provides modular theme generation and `gsettings` integration for **Linux Mint Cinnamon** alongside the lower-resource **Linux Mint 22.3 Xfce** edition (`linux/xfce/`, `linux/mint/`).

## Implemented Components

### 1. Five Coordinated NEXUS Themes (`linux/cinnamon/themes.json`)
- **NEXUS Midnight** (`NEXUS-Midnight`): dark navy (`#0d1424`) with `#66a3ff` blue accent
- **NEXUS Nebula** (`NEXUS-Nebula`): deep space slate (`#141024`) with `#b185ff` violet accent
- **NEXUS Arctic** (`NEXUS-Arctic`): cool slate (`#101922`) with `#38bdf8` cyan accent
- **NEXUS Emerald** (`NEXUS-Emerald`): forest dark (`#0d1914`) with `#34d399` emerald accent
- **NEXUS Solar** (`NEXUS-Solar`): warm dark slate (`#191a20`) with `#ffad7a` copper accent

`linux/cinnamon/apply-nexus-cinnamon.sh` renders `cinnamon/cinnamon.css`, `gtk-3.0/gtk.css`, and `index.theme` for all five presets under `~/.local/share/themes/NEXUS-*` without modifying `/usr/share/themes`.

### 2. Cinnamon Panel, Workspaces, Notifications & Performance Modes
`apply-nexus-cinnamon.sh` configures established Cinnamon `gsettings` schemas (`org.cinnamon.theme`, `org.cinnamon.desktop.interface`, `org.cinnamon.desktop.wm.preferences`, `org.cinnamon.muffin`, `org.cinnamon.desktop.notifications`, `org.cinnamon`):
- `--dock-position bottom|left|right`: updates `org.cinnamon panels-enabled` for panel 1 without adding a conflicting third-party dock.
- `--workspaces 1..8`: sets `org.cinnamon.desktop.wm.preferences num-workspaces` and enables Muffin `edge-tiling`.
- `--profile balanced|performance|lightweight`: controls `enable-animations` and `desktop-effects`.
- `--revert`: removes user `NEXUS-*` theme directories and restores `Mint-Y-Dark` defaults.

### 3. Curated Wallpaper Attribution Manifest (`linux/cinnamon/wallpapers.json`)
Lists genuine photographer-attributed images with source URLs, licenses, categories, and recommended NEXUS theme pairings (`recommendedTheme`).

## Testing & Verification Limits

- **Verified locally & in CI:** `bash -n`, `shellcheck`, JSON schema validation for `themes.json` and `wallpapers.json`, `--help`/`--dry-run`/`--revert` CLI checks, and generating + reverting all five `NEXUS-*` theme packages inside a temporary `XDG_DATA_HOME` directory.
- **Requires a booted Linux Mint Cinnamon session (not yet tested):** live `gsettings` schema availability, Cinnamon shell CSS visual rendering, panel drag/dock behavior, workspace transitions, and desktop notifications.
