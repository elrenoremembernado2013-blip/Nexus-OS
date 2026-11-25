#!/usr/bin/env bash
# Lightweight static checks for foundation scripts, configuration, and prototype code.
set -euo pipefail
ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

for script in scripts/download-linux-mint.sh scripts/download-ubuntu.sh scripts/launch-qemu.sh scripts/check-foundation.sh scripts/check-prototype.sh linux/mint/apply-nexus-xfce.sh linux/mint/measure-footprint.sh linux/mint/nexus-panel-status.sh linux/mint/madoo-qualify-report.sh linux/mint/provision-nexus-guest.sh linux/mint/nexus-firstboot.sh linux/mint/nexus-store-cli.sh linux/mint/nexus-security-cli.sh linux/mint/nexus-gaming-cli.sh linux/build/check-build-prereqs.sh linux/build/build-nexus-iso.sh linux/cinnamon/apply-nexus-cinnamon.sh; do
  [[ -f "$script" ]] || { printf 'Missing required script: %s\n' "$script" >&2; exit 1; }
  bash -n "$script"
  printf 'PASS bash syntax: %s\n' "$script"
done

if command -v shellcheck >/dev/null 2>&1; then
  shellcheck scripts/download-linux-mint.sh scripts/download-ubuntu.sh scripts/launch-qemu.sh scripts/check-foundation.sh scripts/check-prototype.sh linux/mint/apply-nexus-xfce.sh linux/mint/measure-footprint.sh linux/mint/nexus-panel-status.sh linux/mint/madoo-qualify-report.sh linux/mint/provision-nexus-guest.sh linux/mint/nexus-firstboot.sh linux/mint/nexus-store-cli.sh linux/mint/nexus-security-cli.sh linux/mint/nexus-gaming-cli.sh linux/build/check-build-prereqs.sh linux/build/build-nexus-iso.sh linux/cinnamon/apply-nexus-cinnamon.sh
  printf 'PASS shellcheck lint on foundation scripts\n'
else
  printf 'INFO shellcheck not installed; skipping shell lint\n'
fi

for required in .gitignore LICENSE package.json linux/config/README.md linux/config/nexus-system.conf linux/config/mint-packages.list linux/xfce/nexus-dark.css linux/branding/README.md linux/branding/nexus-logo.svg linux/branding/nexus-firstboot.desktop linux/cinnamon/themes.json linux/cinnamon/wallpapers.json linux/cinnamon/cinnamon-base.css linux/cinnamon/gtk3-base.css docs/LINUX_FOUNDATION_SETUP.md docs/ISO_BUILD.md docs/CINNAMON_DESKTOP.md docs/NEXUS_STORE.md docs/SECURITY_AND_PRIVACY.md docs/GAMING_AND_PROTON.md docs/PERSONALISATION_AND_THEMES.md; do
  [[ -f "$required" ]] || { printf 'Missing required foundation file: %s\n' "$required" >&2; exit 1; }
done

grep -Fqx '/build/' .gitignore
grep -Fqx '*.qcow2' .gitignore
grep -Fq 'VALIDSIG' scripts/download-linux-mint.sh
grep -Fq 'sha256sum' scripts/download-linux-mint.sh
grep -Fq 'if=pflash' scripts/launch-qemu.sh
grep -Fq 'NEXUS_RAM_MB' scripts/launch-qemu.sh
grep -Fq 'NEXUS_BASE_DISTRO=linuxmint' linux/config/nexus-system.conf
grep -Fq 'NexusNativeServices' apps/native-services.js
grep -Fq 'NativeIntegrationUnavailableError' apps/native-services.js
grep -Fq 'native-services.js' index.html
grep -Fq 'NexusWindowManager' app.js
grep -Fq 'NexusNativeServices' app.js
grep -Fq -- '--dry-run' scripts/launch-qemu.sh
if grep -R -n -E '(^|[^[:alnum:]_])(eval|Function)[[:space:]]*\(' app.js apps >/dev/null 2>&1; then
  printf 'Unexpected eval() or Function() usage in executable prototype code\n' >&2
  exit 1
fi

bash scripts/launch-qemu.sh --dry-run >/dev/null
bash scripts/download-linux-mint.sh --help >/dev/null
bash scripts/download-ubuntu.sh --help >/dev/null
bash linux/mint/apply-nexus-xfce.sh --help >/dev/null
bash linux/mint/apply-nexus-xfce.sh --dry-run >/dev/null
bash linux/mint/apply-nexus-xfce.sh --dry-run --lightweight >/dev/null
bash linux/mint/apply-nexus-xfce.sh --dry-run --revert >/dev/null
bash linux/mint/measure-footprint.sh --help >/dev/null
bash linux/mint/nexus-panel-status.sh --help >/dev/null
bash linux/mint/nexus-panel-status.sh --genmon >/dev/null
bash linux/mint/nexus-panel-status.sh --plain >/dev/null
bash linux/mint/nexus-panel-status.sh --json >/dev/null
bash linux/mint/madoo-qualify-report.sh --help >/dev/null
bash linux/mint/madoo-qualify-report.sh --plain >/dev/null
bash linux/mint/madoo-qualify-report.sh --markdown >/dev/null
bash linux/mint/provision-nexus-guest.sh --help >/dev/null
bash linux/mint/provision-nexus-guest.sh --dry-run >/dev/null
bash linux/mint/provision-nexus-guest.sh --dry-run --with-gaming --with-dev --autostart-firstboot >/dev/null
bash linux/mint/nexus-firstboot.sh --help >/dev/null
bash linux/mint/nexus-firstboot.sh --dry-run --profile lightweight --theme dark --check-updates --gaming-status --mark-done >/dev/null
bash linux/build/check-build-prereqs.sh --help >/dev/null
bash linux/build/check-build-prereqs.sh >/dev/null
bash linux/build/build-nexus-iso.sh --help >/dev/null
bash linux/build/build-nexus-iso.sh --check >/dev/null
bash linux/build/build-nexus-iso.sh --dry-run --with-gaming --with-dev >/dev/null
bash linux/cinnamon/apply-nexus-cinnamon.sh --help >/dev/null
bash linux/cinnamon/apply-nexus-cinnamon.sh --dry-run --theme nebula --profile lightweight --dock-position left --workspaces 4 >/dev/null
bash linux/cinnamon/apply-nexus-cinnamon.sh --dry-run --preset-profile gaming --effect-level off --panel-size small --wallpaper-fit zoom --accent '#ffad7a' >/dev/null
bash linux/cinnamon/apply-nexus-cinnamon.sh --dry-run --revert >/dev/null
bash linux/mint/nexus-store-cli.sh --help >/dev/null
bash linux/mint/nexus-store-cli.sh sources >/dev/null
bash linux/mint/nexus-store-cli.sh --dry-run install apt gimp >/dev/null
bash linux/mint/nexus-store-cli.sh --dry-run install flatpak org.gimp.GIMP >/dev/null
bash linux/mint/nexus-store-cli.sh --dry-run remove apt gimp >/dev/null
if bash linux/mint/nexus-store-cli.sh --dry-run remove apt systemd >/dev/null 2>&1; then
  echo 'Expected nexus-store-cli.sh to refuse removing protected package systemd' >&2
  exit 1
fi
if bash linux/mint/nexus-store-cli.sh --dry-run install apt 'bad;pkg' >/dev/null 2>&1; then
  echo 'Expected nexus-store-cli.sh to reject invalid package identifier' >&2
  exit 1
fi
bash linux/mint/nexus-security-cli.sh --help >/dev/null
bash linux/mint/nexus-security-cli.sh status >/dev/null
bash linux/mint/nexus-security-cli.sh startup-list >/dev/null
bash linux/mint/nexus-security-cli.sh --dry-run firewall enable >/dev/null
bash linux/mint/nexus-security-cli.sh --dry-run flatpak-revoke org.gimp.GIMP --nofilesystem=home >/dev/null
if bash linux/mint/nexus-security-cli.sh --dry-run flatpak-revoke org.gimp.GIMP --bad-flag >/dev/null 2>&1; then
  echo 'Expected nexus-security-cli.sh to reject unsupported Flatpak override flag' >&2
  exit 1
fi
bash linux/mint/nexus-gaming-cli.sh --help >/dev/null
bash linux/mint/nexus-gaming-cli.sh status >/dev/null
bash linux/mint/nexus-gaming-cli.sh --dry-run gaming-mode enable >/dev/null
bash linux/mint/nexus-gaming-cli.sh --dry-run gaming-mode disable >/dev/null
bash linux/mint/nexus-gaming-cli.sh --dry-run steam install >/dev/null
bash linux/mint/nexus-gaming-cli.sh --dry-run steam remove >/dev/null
python3 - <<'PY'
import json
from pathlib import Path

themes = json.loads(Path("linux/cinnamon/themes.json").read_text(encoding="utf-8"))
for expected in ("midnight", "nebula", "arctic", "emerald", "solar"):
    assert expected in themes, f"Missing theme: {expected}"

wallpapers = json.loads(Path("linux/cinnamon/wallpapers.json").read_text(encoding="utf-8"))
assert len(wallpapers["wallpapers"]) >= 6
for item in wallpapers["wallpapers"]:
    assert item["photographer"] and item["sourceUrl"].startswith("https://")
    assert item["recommendedTheme"] in themes
PY
printf 'PASS expected files, Linux Mint config, dry-run CLI checks, signed-checksum, and UEFI/QEMU wiring\n'

for desktop_file in linux/branding/applications/*.desktop; do
  [[ -f "$desktop_file" ]] || { printf 'Missing desktop entry: %s\n' "$desktop_file" >&2; exit 1; }
  grep -Fq '[Desktop Entry]' "$desktop_file"
done

python3 -m py_compile linux/mint/nexus-system-bridge.py scripts/check-linux-bridge.py
python3 scripts/check-linux-bridge.py

bash scripts/check-prototype.sh
