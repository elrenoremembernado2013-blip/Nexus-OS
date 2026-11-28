#!/usr/bin/env bash
# NEXUS OS Phase 22 Cross-Platform Compatibility Engine & Runtime Manager.
# Covers Linux (APT/DEB, Flatpak, AppImage), Windows (Wine, Proton),
# Android (Waydroid), and Apple (honest licensing/ABI status + Web/FOSS alternatives).
# Never auto-executes untrusted binaries and never fabricates compatibility claims.
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")" && pwd)"
STORE_CLI="$SCRIPT_DIR/nexus-store-cli.sh"
[[ -x "$STORE_CLI" ]] || STORE_CLI="$(command -v nexus-store-cli || true)"
PREFIX_BASE="${XDG_DATA_HOME:-$HOME/.local/share}/nexus-os/wine-prefixes"

DRY_RUN=false
CONFIRM_ACTION=false
FORCE_LOW_RAM=false

usage() {
  cat <<'USAGE'
Usage: bash linux/mint/nexus-compat-cli.sh [OPTIONS] <command> [args...]

Inspects host architecture, cross-platform compatibility runtimes (Linux APT/Flatpak/
AppImage, Windows Wine/Proton, Android Waydroid, Apple alternatives), inspects
package/executable formats read-only without executing them, and manages isolated
Wine prefixes or optional runtime installs via PolicyKit.

Options:
  --json            Emit JSON output
  --dry-run         Preview actions without modifying the system
  --confirm         Confirm runtime installation or confirmed application launch
  --force-low-ram   Allow optional runtime install even when RAM is below 3.5 GiB
  --help, -h        Show this help message

Commands:
  status                         Report real host arch, RAM, Wayland/X11, and runtimes
  catalog                        Output curated Linux/Windows/Android/Apple compatibility matrix
  inspect <file> [filename]      Read-only magic-byte format, arch, and compatibility inspection
  prefix list                    List isolated NEXUS Wine prefixes
  prefix create <slug>           Create an isolated Wine prefix directory (never touches /)
  install-runtime <id>           Install optional runtime (wine|waydroid|flatpak|appimage-fuse)
  launch <file>                  Launch user-confirmed file inside appropriate runtime (--confirm required)
USAGE
}

while (($#)); do
  case "$1" in
    --json) shift ;;
    --dry-run) DRY_RUN=true; shift ;;
    --confirm) CONFIRM_ACTION=true; shift ;;
    --force-low-ram) FORCE_LOW_RAM=true; shift ;;
    --help|-h) usage; exit 0 ;;
    --) shift; break ;;
    -*) printf 'Unknown option: %s\n' "$1" >&2; usage >&2; exit 2 ;;
    *) break ;;
  esac
done

[[ $# -ge 1 ]] || { usage >&2; exit 2; }
CMD="$1"
shift

case "$CMD" in
  status)
    python3 - "$PREFIX_BASE" <<'PY'
import json
import os
from pathlib import Path
import platform
import re
import shutil
import subprocess
import sys

prefix_base = Path(sys.argv[1])

def read_text(path: Path) -> str | None:
    try:
        return path.read_text(encoding="utf-8", errors="replace").strip()
    except OSError:
        return None

def run_out(cmd: list[str], timeout: float = 2.5) -> tuple[int, str]:
    try:
        res = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
        return res.returncode, (res.stdout or res.stderr or "").strip()
    except Exception:
        return 127, ""

machine = platform.machine() or "unknown"
dpkg_arch = run_out(["dpkg", "--print-architecture"])[1] if shutil.which("dpkg") else machine
foreign_arches = []
if shutil.which("dpkg"):
    rc, out = run_out(["dpkg", "--print-foreign-architectures"])
    if rc == 0 and out:
        foreign_arches = [line.strip() for line in out.splitlines() if line.strip()]

mem_total_mib = None
mem_raw = read_text(Path("/proc/meminfo"))
if mem_raw:
    for line in mem_raw.splitlines():
        if line.startswith("MemTotal:"):
            parts = line.split()
            if len(parts) >= 2 and parts[1].isdigit():
                mem_total_mib = round(int(parts[1]) / 1024)
            break

low_ram = mem_total_mib is not None and mem_total_mib < 3500
cpu_raw = read_text(Path("/proc/cpuinfo")) or ""
virt_flags = any(flag in cpu_raw.split() for flag in ("vmx", "svm"))
kvm_available = os.path.exists("/dev/kvm")
session_type = os.environ.get("XDG_SESSION_TYPE") or ("wayland" if os.environ.get("WAYLAND_DISPLAY") else ("x11" if os.environ.get("DISPLAY") else "headless"))
desktop_env = (os.environ.get("XDG_CURRENT_DESKTOP") or os.environ.get("DESKTOP_SESSION") or "").lower()
is_lite_edition = "openbox" in desktop_env or "lxqt" in desktop_env

# Linux ecosystem
apt_ok = shutil.which("apt-get") is not None and shutil.which("dpkg-deb") is not None
flatpak_bin = shutil.which("flatpak")
flatpak_remotes = []
if flatpak_bin:
    rc, out = run_out(["flatpak", "remotes", "--columns=name"])
    if rc == 0 and out:
        flatpak_remotes = [r.strip() for r in out.splitlines() if r.strip()]

fuse2_ok = any(Path(p).exists() for p in (
    "/usr/lib/x86_64-linux-gnu/libfuse.so.2",
    "/lib/x86_64-linux-gnu/libfuse.so.2",
    "/usr/lib/aarch64-linux-gnu/libfuse.so.2",
)) or shutil.which("fusermount") is not None

# Windows ecosystem
wine_bin = shutil.which("wine") or shutil.which("wine64")
wine_ver = run_out([wine_bin, "--version"])[1] if wine_bin else None
winetricks_ok = shutil.which("winetricks") is not None
bottles_ok = shutil.which("bottles") is not None or (Path.home() / ".local/share/flatpak/app/com.usebottles.bottles").is_dir() or Path("/var/lib/flatpak/app/com.usebottles.bottles").is_dir()
lutris_ok = shutil.which("lutris") is not None or (Path.home() / ".local/share/flatpak/app/net.lutris.Lutris").is_dir() or Path("/var/lib/flatpak/app/net.lutris.Lutris").is_dir()
steam_bin = shutil.which("steam") is not None
proton_versions = []
for sroot in (
    Path.home() / ".local/share/Steam/steamapps",
    Path.home() / ".steam/steam/steamapps",
    Path.home() / ".var/app/com.valvesoftware.Steam/.local/share/Steam/steamapps",
):
    if (sroot / "common").is_dir():
        for p in sorted((sroot / "common").glob("Proton*")):
            if p.is_dir() and p.name not in proton_versions:
                proton_versions.append(p.name)
    if (sroot / "compatibilitytools.d").is_dir():
        for p in sorted((sroot / "compatibilitytools.d").iterdir()):
            if p.is_dir() and p.name not in proton_versions:
                proton_versions.append(p.name)

prefixes = []
if prefix_base.is_dir():
    for d in sorted(prefix_base.iterdir()):
        if d.is_dir():
            prefixes.append({"name": d.name, "path": str(d), "initialized": (d / "system.reg").is_file()})

# Android ecosystem (Waydroid)
waydroid_bin = shutil.which("waydroid")
waydroid_ver = run_out(["waydroid", "--version"])[1] if waydroid_bin else None
waydroid_container = "not_installed"
if waydroid_bin:
    rc, wd_out = run_out(["waydroid", "status"], timeout=2.0)
    waydroid_container = "running" if ("RUNNING" in wd_out) else ("stopped" if rc == 0 else "uninitialized")
binder_ready = os.path.exists("/dev/binderfs") or os.path.exists("/dev/binder") or Path("/sys/module/binder_linux").is_dir()
nested_wayland = shutil.which("weston") is not None or shutil.which("cage") is not None
gms_supported = False  # Never claim Google Play Services unless user explicitly installed a GMS/microG image and verified

payload = {
    "schema_version": 1,
    "host": {
        "machine": machine,
        "dpkg_arch": dpkg_arch,
        "foreign_arches": foreign_arches,
        "i386_multiarch": "i386" in foreign_arches,
        "mem_total_mib": mem_total_mib,
        "low_ram": low_ram,
        "session_type": session_type,
        "desktop_env": desktop_env or "unknown",
        "is_lite_edition": is_lite_edition,
        "kvm_available": kvm_available,
        "cpu_virtualisation": virt_flags,
    },
    "ecosystems": {
        "linux": {
            "apt": apt_ok,
            "flatpak": bool(flatpak_bin),
            "flatpak_remotes": flatpak_remotes,
            "appimage_fuse2": fuse2_ok,
            "status": "Native",
        },
        "windows": {
            "wine_installed": bool(wine_bin),
            "wine_version": wine_ver,
            "winetricks": winetricks_ok,
            "bottles": bottles_ok,
            "lutris": lutris_ok,
            "steam": steam_bin,
            "proton_versions": proton_versions,
            "prefixes": prefixes,
            "status": "Compatible" if (wine_bin or proton_versions) else "Optional runtime not installed",
            "limitations": [
                "32-bit Windows apps on x86_64 require i386 multiarch and wine32.",
                "Kernel-level anti-cheat games and drivers are Unsupported under Wine/Proton.",
            ],
        },
        "android": {
            "waydroid_installed": bool(waydroid_bin),
            "waydroid_version": waydroid_ver,
            "container_status": waydroid_container,
            "binder_ready": binder_ready,
            "wayland_ready": session_type == "wayland" or nested_wayland,
            "nested_wayland_tool": "weston" if shutil.which("weston") else ("cage" if shutil.which("cage") else None),
            "gms_included": gms_supported,
            "recommended_for_host": not low_ram and not is_lite_edition,
            "status": "Containerised (Waydroid)" if waydroid_bin else "Optional runtime not installed",
            "limitations": [
                "Waydroid requires a Wayland session (or nested Weston/Cage on X11 Cinnamon/Xfce/Openbox) and Linux binder_linux kernel support.",
                "Google Play Services & Play Integrity are NOT included by default; banking/DRM apps depending on GMS are Unsupported without verified alternatives.",
                "ARM-only APKs on x86_64 hosts require libndk_translation or houdini.",
                "Not recommended on systems below 3.5 GiB RAM or Lite editions.",
            ],
        },
        "apple": {
            "direct_execution_supported": False,
            "status": "Unsupported",
            "reasons": [
                "macOS (.app, .dmg, .pkg) and iOS (.ipa) binaries use Darwin/XNU Mach-O ABIs, proprietary frameworks, FairPlay/App Store signing, and Apple licensing terms that forbid running macOS on non-Apple hardware.",
                "NEXUS OS does not attempt to bypass Apple licensing, signing, or security protections.",
            ],
            "alternatives": [
                {"name": "iCloud Web / Apple Music Web", "kind": "Web App", "url": "https://www.icloud.com"},
                {"name": "Open-Source Linux Equivalents", "kind": "Native", "detail": "LibreOffice, GIMP, Kdenlive, Ardour, VS Code, Thunderbird"},
                {"name": "CalDAV / CardDAV / WebDAV", "kind": "Protocol", "detail": "Standard open sync without proprietary macOS runtime"},
            ],
        },
    },
}
print(json.dumps(payload, indent=2))
PY
    ;;

  catalog)
    python3 - <<'PY'
import json
catalog = [
    {
        "id": "firefox-linux",
        "name": "Mozilla Firefox",
        "source_os": "Linux",
        "format": "APT / Flatpak",
        "execution": "Native",
        "runtime": "Linux APT / Flatpak",
        "status": "Native",
        "tested": "Tested",
        "arch": ["amd64", "arm64"],
        "limitations": "Hardware video decode depends on Mesa/VA-API or NVIDIA drivers.",
        "guidance": "Install via NEXUS Store (APT firefox or Flathub org.mozilla.firefox).",
    },
    {
        "id": "libreoffice-linux",
        "name": "LibreOffice Suite",
        "source_os": "Linux",
        "format": "APT / Flatpak",
        "execution": "Native",
        "runtime": "Linux APT / Flatpak",
        "status": "Native",
        "tested": "Tested",
        "arch": ["amd64", "arm64"],
        "limitations": "Complex proprietary DOCX/XLSX macros may vary slightly.",
        "guidance": "Install via NEXUS Store (APT libreoffice or Flatpak org.libreoffice.LibreOffice).",
    },
    {
        "id": "appimage-generic",
        "name": "Portable Linux AppImages (.AppImage)",
        "source_os": "Linux",
        "format": ".AppImage (ELF + SquashFS)",
        "execution": "Native",
        "runtime": "FUSE2 (libfuse2t64 / libfuse2)",
        "status": "Compatible",
        "tested": "Estimated",
        "arch": ["x86_64", "aarch64"],
        "limitations": "Requires matching CPU architecture, user execute permission after inspection, and FUSE2 (or --appimage-extract).",
        "guidance": "Inspect file checksum and permissions in Compatibility Centre before marking executable.",
    },
    {
        "id": "notepadpp-win",
        "name": "Notepad++ (.exe)",
        "source_os": "Windows",
        "format": ".exe (PE32 / PE32+)",
        "execution": "Translated",
        "runtime": "Wine",
        "status": "Compatible",
        "tested": "Estimated",
        "arch": ["x86_64", "i386"],
        "limitations": "Estimated from Wine compatibility data; isolated prefix recommended. Native alternatives: Mousepad, FeatherPad, VS Code.",
        "guidance": "Create an isolated Wine prefix first, inspect the .exe, and launch with confirmation.",
    },
    {
        "id": "7zip-win",
        "name": "7-Zip GUI (.exe / .msi)",
        "source_os": "Windows",
        "format": ".exe / .msi",
        "execution": "Translated",
        "runtime": "Wine",
        "status": "Compatible",
        "tested": "Estimated",
        "arch": ["x86_64", "i386"],
        "limitations": "Shell context-menu extensions apply only inside Wine; native p7zip/file-roller handles archives directly.",
        "guidance": "Prefer native p7zip-full / lxqt-archiver, or run inside an isolated Wine prefix.",
    },
    {
        "id": "steam-proton-games",
        "name": "Windows Steam Games via Proton",
        "source_os": "Windows",
        "format": "Steam / PE32+",
        "execution": "Translated",
        "runtime": "Proton (Steam Play) + Vulkan/DXVK",
        "status": "Partially compatible",
        "tested": "Estimated",
        "arch": ["x86_64"],
        "limitations": "Single-player and Valve-verified titles often run well; games using kernel-level anti-cheat (Vanguard, Ricochet, Faceit) are Unsupported.",
        "guidance": "Enable Steam Play in Steam Settings and check GPU/Vulkan readiness in Gaming Hub.",
    },
    {
        "id": "adobe-cc-win",
        "name": "Adobe Creative Cloud / Photoshop (.exe)",
        "source_os": "Windows",
        "format": ".exe",
        "execution": "Translated",
        "runtime": "Wine",
        "status": "Unsupported",
        "tested": "Estimated",
        "arch": ["x86_64"],
        "limitations": "Modern Creative Cloud DRM, background services, and GPU hooks fail reliably in Wine.",
        "guidance": "Use GIMP, Krita, Darktable, or Photopea (Web App) instead.",
    },
    {
        "id": "rufus-win",
        "name": "Rufus USB Writer (.exe)",
        "source_os": "Windows",
        "format": ".exe",
        "execution": "Translated",
        "runtime": "Wine",
        "status": "Unsupported",
        "tested": "Estimated",
        "arch": ["x86_64"],
        "limitations": "Requires Windows raw block-device kernel APIs not exposed safely inside Wine.",
        "guidance": "Use Linux Mint USB Image Writer (mintstick) or BalenaEtcher AppImage.",
    },
    {
        "id": "fdroid-android",
        "name": "F-Droid & Open-Source Android APKs (.apk)",
        "source_os": "Android",
        "format": ".apk",
        "execution": "Containerised",
        "runtime": "Waydroid (LXC + Wayland)",
        "status": "Compatible",
        "tested": "Estimated",
        "arch": ["x86_64", "arm64"],
        "limitations": "Requires Waydroid container + Wayland (or nested Weston on X11) + kernel binder; pure ARM APKs on x86_64 need translation libs.",
        "guidance": "Optional on 4+ GiB RAM systems; keep disabled on Lite 512 MB / 1 GB editions.",
    },
    {
        "id": "gms-banking-android",
        "name": "Google Play Integrity / Banking Apps (.apk)",
        "source_os": "Android",
        "format": ".apk",
        "execution": "Containerised",
        "runtime": "Waydroid + Certified Google Play Integrity",
        "status": "Unsupported",
        "tested": "Estimated",
        "arch": ["x86_64", "arm64"],
        "limitations": "Waydroid does not provide certified Google Play Services / SafetyNet / Play Integrity attestation.",
        "guidance": "Use the provider's official Web App in Firefox instead.",
    },
    {
        "id": "macos-app-dmg",
        "name": "macOS Applications (.dmg / .pkg / .app)",
        "source_os": "Apple (macOS)",
        "format": ".dmg / .pkg / .app",
        "execution": "Unsupported",
        "runtime": "None on Linux (Darwin/Mach-O)",
        "status": "Unsupported",
        "tested": "Tested",
        "arch": ["arm64", "x86_64"],
        "limitations": "Incompatible Mach-O ABI, Apple frameworks, code signing, and Apple licensing constraints.",
        "guidance": "Use Web Apps (iCloud, Apple Music Web) or native Linux equivalents (Kdenlive, Ardour, LibreOffice).",
    },
    {
        "id": "ios-ipa-app",
        "name": "iOS / iPadOS Apps (.ipa)",
        "source_os": "Apple (iOS)",
        "format": ".ipa",
        "execution": "Unsupported",
        "runtime": "None on Linux (iOS FairPlay/UIKit)",
        "status": "Unsupported",
        "tested": "Tested",
        "arch": ["arm64"],
        "limitations": "Encrypted App Store FairPlay binaries and iOS UIKit runtime cannot run legally or technically on Linux.",
        "guidance": "Check for a Web App or native Linux/Android alternative.",
    },
]
print(json.dumps({"schema_version": 1, "entries": catalog}, indent=2))
PY
    ;;

  inspect)
    [[ $# -ge 1 ]] || { echo "inspect requires a file path" >&2; exit 2; }
    TARGET_FILE="$1"
    DISPLAY_NAME="${2:-$(basename -- "$TARGET_FILE")}"
    python3 - "$TARGET_FILE" "$DISPLAY_NAME" <<'PY'
import json
import os
from pathlib import Path
import platform
import shutil
import struct
import subprocess
import sys
import zipfile

target = Path(sys.argv[1])
display_name = sys.argv[2]
lower_name = display_name.lower()

if not target.is_file():
    print(json.dumps({"error": f"File not found: {display_name}"}))
    sys.exit(1)

size_bytes = target.stat().st_size
executable_bit = os.access(target, os.X_OK)
host_machine = platform.machine() or "x86_64"

with target.open("rb") as f:
    head = f.read(4096)
    f.seek(max(0, size_bytes - 512))
    tail = f.read(512)

wine_present = shutil.which("wine") is not None or shutil.which("wine64") is not None
waydroid_present = shutil.which("waydroid") is not None
dpkg_present = shutil.which("dpkg-deb") is not None
flatpak_present = shutil.which("flatpak") is not None
fuse2_ok = any(Path(p).exists() for p in (
    "/usr/lib/x86_64-linux-gnu/libfuse.so.2",
    "/lib/x86_64-linux-gnu/libfuse.so.2",
    "/usr/lib/aarch64-linux-gnu/libfuse.so.2",
)) or shutil.which("fusermount") is not None

result = {
    "filename": display_name,
    "size_bytes": size_bytes,
    "executable_bit": executable_bit,
    "host_arch": host_machine,
    "executed": False,
    "format": "Unknown",
    "source_os": "Unknown",
    "target_arch": "unknown",
    "execution_kind": "Unknown",
    "runtime": "None detected",
    "runtime_installed": False,
    "status": "Not tested",
    "confidence": "Estimated compatibility (static format inspection; file was NOT executed)",
    "missing_dependencies": [],
    "security_notes": [
        "File was inspected read-only via header/magic bytes and has NOT been executed.",
        "Always verify download source checksums/signatures before launching.",
    ],
    "guidance": "",
}

# 1. Windows PE (.exe / .dll)
if head[:2] == b"MZ" and len(head) >= 64:
    pe_offset = struct.unpack_from("<I", head, 0x3C)[0]
    is_pe = pe_offset + 6 <= len(head) and head[pe_offset:pe_offset + 4] == b"PE\x00\x00"
    arch_map = {0x014C: "i386 (32-bit x86)", 0x8664: "x86_64 (64-bit)", 0xAA64: "arm64"}
    if is_pe:
        mach = struct.unpack_from("<H", head, pe_offset + 4)[0]
        t_arch = arch_map.get(mach, f"0x{mach:04x}")
        result.update({
            "format": "Windows PE Executable (.exe)",
            "source_os": "Windows",
            "target_arch": t_arch,
            "execution_kind": "Translated (Wine / Proton)",
            "runtime": "Wine (or Proton for Steam games)",
            "runtime_installed": wine_present,
            "status": "Partially compatible" if mach == 0xAA64 else ("Compatible" if wine_present else "Partially compatible"),
            "guidance": "Run inside an isolated Wine prefix (~/.local/share/nexus-os/wine-prefixes/) after verifying publisher trust." if wine_present else "Install optional Wine runtime via Compatibility Centre or use a native Linux alternative.",
        })
        if not wine_present:
            result["missing_dependencies"].append("wine / wine64 runtime")
        if mach == 0x014C:
            result["security_notes"].append("32-bit Windows binary: requires i386 multiarch & wine32 on 64-bit Linux.")
        if mach == 0xAA64 and host_machine in ("x86_64", "amd64"):
            result["status"] = "Unsupported"
            result["missing_dependencies"].append("Windows ARM64 emulation (host is x86_64)")
    else:
        result.update({
            "format": "DOS / Legacy MZ Binary",
            "source_os": "Windows / DOS",
            "execution_kind": "Translated (DOSBox / Wine)",
            "runtime": "DOSBox / Wine",
            "status": "Experimental",
            "guidance": "Legacy 16-bit MZ executables typically require DOSBox rather than Wine.",
        })

# 2. Windows MSI Installer
elif head[:8] == b"\xd0\xcf\x11\xe0\xa1\xb1\x1a\xe1" and lower_name.endswith(".msi"):
    result.update({
        "format": "Windows Installer Package (.msi)",
        "source_os": "Windows",
        "target_arch": "x86 / x86_64",
        "execution_kind": "Translated (Wine msiexec)",
        "runtime": "Wine (msiexec)",
        "runtime_installed": wine_present,
        "status": "Compatible" if wine_present else "Partially compatible",
        "guidance": "Install into a dedicated Wine prefix with `WINEPREFIX=... wine msiexec /i <file>.msi` after verification.",
    })
    if not wine_present:
        result["missing_dependencies"].append("wine runtime")

# 3. Linux Debian Package (.deb)
elif head[:8] == b"!<arch>\n" and b"debian-binary" in head[:64]:
    deb_arch = "unknown"
    pkg_name = display_name
    deps = ""
    if dpkg_present:
        try:
            out = subprocess.check_output(["dpkg-deb", "-f", str(target), "Package", "Architecture", "Version"], text=True, timeout=3)
            for line in out.splitlines():
                if line.startswith("Architecture:"):
                    deb_arch = line.split(":", 1)[1].strip()
                elif line.startswith("Package:"):
                    pkg_name = line.split(":", 1)[1].strip()
        except Exception:
            pass
    arch_ok = deb_arch in ("all", "amd64" if host_machine == "x86_64" else host_machine, host_machine)
    result.update({
        "format": f"Debian / Ubuntu Package (.deb · {pkg_name})",
        "source_os": "Linux",
        "target_arch": deb_arch,
        "execution_kind": "Native",
        "runtime": "APT / dpkg",
        "runtime_installed": dpkg_present,
        "status": "Native" if (dpkg_present and arch_ok) else "Unsupported",
        "confidence": "Format verified via dpkg-deb header (compatibility with current distro libraries depends on APT dependencies)",
        "guidance": "Install via PolicyKit (`sudo apt install ./file.deb`) only from trusted signed sources." if arch_ok else f"Architecture mismatch: package is {deb_arch}, host is {host_machine}.",
    })
    if not arch_ok:
        result["missing_dependencies"].append(f"compatible architecture ({deb_arch} != {host_machine})")

# 4. Linux ELF / AppImage
elif head[:4] == b"\x7fELF":
    e_machine = struct.unpack_from("<H", head, 18)[0] if len(head) >= 20 else 0
    elf_arch = {62: "x86_64", 183: "aarch64", 3: "i386"}.get(e_machine, f"machine-{e_machine}")
    is_appimage = (len(head) >= 11 and head[8:11] == b"AI\x02") or lower_name.endswith(".appimage")
    arch_ok = elf_arch == host_machine or (elf_arch == "i386" and host_machine == "x86_64")
    if is_appimage:
        result.update({
            "format": "Linux AppImage",
            "source_os": "Linux",
            "target_arch": elf_arch,
            "execution_kind": "Native (portable bundle)",
            "runtime": "Linux kernel + FUSE2",
            "runtime_installed": fuse2_ok and arch_ok,
            "status": "Compatible" if (arch_ok and fuse2_ok) else ("Partially compatible" if arch_ok else "Unsupported"),
            "guidance": "Verify SHA-256 checksum, keep in ~/Applications/, and mark executable only when ready to run." if arch_ok else f"CPU architecture mismatch ({elf_arch} vs {host_machine}).",
        })
        if not fuse2_ok:
            result["missing_dependencies"].append("libfuse2 / libfuse2t64 (or pass --appimage-extract)")
        if not executable_bit:
            result["missing_dependencies"].append("executable permission bit (+x) — intentionally off until user confirms")
    else:
        result.update({
            "format": "Linux Native ELF Binary",
            "source_os": "Linux",
            "target_arch": elf_arch,
            "execution_kind": "Native",
            "runtime": "Linux ELF loader",
            "runtime_installed": arch_ok,
            "status": "Native" if arch_ok else "Unsupported",
            "guidance": "Inspect source trust before running standalone ELF binaries.",
        })

# 5. ZIP containers: Android APK vs Apple IPA
elif head[:4] in (b"PK\x03\x04", b"PK\x05\x06"):
    is_apk = False
    is_ipa = False
    abis = set()
    gms_hint = False
    try:
        with zipfile.ZipFile(target, "r") as zf:
            names = zf.namelist()
            is_apk = "AndroidManifest.xml" in names
            is_ipa = any(n.startswith("Payload/") and ".app/" in n for n in names)
            for n in names:
                if n.startswith("lib/") and n.count("/") >= 2:
                    abis.add(n.split("/")[1])
            if is_apk:
                manifest_raw = zf.read("AndroidManifest.xml")
                if b"com.google.android.gms" in manifest_raw or b"com.android.vending" in manifest_raw:
                    gms_hint = True
    except zipfile.BadZipFile:
        pass

    if is_apk or lower_name.endswith(".apk"):
        abi_list = sorted(abis)
        native_x86 = any(a in abi_list for a in ("x86_64", "x86"))
        arm_only = bool(abi_list) and not native_x86 and host_machine == "x86_64"
        st = "Unsupported" if gms_hint else ("Experimental" if arm_only else ("Compatible" if waydroid_present else "Partially compatible"))
        result.update({
            "format": "Android Application Package (.apk)",
            "source_os": "Android",
            "target_arch": ", ".join(abi_list) if abi_list else "Architecture-independent (Dalvik/ART bytecode)",
            "execution_kind": "Containerised (Waydroid)",
            "runtime": "Waydroid",
            "runtime_installed": waydroid_present,
            "status": st,
            "guidance": "This APK references Google Play Services / Vending; it will likely fail without certified GMS." if gms_hint else ("Install inside Waydroid only after verifying APK signature." if waydroid_present else "Install optional Waydroid runtime (4+ GiB RAM recommended)."),
        })
        if not waydroid_present:
            result["missing_dependencies"].append("waydroid container runtime")
        if arm_only:
            result["missing_dependencies"].append("ARM-to-x86_64 translation (libndk_translation / houdini)")
        if gms_hint:
            result["missing_dependencies"].append("Google Play Services / Play Integrity (not bundled)")
    elif is_ipa or lower_name.endswith(".ipa"):
        result.update({
            "format": "Apple iOS Application Archive (.ipa)",
            "source_os": "Apple (iOS / iPadOS)",
            "target_arch": "arm64 (Apple Silicon)",
            "execution_kind": "Unsupported",
            "runtime": "None on Linux",
            "runtime_installed": False,
            "status": "Unsupported",
            "confidence": "Verified unsupported format (iOS Mach-O / FairPlay / UIKit)",
            "guidance": "iOS .ipa apps cannot run on Linux. Use the app's Web App or a native Linux/Android alternative.",
        })

# 6. Apple macOS DMG / PKG / Mach-O
elif tail[-512:].find(b"koly") != -1 or lower_name.endswith(".dmg") or head[:4] == b"xar!" or lower_name.endswith(".pkg") or head[:4] in (b"\xfe\xed\xfa\xcf", b"\xcf\xfa\xed\xfe", b"\xca\xfe\xba\xbe"):
    fmt = "Apple macOS Disk Image (.dmg)" if lower_name.endswith(".dmg") or b"koly" in tail else (
        "Apple macOS Installer (.pkg)" if head[:4] == b"xar!" or lower_name.endswith(".pkg") else "Apple Mach-O Executable"
    )
    result.update({
        "format": fmt,
        "source_os": "Apple (macOS)",
        "target_arch": "arm64 / x86_64 (Darwin Mach-O)",
        "execution_kind": "Unsupported",
        "runtime": "None on Linux (Darwin/XNU)",
        "runtime_installed": False,
        "status": "Unsupported",
        "confidence": "Verified unsupported OS format & licensing restriction",
        "guidance": "macOS applications are not supported on Linux. Use Web Apps (e.g., iCloud.com) or native Linux equivalents (LibreOffice, GIMP, Kdenlive, Ardour).",
    })

# 7. Flatpak Ref / Bundle
elif lower_name.endswith((".flatpakref", ".flatpak")) or b"[Flatpak Ref]" in head:
    result.update({
        "format": "Linux Flatpak Reference / Bundle",
        "source_os": "Linux",
        "target_arch": host_machine,
        "execution_kind": "Containerised (Flatpak sandbox)",
        "runtime": "Flatpak",
        "runtime_installed": flatpak_present,
        "status": "Native" if flatpak_present else "Partially compatible",
        "guidance": "Install via Flatpak and inspect sandbox permissions in Settings -> Privacy & Security." if flatpak_present else "Install Flatpak via NEXUS Store.",
    })
    if not flatpak_present:
        result["missing_dependencies"].append("flatpak")

print(json.dumps(result, indent=2))
PY
    ;;

  prefix)
    sub="${1:-list}"
    shift || true
    case "$sub" in
      list)
        python3 - "$PREFIX_BASE" <<'PY'
import json, sys
from pathlib import Path
base = Path(sys.argv[1])
items = []
if base.is_dir():
    for d in sorted(base.iterdir()):
        if d.is_dir():
            items.append({"name": d.name, "path": str(d), "initialized": (d / "system.reg").is_file()})
print(json.dumps({"base": str(base), "prefixes": items}))
PY
        ;;
      create)
        slug="${1:-}"
        [[ "$slug" =~ ^[A-Za-z0-9_-]{1,48}$ ]] || { echo "Invalid Wine prefix name (use 1-48 alphanumeric/_/- chars)" >&2; exit 2; }
        target="$PREFIX_BASE/$slug"
        if [[ "$DRY_RUN" == true ]]; then
          printf '{"ok":true,"dryRun":true,"name":"%s","path":"%s"}\n' "$slug" "$target"
        else
          mkdir -p -m 0700 "$target"
          printf '{"ok":true,"name":"%s","path":"%s"}\n' "$slug" "$target"
        fi
        ;;
      *)
        echo "Usage: prefix {list|create <name>}" >&2
        exit 2
        ;;
    esac
    ;;

  install-runtime)
    rt="${1:-}"
    case "$rt" in
      wine) pkg="wine" ;;
      waydroid) pkg="waydroid" ;;
      flatpak) pkg="flatpak" ;;
      appimage-fuse) pkg="libfuse2t64" ;;
      *) echo "Unsupported runtime id: $rt (expected wine, waydroid, flatpak, appimage-fuse)" >&2; exit 2 ;;
    esac

    if [[ "$rt" == "waydroid" && "$FORCE_LOW_RAM" == false ]]; then
      mem_mib="$(awk '/MemTotal:/ {print int($2/1024)}' /proc/meminfo 2>/dev/null || echo 0)"
      if [[ "$mem_mib" -gt 0 && "$mem_mib" -lt 3500 && "$DRY_RUN" == false ]]; then
        echo "Waydroid is not recommended below 3.5 GiB RAM (detected ${mem_mib} MiB). Pass --force-low-ram to override." >&2
        exit 2
      fi
    fi

    if [[ "$DRY_RUN" == false && "$CONFIRM_ACTION" == false ]]; then
      echo "Refusing runtime installation without explicit --confirm." >&2
      exit 2
    fi

    [[ -n "$STORE_CLI" ]] || { echo "nexus-store-cli not found" >&2; exit 1; }
    args=(--json)
    [[ "$DRY_RUN" == true ]] && args+=(--dry-run)
    args+=(install apt "$pkg")
    exec "$STORE_CLI" "${args[@]}"
    ;;

  launch)
    [[ $# -ge 1 ]] || { echo "launch requires a file path" >&2; exit 2; }
    TARGET_FILE="$1"
    if [[ "$CONFIRM_ACTION" == false ]]; then
      echo "Refusing to launch $TARGET_FILE without explicit user --confirm." >&2
      exit 2
    fi
    [[ -f "$TARGET_FILE" ]] || { echo "File not found: $TARGET_FILE" >&2; exit 1; }
    lower="${TARGET_FILE,,}"
    if [[ "$lower" == *.exe || "$lower" == *.msi ]]; then
      command -v wine >/dev/null 2>&1 || { echo "Wine runtime is not installed." >&2; exit 1; }
      prefix_dir="$PREFIX_BASE/default"
      if [[ "$DRY_RUN" == true ]]; then
        printf '{"ok":true,"dryRun":true,"runtime":"wine","prefix":"%s","file":"%s"}\n' "$prefix_dir" "$TARGET_FILE"
        exit 0
      fi
      mkdir -p -m 0700 "$prefix_dir"
      export WINEPREFIX="$prefix_dir"
      if [[ "$lower" == *.msi ]]; then
        exec wine msiexec /i "$TARGET_FILE"
      else
        exec wine "$TARGET_FILE"
      fi
    elif [[ "$lower" == *.apk ]]; then
      command -v waydroid >/dev/null 2>&1 || { echo "Waydroid runtime is not installed." >&2; exit 1; }
      if [[ "$DRY_RUN" == true ]]; then
        printf '{"ok":true,"dryRun":true,"runtime":"waydroid","file":"%s"}\n' "$TARGET_FILE"
        exit 0
      fi
      exec waydroid app install "$TARGET_FILE"
    elif [[ "$lower" == *.appimage ]]; then
      if [[ "$DRY_RUN" == true ]]; then
        printf '{"ok":true,"dryRun":true,"runtime":"appimage","file":"%s"}\n' "$TARGET_FILE"
        exit 0
      fi
      [[ -x "$TARGET_FILE" ]] || { echo "AppImage is not marked executable; set +x only after verifying source trust." >&2; exit 2; }
      exec "$TARGET_FILE"
    else
      echo "Refusing to launch unsupported or non-launchable file format." >&2
      exit 2
    fi
    ;;

  *)
    usage >&2
    exit 2
    ;;
esac
