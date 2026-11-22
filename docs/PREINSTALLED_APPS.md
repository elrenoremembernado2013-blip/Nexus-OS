# NEXUS preinstalled application milestone

This milestone extends the static browser desktop; it does not deliver native Linux applications or a bootable operating system.

## Figma design reference

Editable screen concepts for Settings, File Manager, Software Centre, System Monitor and Control Centre are available in [NEXUS OS — System Apps](https://www.figma.com/design/6G7b2TSWi7a0sDelfFBZSM). The frames use the existing desktop palette and distinguish local preview behavior from native-only services.

## Shared application host

`apps/app-registry.js` supplies a small browser-side registry. Each registered app owns its render and mount functions; optional cleanup runs when the app is replaced or closed. The existing desktop window, dock, launcher, theme and preference state remain in `app.js`. Settings sections are added through the registry enhancement hook, while Control Centre remains the shell's integrated quick-settings panel.

## Current capability boundary

| App | Works in the browser prototype | Requires native Linux integration |
|---|---|---|
| Settings | Theme, wallpaper, accent, glass blur, lightweight mode and reduced-motion preferences persist locally; system sections expose the integration boundary | Display, sound, network, Bluetooth, power, accounts, system security and package updates |
| File Manager | User-selected folder browsing, current-folder search, text/image preview, create, rename when supported, copy/cut/paste and confirmed delete; individual file-picker fallback is read-only | Unrestricted home-directory access, removable-device management, system storage capacity and cross-app file permissions |
| NEXUS Store | Catalogue search, categories, listing details, collections, wishlist, launcher library and local activity history; the bundled Calendar can be added to or removed from the launcher | External package discovery/download/install, update checks, verified publisher identity, security scanning, ratings, permissions enforcement and developer submissions |
| System Monitor | Resource and process views clearly identify themselves as unavailable | CPU, RAM, storage, process and network telemetry |
| Control Centre | Local Do Not Disturb and lightweight visual preferences; brightness is only a desktop CSS preview | Wi-Fi, Bluetooth, actual screen brightness, system volume, battery, suspend and power actions |

File access is never requested on startup. The user selects a directory through the browser's picker, and the app operates only on that granted handle. Browser support and secure-context requirements vary; where the picker is unavailable, individual files can be opened read-only. File previews are size-limited and rendered as text or images, never executed.

## NEXUS Store capability boundary

`apps/store-catalog.js` is the single source for app listing metadata and browser-local install, wishlist and activity state. The desktop launcher is rendered from the installed catalog entries, so adding NEXUS Calendar registers its already-bundled code in the launcher; removing it unregisters the launcher entry and retains its local events. Neither action downloads, executes or removes host software. Calendar events and Store state stay in the current browser profile.

The Store includes routes for Home, Discover, Apps, Games, Categories, Collections, My Library, Wishlist, Downloads, Updates and Developer Hub. The catalogue intentionally has no invented ratings, security badges or download progress. Updates are reported as unknown until an update service can actually check. Steam and planned apps have no install action. NEXUS Originals identifies first-party work only; it is not NEXUS Verified and does not imply a security review.

The optional `apps/calendar.js` module supports month navigation, date selection, event creation and deletion with browser-local persistence. It does not provide account sync, reminders, notifications or native calendar integration. If Calendar is removed from the launcher, its event data remains available if it is added again later.

## Future native boundary

`apps/native-services.js` provides the browser-side native integration boundary. It is a capability registry: services start unavailable, integrations must be registered explicitly by the native host, and calls fail with `NativeIntegrationUnavailableError` instead of returning simulated values. The registry does not execute browser commands or dynamically evaluate native code.

The Linux desktop should expose narrowly scoped, permission-aware services to app frontends for file portals, package operations, system telemetry, network/audio/display controls and notifications. This prototype deliberately does not choose a toolkit or invent a browser-to-host bridge; the desktop toolkit and service protocol remain open platform decisions in `PLATFORM_ARCHITECTURE.md`.

## Verification limits

The browser prototype can validate navigation, local preference state, catalogue filtering and the explicit file-picker workflow. Native device controls, package operations, host metrics, removable media, QEMU/Ubuntu behavior and full hardware integration require a Linux environment and are not validated by this milestone.
