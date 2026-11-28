# NEXUS OS — Native Applications & Ecosystem (Phase 21)

## 1. Native vs Local vs Browser Preview Classification

NEXUS OS explicitly distinguishes how each application operates (`NexusDesktopShell.getAppRuntimeMode(appId)`):

- **Genuinely Native when Bridge Connected (`127.0.0.1` + `X-Nexus-Token`)**:
  - **Terminal**: Real GNU Bash PTY sessions (`/bin/bash -i`) via `/api/terminal/*`.
  - **System Monitor & Performance Centre**: Real `/proc` + `/sys` telemetry and `nexus-performance-cli.sh`.
  - **NEXUS Store**: Real APT (`apt-cache`/`dpkg-query`/`pkexec apt-get`) + Flatpak (`flatpak`) discovery, info, install, update, and removal via `nexus-store-cli.sh`.
  - **File Manager**: Real `$HOME`-jailed directory browsing, text preview, create folder/file, rename, and delete via `/api/files/*` (plus `nemo`/`pcmanfm-qt`/`pcmanfm`/`thunar` native desktop launch). Falls back to browser `showDirectoryPicker` / read-only file preview when disconnected.
  - **Settings**: Connected to `nexus-control-centre-cli.sh`, `nexus-wallpaper-cli.sh`, `nexus-security-cli.sh`, and edition theme/compositor scripts.
  - **Gaming Hub**: Connected to `nexus-gaming-cli.sh` (Steam, Proton, Vulkan/GPU, controllers, GameMode).
  - **Hardware & Beta Centre**: Connected to `nexus-hw-inventory.sh`, `nexus-hw-diagnostics.sh`, and `nexus-recovery.sh`.
  - **Welcome & Installer**: Connected to `nexus-firstboot.sh`, `nexus-install-preflight.sh`, and Ubiquity launcher.
- **Local / Offline Applications**:
  - **Quantum**: Offline single-qubit lab, Quantum/Python/Languages/Linux tracks, personal study notes (`localStorage` or `~/.local/share/nexus-os/quantum-notes.json` when bridge-connected), and offline reviewed guide.
  - **Notes, Calculator, Calendar**: Local desktop utilities stored in browser storage.
- **Browser Preview / External Link Opener**:
  - **NEXUS Browser**: Validated HTTP/HTTPS opener in browser preview; launches native `firefox`/`chromium`/`falkon` on Linux via `nexus-launch-app browser`.

## 2. Package Sources & Trust Assumptions

- **APT (`ubuntu` / `linuxmint`)**: Packages come from configured signed APT repositories verified by GPG keys in `/etc/apt/trusted.gpg.d/`. Privileged installs/removals/cleanups always invoke PolicyKit (`pkexec`) and refuse removing protected base system packages (`systemd`, `ufw`, `polkitd`, `openbox`, `cinnamon`, etc.). Traditional APT packages run unsandboxed under the regular user.
- **Flatpak (`flathub` / configured remotes)**: Uses desktop portal permissions (`flatpak info --show-permissions`) inspectable and revocable in Settings -> Privacy & Security.
- **No Unconsented Execution**: Downloaded files or packages are never executed silently; no credentials are stored in frontend JavaScript.

## 3. Security Boundaries

- **Bridge Isolation**: `nexus-system-bridge.py` refuses to run as root (`euid == 0`), binds strictly to `127.0.0.1`, validates `Origin`, and requires a per-session `0600`-protected `X-Nexus-Token`.
- **`$HOME`-Jailed File Manager**: `SafeHomeFilesManager` resolves all paths against `Path.home().resolve()`, denies `..`/symlink escapes outside `$HOME` (`403`), hides/blocks `.ssh`, `.gnupg`, `.pki`, `.aws`, `.kube`, and protects `.config/nexus-os` from deletion.

## 4. Four-Edition Compatibility

Native launchers (`linux/branding/nexus-launch-app.sh` and `linux/branding/applications/*.desktop`) adapt automatically across **Cinnamon** (`nemo`, `gnome-terminal`, `cinnamon-settings`), **Xfce** (`thunar`, `xfce4-terminal`, `xfce4-settings-manager`), **Lite LXQt** (`pcmanfm-qt`, `qterminal`, `lxqt-config`, `qps`), and **Lite Openbox** (`pcmanfm`, `lxterminal`, `obconf`, `lxtask`). Heavy apps and animations are never forced onto Lite editions.
