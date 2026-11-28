# NEXUS OS Personalisation, Themes & Wallpapers (Phase 7)

## Theme Engine

NEXUS OS ships five cohesive built-in themes implemented identically across the desktop CSS shell (`apps/personalisation-catalog.js`, `styles.css`) and user-local Linux Mint Cinnamon/GTK3 theme packages (`linux/cinnamon/themes.json`, `linux/cinnamon/apply-nexus-cinnamon.sh`):

- **Midnight** — deep slate `#0d1424` and subtle blue `#66a3ff` (`NEXUS-Midnight` / `Mint-Y-Dark-Blue`).
- **Nebula** — dark purple `#141024` and cosmic violet `#b185ff` (`NEXUS-Nebula` / `Mint-Y-Dark-Purple`).
- **Arctic** — cool white/icy slate and sky blue `#0284c7` / `#38bdf8` (`NEXUS-Arctic` / `Mint-Y-Dark-Aqua`).
- **Emerald** — dark forest `#0d1914` and emerald `#34d399` (`NEXUS-Emerald` / `Mint-Y-Dark-Teal`).
- **Solar** — warm charcoal `#191a20` and copper/gold `#ffad7a` (`NEXUS-Solar` / `Mint-Y-Dark-Sand`).

All themes support Dark / Light / System mode switching, custom `#RRGGBB` accent colours (passed via `--accent` to `apply-nexus-cinnamon.sh` to regenerate user GTK3/Cinnamon CSS), preview-before-apply for wallpapers, and `--revert` / full preference reset.

## Genuine Photographic Wallpaper Library

Every curated wallpaper in `linux/cinnamon/wallpapers.json` and `apps/personalisation-catalog.js` is a verified photograph (zero AI-generated wallpapers) with photographer/agency attribution, original source page URL, license, HD (`1280px`) and UHD (`2400px`) URLs, search/category filtering across 8 categories, favourites, fit modes (`cover`, `contain`, `fill`, `center`), automatic rotation, local custom JPEG/PNG/WebP import (`IndexedDB`), and local canvas colour sampling for optional accent suggestions.

On Linux Mint, `apply-nexus-cinnamon.sh --wallpaper-url <https-or-path> --wallpaper-fit <zoom|scaled|stretched|centered|wallpaper>` caches verified HTTPS wallpapers under `~/.cache/nexus-os/wallpapers/` and applies them via `org.cinnamon.desktop.background`.

## Custom Wallpaper Persistence (Phase 26)

When the native Linux bridge is connected, importing a custom JPEG, PNG, or WebP wallpaper now sends the already-previewed image to the authenticated loopback bridge. The bridge validates the declared MIME type against the image signature, rejects malformed base64 and images over 8 MiB, and stores the image under:

`~/.local/share/nexus-os/wallpapers/custom.<ext>`

The file is written with user-only permissions and applied through the same cross-edition `nexus-wallpaper` CLI used by catalog wallpapers. This lets Cinnamon, XFCE, LXQt, and Openbox persist the imported image through their native desktop settings, including after a restart. In browser-only preview mode, the existing IndexedDB copy remains local to that browser and is not represented as a native OS wallpaper.

## Dock, Panel, Effects & Profiles

- **Dock & Panel**: position (`bottom`, `left`, `right`), icon size (`36`, `43`, `52` px), spacing, auto-hide (`false`, `true`, `intel`), background style (`glass`, `solid`, `minimal`), running indicators, desktop shortcuts, and 24-hour clock format.
- **Effects**: `Off`, `Subtle`, `Balanced`, `Enhanced` levels plus blur slider (`0–28 px`) and Reduced Motion support, mapping cleanly to `org.cinnamon.desktop.interface enable-animations` and `org.cinnamon desktop-effects`.
- **Profiles**: `NEXUS Default`, `Minimal`, `Gaming`, `Productivity`, `Cinematic`, and `Lightweight`, with single-click undo in Settings and `--preset-profile` CLI / `POST /api/personalisation/apply` bridge support.

## Verification Boundaries

- **Verified locally & in CI:** `scripts/check-personalisation.js`, `apply-nexus-cinnamon.sh` theme generation (`NEXUS-*`) + `--revert` + `--dry-run` checks across `--preset-profile`, `--effect-level`, `--panel-size`, `--wallpaper-fit`, and `--accent`, plus `POST /api/personalisation/apply` (`dryRun: true`) via `scripts/check-linux-bridge.py`.
- **Untested (requires booted Linux Mint Cinnamon session):** live Cinnamon compositor/GTK3 visual rendering, `gsettings` panel edge transitions, and live HTTPS wallpaper download/set via `org.cinnamon.desktop.background`.
