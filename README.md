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
- Gaming Hub preview
- Basic calculator

## Run
Open \`index.html\` in a modern browser.

## Validate
Run \`bash scripts/check-foundation.sh\` from the repository root. This checks the Linux helper scripts and configuration, validates JavaScript syntax with Node.js, verifies local scripts/styles/icons referenced by \`index.html\`, and rejects unsafe \`eval()\`/\`Function()\` execution patterns in the prototype. Node.js and Python 3 are required for the prototype checks.

## Prototype limitations
The File Manager uses browser file-system permissions only after the user explicitly chooses a folder. Browsers without the File System Access API can open selected files for read-only preview; folder mutations remain unavailable there. File operations are confined to the browser-granted folder. Package installation, hardware controls, system monitoring and Steam/Proton support are not native Linux integrations. Wi-Fi, Bluetooth and system volume controls are unavailable here; no host metrics are fabricated. Notes and desktop preferences use local browser storage. The Browser opens websites in separate tabs.

## Roadmap
1. Stabilize desktop shell and accessibility.
2. Improve window management and app state.
3. Implement settings persistence and safe local file permissions.
4. Build a Linux-native backend and package the desktop.
5. Integrate system monitoring, power controls and Steam/Proton through legitimate native interfaces.
6. Implement the native Ubuntu GNU Bash terminal through a trusted PTY-backed session service; see [Native Terminal architecture](docs/NATIVE_TERMINAL.md).
