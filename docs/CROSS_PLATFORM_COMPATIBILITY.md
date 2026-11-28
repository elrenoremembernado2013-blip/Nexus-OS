# NEXUS OS — Cross-Platform Application Compatibility (Phase 22)

NEXUS OS supports four application ecosystems transparently without claiming universal compatibility. Applications are clearly classified as **Native**, **Compatible**, **Partially compatible**, **Experimental**, **Unsupported**, or **Not tested**, and **Tested** entries are distinguished from **Estimated** compatibility.

## 1. Supported Ecosystems

### Linux (`Native`)
- **APT / `.deb`**: Primary signed system package ecosystem (`nexus-store-cli.sh`, `pkexec apt-get`, `dpkg-deb`).
- **Flatpak**: Sandboxed desktop applications via Flathub with inspectable portal permissions (`Settings -> Privacy & Security`).
- **AppImage**: Portable ELF + SquashFS bundles requiring matching CPU architecture, user execute permission (`+x` set only by the user after verification), and FUSE2 (`libfuse2t64` / `libfuse2`).

### Windows (`Translated` — Optional)
- **Wine**: Runs compatible `.exe` (PE32/PE32+) and `.msi` applications inside isolated user prefixes (`~/.local/share/nexus-os/wine-prefixes/<name>`). 32-bit Windows binaries on `x86_64` hosts require `i386` multiarch and `wine32`.
- **Proton (Steam Play)**: Runs compatible Windows games via Steam/Lutris/Heroic with Vulkan/DXVK. Games relying on kernel-level anti-cheat (e.g. Vanguard, Ricochet, Faceit) or Windows kernel drivers remain **Unsupported**.

### Android (`Containerised` — Optional)
- **Waydroid**: Optional LXC Android container requiring Linux kernel `binder_linux` support and a Wayland compositor (or nested `weston`/`cage` on X11 Cinnamon/Xfce/Openbox/LXQt).
- **Google Play Services**: Not included by default. Apps requiring Google Play Integrity / SafetyNet attestation remain **Unsupported** unless the user independently deploys compatible services.
- **ARM vs x86_64**: Pure ARM APKs (`arm64-v8a` / `armeabi-v7a`) on `x86_64` require binary translation (`libndk_translation` / `houdini`).
- **Low-RAM & Lite Editions**: Waydroid is optional and explicitly discouraged on `< 3.5 GiB` RAM and Lite editions.

### Apple (`Unsupported` — Honest Alternatives)
- Direct execution of macOS (`.dmg`, `.pkg`, `.app`, Mach-O) and iOS (`.ipa`, FairPlay/UIKit) applications is **Unsupported** on Linux due to Darwin/XNU ABI differences, proprietary Apple frameworks, code signing/FairPlay DRM, and Apple licensing terms.
- NEXUS OS never attempts to circumvent Apple licensing or security protections. Users are guided to official Web Apps (iCloud Web, Apple Music Web) or native open-source Linux alternatives (LibreOffice, GIMP, Kdenlive, Ardour, VS Code, Thunderbird).

## 2. Security & Least-Privilege Guarantees
- **Read-only inspection**: `nexus-compat-cli.sh inspect` and `NexusCompatibilityClassifier.classifyBuffer()` read only magic bytes/headers and **never execute** downloaded `.exe`, `.msi`, `.AppImage`, or `.apk` files.
- **Explicit user confirmation**: Launching external binaries (`nexus-compat-cli launch`) and installing optional runtimes (`nexus-compat-cli install-runtime`) require explicit confirmation and PolicyKit (`pkexec`) authentication where privileged.
- **Preserved Linux security**: UFW firewall, APT GPG signature verification, PolicyKit, and Flatpak sandboxes are never weakened for compatibility.
- **4-Edition Parity**: Cinnamon, Xfce, Lite LXQt, and Lite Openbox all ship `nexus-compat-cli` and `nexus-compatibility.desktop`, while Wine, Proton, and Waydroid remain strictly optional and excluded from Lite package manifests.
