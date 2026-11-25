# NEXUS OS — Desktop Prototype

A lightweight browser-based desktop concept with a premium glass UI. This is **not yet a bootable OS** and does not control hardware.

## Prototype features
- Desktop wallpaper, top bar, dock and shortcuts
- App launcher with search
- Control Centre with local Do Not Disturb and lightweight-mode preferences, plus a desktop-only brightness preview
- Notifications entry integrated into Control Centre
- File Manager with an explicit user-selected folder, browsing, search, preview, create, rename, copy, move and delete where supported by the browser
- Software Centre catalogue with search and categories
- System Monitor interface that clearly reports unavailable native telemetry
- Explicit native-service capability boundary that rejects unavailable integrations instead of fabricating values
- Notes with browser-local autosave
- Settings: appearance, wallpaper, accent, glass, performance, notifications, accessibility, system information and native-integration status pages
- Browser launcher (opens valid HTTP/HTTPS links in a new tab)
- Terminal preview with an explicit unavailable-native-Bash state; no fake commands are executed
- Quantum Learning Studio with offline lessons (quantum concepts, Spanish, French, Python), a real single-qubit state-vector lab (`H`, `X`, `Z`, measurement), local XP progress, and an offline lesson guide (not a connected AI service)
- Gaming Hub preview
- Basic calculator

## Run
Serve the repository over HTTP (recommended over `file://` so the File System Access API, local storage, and canvas colour sampling behave consistently):

```sh
python3 -m http.server 4173
# or: npm run dev
```

Then open `http://localhost:4173` in a modern browser.

## Validate
Run `bash scripts/check-foundation.sh` (or `npm test`) from the repository root. This checks the Linux Mint helper scripts and configuration, runs `--dry-run` / `--help` smoke checks, validates JavaScript syntax with Node.js, runs unit tests for the app registry, window manager, native-service boundary, calculator parser, browser URL validator, store catalog, file helpers, calendar, and terminal preview, verifies local scripts/styles/icons referenced by `index.html` and the Store catalog, and rejects unsafe `eval()`/`Function()` execution patterns. Node.js and Python 3 are required for the prototype checks.

## Prototype limitations
The File Manager uses browser file-system permissions only after the user explicitly chooses a folder. Browsers without the File System Access API can open selected files for read-only preview; folder mutations remain unavailable there. File operations are confined to the browser-granted folder. Package installation, hardware controls, system monitoring and Steam/Proton support are not native Linux integrations. Wi-Fi, Bluetooth and system volume controls are unavailable here; no host metrics are fabricated. Notes and desktop preferences use local browser storage. The Browser opens websites in separate tabs.

## Linux foundation status
Linux Mint Xfce on Ubuntu LTS is the selected first base for the reported HP Chromebook x360 14b hardware. Stock Mint reached its live desktop in QEMU on the Mac development host. **This is not a NEXUS image and does not qualify the Chromebook.** See the [MADOO Chromebook qualification plan](docs/MADOO_CHROMEBOOK_QUALIFICATION.md) before any physical-device or firmware work.

## Roadmap
1. Stabilize desktop shell and accessibility.
2. Improve window management and app state.
3. Implement settings persistence and safe local file permissions.
4. Build a Linux-native backend and package the desktop.
5. Integrate system monitoring, power controls and Steam/Proton through legitimate native interfaces.
6. Implement the native Ubuntu GNU Bash terminal through a trusted PTY-backed session service; see [Native Terminal architecture](docs/NATIVE_TERMINAL.md).
