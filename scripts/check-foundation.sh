#!/usr/bin/env bash
# Lightweight static checks for foundation scripts, configuration, and prototype code.
set -euo pipefail
ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

for script in scripts/download-linux-mint.sh scripts/download-ubuntu.sh scripts/launch-qemu.sh scripts/check-foundation.sh scripts/check-prototype.sh linux/mint/apply-nexus-xfce.sh linux/mint/measure-footprint.sh linux/mint/nexus-panel-status.sh linux/mint/madoo-qualify-report.sh linux/mint/provision-nexus-guest.sh linux/mint/nexus-firstboot.sh linux/mint/nexus-store-cli.sh linux/mint/nexus-security-cli.sh linux/mint/nexus-gaming-cli.sh linux/installer/nexus-install-preflight.sh linux/installer/nexus-installer-launcher.sh linux/installer/nexus-disk-install.sh linux/installer/nexus-recovery.sh linux/build/check-build-prereqs.sh linux/build/validate-packages.sh linux/build/apply-iso-branding.sh linux/build/build-nexus-iso.sh linux/build/verify-nexus-iso.sh linux/build/prepare-release.sh linux/cinnamon/apply-nexus-cinnamon.sh linux/lite/apply-nexus-lite.sh linux/lite/configure-zram.sh linux/lite/memory-audit.sh linux/lite/provision-nexus-lite.sh linux/lite/build-nexus-lite-iso.sh linux/lite/nexus-lite-install.sh linux/lite/openbox/autostart linux/lite/scripts/apply-nexus-lite-lxqt.sh linux/lite/scripts/provision-nexus-lite-lxqt.sh linux/lite/scripts/build-nexus-lite-lxqt-iso.sh linux/hardware/nexus-hw-inventory.sh linux/hardware/nexus-hw-diagnostics.sh linux/hardware/nexus-hw-qualify.sh linux/hardware/nexus-browser-qualify.sh linux/security/nexus-security-audit.sh linux/test/guest-mem-probe.sh linux/test/test-zram-pressure.sh linux/test/test-installer-safety.sh linux/test/run-qemu-validation.sh linux/test/run-phase125-tests.sh linux/test/run-phase130-tests.sh linux/test/casper-test-hook.sh; do
  [[ -f "$script" ]] || { printf 'Missing required script: %s\n' "$script" >&2; exit 1; }
  bash -n "$script"
  printf 'PASS bash syntax: %s\n' "$script"
done

if command -v shellcheck >/dev/null 2>&1; then
  shellcheck scripts/download-linux-mint.sh scripts/download-ubuntu.sh scripts/launch-qemu.sh scripts/check-foundation.sh scripts/check-prototype.sh linux/mint/apply-nexus-xfce.sh linux/mint/measure-footprint.sh linux/mint/nexus-panel-status.sh linux/mint/madoo-qualify-report.sh linux/mint/provision-nexus-guest.sh linux/mint/nexus-firstboot.sh linux/mint/nexus-store-cli.sh linux/mint/nexus-security-cli.sh linux/mint/nexus-gaming-cli.sh linux/installer/nexus-install-preflight.sh linux/installer/nexus-installer-launcher.sh linux/installer/nexus-disk-install.sh linux/installer/nexus-recovery.sh linux/build/check-build-prereqs.sh linux/build/validate-packages.sh linux/build/apply-iso-branding.sh linux/build/build-nexus-iso.sh linux/build/verify-nexus-iso.sh linux/build/prepare-release.sh linux/cinnamon/apply-nexus-cinnamon.sh linux/lite/apply-nexus-lite.sh linux/lite/configure-zram.sh linux/lite/memory-audit.sh linux/lite/provision-nexus-lite.sh linux/lite/build-nexus-lite-iso.sh linux/lite/nexus-lite-install.sh linux/lite/openbox/autostart linux/lite/scripts/apply-nexus-lite-lxqt.sh linux/lite/scripts/provision-nexus-lite-lxqt.sh linux/lite/scripts/build-nexus-lite-lxqt-iso.sh linux/hardware/nexus-hw-inventory.sh linux/hardware/nexus-hw-diagnostics.sh linux/hardware/nexus-hw-qualify.sh linux/hardware/nexus-browser-qualify.sh linux/security/nexus-security-audit.sh linux/test/guest-mem-probe.sh linux/test/test-zram-pressure.sh linux/test/test-installer-safety.sh linux/test/run-qemu-validation.sh linux/test/run-phase125-tests.sh linux/test/run-phase130-tests.sh linux/test/casper-test-hook.sh
  printf 'PASS shellcheck lint on foundation scripts\n'
else
  printf 'INFO shellcheck not installed; skipping shell lint\n'
fi

for required in .gitignore LICENSE package.json linux/config/README.md linux/config/nexus-system.conf linux/config/nexus-standard-cinnamon.conf linux/config/mint-packages.list linux/config/cinnamon-packages.list linux/xfce/nexus-dark.css linux/branding/README.md linux/branding/nexus-logo.svg linux/branding/nexus-firstboot.desktop linux/cinnamon/themes.json linux/cinnamon/wallpapers.json linux/cinnamon/cinnamon-base.css linux/cinnamon/gtk3-base.css linux/lite/nexus-lite.conf linux/lite/nexus-lite-lxqt.conf linux/lite/lite-packages.list linux/lite/manifests/lite-openbox-packages.list linux/lite/manifests/lite-lxqt-packages.list linux/lite/profiles/lite-512.conf linux/lite/profiles/lite-768.conf linux/lite/profiles/lite-1g.conf linux/lite/profiles/lite-2g.conf linux/lite/profiles/lite-4g.conf linux/lite/openbox/rc.xml linux/lite/openbox/menu.xml linux/lite/openbox/tint2rc linux/lite/lxqt/openbox-rc.xml linux/lite/lxqt/lxqt.conf linux/lite/lxqt/panel.conf linux/lite/lxqt/session.conf linux/lite/lxqt/qterminal.ini linux/lite/lxqt/theme/nexus-dark/lxqt-panel.qss linux/lite/lxqt/wallpaper-nexus-obsidian.svg linux/hardware/hw-compatibility-db.json docs/LINUX_FOUNDATION_SETUP.md docs/ISO_BUILD.md docs/CINNAMON_DESKTOP.md docs/NEXUS_STORE.md docs/SECURITY_AND_PRIVACY.md docs/GAMING_AND_PROTON.md docs/PERSONALISATION_AND_THEMES.md docs/INSTALLER_ARCHITECTURE.md docs/RECOVERY_AND_BOOT.md docs/RELEASE_ENGINEERING.md docs/HARDWARE_COMPATIBILITY.md docs/HARDWARE_TESTING_GUIDE.md docs/RELEASE_DASHBOARD.md docs/NEXUS_LITE.md docs/STANDARD_VS_LITE_EDITIONS.md; do
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
bash linux/build/validate-packages.sh >/dev/null
bash linux/build/apply-iso-branding.sh --dry-run >/dev/null
bash linux/build/build-nexus-iso.sh --help >/dev/null
bash linux/build/build-nexus-iso.sh --check >/dev/null
bash linux/build/build-nexus-iso.sh --dry-run --with-gaming --with-dev >/dev/null
bash linux/build/verify-nexus-iso.sh --dry-run >/dev/null
bash linux/build/prepare-release.sh --dry-run --stage alpha >/dev/null
bash linux/build/prepare-release.sh --dry-run --stage beta >/dev/null
bash linux/build/prepare-release.sh --dry-run --stage rc >/dev/null
bash linux/build/prepare-release.sh --dry-run --stage testing >/dev/null
bash linux/build/validate-packages.sh linux/config/cinnamon-packages.list >/dev/null
bash linux/build/validate-packages.sh linux/lite/lite-packages.list >/dev/null
bash linux/build/validate-packages.sh linux/lite/manifests/lite-openbox-packages.list >/dev/null
bash linux/build/validate-packages.sh linux/lite/manifests/lite-lxqt-packages.list >/dev/null
bash linux/build/build-nexus-iso.sh --edition cinnamon --dry-run >/dev/null
bash linux/build/build-nexus-iso.sh --edition xfce --dry-run >/dev/null
bash linux/build/build-nexus-iso.sh --edition lite --dry-run >/dev/null
bash linux/build/build-nexus-iso.sh --edition lite-lxqt --dry-run >/dev/null
bash linux/build/verify-nexus-iso.sh --edition cinnamon --dry-run >/dev/null
bash linux/build/verify-nexus-iso.sh --edition lite --dry-run >/dev/null
bash linux/build/verify-nexus-iso.sh --edition lite-lxqt --dry-run >/dev/null
bash linux/lite/apply-nexus-lite.sh --dry-run --profile lite-512 >/dev/null
bash linux/lite/apply-nexus-lite.sh --dry-run --profile lite-1g >/dev/null
bash linux/lite/apply-nexus-lite.sh --dry-run --profile standard-2g >/dev/null
bash linux/lite/apply-nexus-lite.sh --dry-run --revert >/dev/null
bash linux/lite/scripts/apply-nexus-lite-lxqt.sh --dry-run --profile lite-1g >/dev/null
bash linux/lite/scripts/apply-nexus-lite-lxqt.sh --dry-run --revert >/dev/null
bash linux/lite/configure-zram.sh status >/dev/null
bash linux/lite/configure-zram.sh --dry-run enable >/dev/null
bash linux/lite/memory-audit.sh --json >/dev/null
bash linux/lite/provision-nexus-lite.sh --dry-run --skip-ufw --purge-bloat >/dev/null
bash linux/lite/scripts/provision-nexus-lite-lxqt.sh --dry-run --skip-ufw --purge-bloat >/dev/null
bash linux/lite/build-nexus-lite-iso.sh --dry-run >/dev/null
bash linux/lite/scripts/build-nexus-lite-lxqt-iso.sh --dry-run >/dev/null
bash linux/lite/nexus-lite-install.sh --dry-run >/dev/null
bash linux/hardware/nexus-hw-inventory.sh --json >/dev/null
bash linux/hardware/nexus-hw-inventory.sh --json | python3 -c 'import json,sys; d=json.load(sys.stdin); assert d["schema_version"]==2 and d["privacy_redacted"] is True and "storage_controllers" in d and "input_devices" in d and "codecs" in d["audio"] and "shim_sb_status" in d["secure_boot_chain"]'
bash linux/hardware/nexus-hw-inventory.sh --markdown >/dev/null
bash linux/hardware/nexus-hw-diagnostics.sh --json | python3 -c 'import json,sys; d=json.load(sys.stdin); assert d["privacy_audit"]["passed"] is True and d["privacy_audit"]["auto_upload"] is False and "service_states" in d'
bash linux/hardware/nexus-hw-diagnostics.sh --contribute-template | python3 -c 'import json,sys; d=json.load(sys.stdin); assert d["schema_version"]==2 and d["auto_upload"] is False and d["human_review_required"] is True and "compatibility_status" in d and "untested_components" in d and "evidence_references" in d'
bash linux/hardware/nexus-hw-qualify.sh --stage a >/dev/null
bash linux/hardware/nexus-hw-qualify.sh --run-test suspend --dry-run >/dev/null
if bash linux/hardware/nexus-hw-qualify.sh --run-test suspend >/dev/null 2>&1; then
  printf 'FAIL nexus-hw-qualify.sh must refuse Stage B suspend without --confirm-test suspend\n' >&2
  exit 1
fi
bash linux/hardware/nexus-browser-qualify.sh --dry-run >/dev/null
if bash linux/hardware/nexus-browser-qualify.sh >/dev/null 2>&1; then
  printf 'FAIL nexus-browser-qualify.sh must refuse launch without --confirm\n' >&2
  exit 1
fi
python3 linux/test/nexus-browser-bench.py >/dev/null
bash linux/installer/nexus-install-preflight.sh --summary >/dev/null
bash linux/security/nexus-security-audit.sh --json >/dev/null
bash linux/security/nexus-security-audit.sh --repo-only --repo . --strict >/dev/null
bash linux/installer/nexus-disk-install.sh --disk /dev/vda --dry-run >/dev/null
bash linux/installer/nexus-disk-install.sh --disk /dev/vda --efi-part /dev/vda1 --root-part /dev/vda2 --dry-run >/dev/null
bash linux/installer/nexus-disk-install.sh --disk /dev/vda --efi-part /dev/vda1 --root-part /dev/vda3 --keep-efi --dry-run >/dev/null
bash linux/installer/nexus-disk-install.sh --disk /dev/vda --luks --dry-run >/dev/null
if bash linux/installer/nexus-disk-install.sh --disk /dev/vda >/dev/null 2>&1; then
  printf 'FAIL nexus-disk-install.sh must refuse execution without --yes-erase-disk\n' >&2
  exit 1
fi
if grep -R -n 'org\.nexus\.test\.0' linux/mint linux/cinnamon linux/lite linux/xfce linux/installer linux/hardware >/dev/null 2>&1; then
  printf 'SECURITY FAIL: Test channel org.nexus.test.0 referenced in production linux/ directories\n' >&2
  exit 1
fi
bash linux/test/guest-mem-probe.sh --dry-run >/dev/null
bash linux/test/test-zram-pressure.sh --dry-run >/dev/null
bash linux/test/run-qemu-validation.sh --dry-run >/dev/null
bash linux/test/run-qemu-validation.sh --edition lite-lxqt --install-test --reliability --dry-run >/dev/null
bash linux/test/run-phase125-tests.sh --dry-run >/dev/null
bash linux/test/run-phase130-tests.sh --dry-run >/dev/null
python3 linux/test/qemu-graphical-runner.py --help | grep -Fq 'dualboot'

# Phase 12 invariant checks: Edition isolation, Lite Openbox/LXQt sync & safety, Openbox XML, and --revert hygiene
python3 - <<'PY'
import json
import xml.etree.ElementTree as ET
from pathlib import Path
import subprocess, tempfile, os

for xml_path in ("linux/lite/openbox/rc.xml", "linux/lite/openbox/menu.xml", "linux/lite/lxqt/openbox-rc.xml", "linux/lite/lxqt/wallpaper-nexus-obsidian.svg"):
    ET.parse(xml_path)

json.loads(Path("linux/hardware/hw-compatibility-db.json").read_text(encoding="utf-8"))

assert Path("linux/lite/lite-packages.list").read_text(encoding="utf-8").splitlines()[3:] == Path("linux/lite/manifests/lite-openbox-packages.list").read_text(encoding="utf-8").splitlines()[3:], "lite-openbox-packages.list drifted from lite-packages.list"

lite_lines = Path("linux/lite/lite-packages.list").read_text(encoding="utf-8").splitlines()
core_desktop = [l.split(":", 1)[1].strip() for l in lite_lines if l and not l.startswith("#") and l.split(":", 1)[0] in ("core", "desktop", "nexus")]
for forbidden in ("cinnamon", "steam", "steam-installer", "picom", "firefox", "falkon"):
    assert forbidden not in core_desktop, f"Forbidden default Lite package: {forbidden}"
for required in ("ufw", "unattended-upgrades", "network-manager", "zram-tools", "openbox", "tint2", "pcmanfm", "lxterminal"):
    assert required in core_desktop, f"Missing required Lite package: {required}"

lxqt_lines = Path("linux/lite/manifests/lite-lxqt-packages.list").read_text(encoding="utf-8").splitlines()
lxqt_pkgs = [l.split(":", 1)[1].strip() for l in lxqt_lines if l and not l.startswith("#") and l.split(":", 1)[0] in ("core", "desktop", "nexus")]
for forbidden in ("cinnamon", "sddm", "connman", "snapd", "steam", "firefox", "falkon", "libreoffice"):
    assert forbidden not in lxqt_pkgs, f"Forbidden default Lite LXQt package: {forbidden}"
for required in ("ufw", "unattended-upgrades", "network-manager", "zram-tools", "openbox", "lxqt-panel", "lxqt-session", "pcmanfm-qt", "qterminal", "featherpad", "qps"):
    assert required in lxqt_pkgs, f"Missing required Lite LXQt package: {required}"

cin_plan = subprocess.check_output(["bash", "linux/build/build-nexus-iso.sh", "--edition", "cinnamon", "--dry-run"], text=True)
xfce_plan = subprocess.check_output(["bash", "linux/build/build-nexus-iso.sh", "--edition", "xfce", "--dry-run"], text=True)
lite_plan = subprocess.check_output(["bash", "linux/build/build-nexus-iso.sh", "--edition", "lite", "--dry-run"], text=True)
lxqt_plan = subprocess.check_output(["bash", "linux/build/build-nexus-iso.sh", "--edition", "lite-lxqt", "--dry-run"], text=True)
assert "nexus-os-22.3-cinnamon-amd64.iso" in cin_plan and "work-cinnamon" in cin_plan
assert "nexus-os-22.3-xfce-amd64.iso" in xfce_plan and "work-xfce" in xfce_plan
assert "nexus-os-22.3-lite-amd64.iso" in lite_plan and "work-lite" in lite_plan
assert "nexus-os-22.3-lite-lxqt-amd64.iso" in lxqt_plan and "work-lite-lxqt" in lxqt_plan

with tempfile.TemporaryDirectory() as td:
    env = dict(os.environ, XDG_CONFIG_HOME=td)
    subprocess.run(["bash", "linux/lite/apply-nexus-lite.sh", "--profile", "lite-1g"], env=env, check=True, stdout=subprocess.DEVNULL)
    assert (Path(td) / "openbox/rc.xml").is_file()
    assert (Path(td) / "openbox/menu.xml").is_file()
    assert "<number>4</number>" in (Path(td) / "openbox/rc.xml").read_text(encoding="utf-8")
    assert "profile=lite-1g" in (Path(td) / "nexus-os/lite-profile").read_text(encoding="utf-8")
    subprocess.run(["bash", "linux/lite/apply-nexus-lite.sh", "--revert"], env=env, check=True, stdout=subprocess.DEVNULL)
    assert not (Path(td) / "openbox/rc.xml").exists()
    assert not (Path(td) / "openbox/menu.xml").exists()
    assert not (Path(td) / "tint2/tint2rc").exists()

    subprocess.run(["bash", "linux/lite/scripts/apply-nexus-lite-lxqt.sh", "--profile", "lite-1g"], env=env, check=True, stdout=subprocess.DEVNULL)
    assert (Path(td) / "lxqt/panel.conf").is_file()
    assert (Path(td) / "openbox/lxqt-openbox-rc.xml").is_file()
    assert "<number>4</number>" in (Path(td) / "openbox/lxqt-openbox-rc.xml").read_text(encoding="utf-8")
    subprocess.run(["bash", "linux/lite/scripts/apply-nexus-lite-lxqt.sh", "--revert"], env=env, check=True, stdout=subprocess.DEVNULL)
    assert not (Path(td) / "lxqt/panel.conf").exists()
    assert not (Path(td) / "openbox/lxqt-openbox-rc.xml").exists()
PY
if bash linux/build/prepare-release.sh --dry-run --stage stable >/dev/null 2>&1; then
  echo 'Expected prepare-release.sh to refuse stable stage without --vm-verified' >&2
  exit 1
fi
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
bash linux/installer/nexus-install-preflight.sh --summary >/dev/null
bash linux/installer/nexus-install-preflight.sh --json | python3 -c 'import json,sys; d=json.load(sys.stdin); assert "dual_boot_detection" in d and "secure_boot_status" in d'
bash linux/installer/nexus-installer-launcher.sh --check >/dev/null
bash linux/installer/nexus-installer-launcher.sh --dry-run >/dev/null
bash linux/installer/nexus-recovery.sh --diagnose --json --redacted >/dev/null
bash linux/test/test-installer-safety.sh >/dev/null
bash linux/mint/nexus-firstboot.sh --dry-run --theme-preset nebula --security-summary >/dev/null
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

python3 -m py_compile linux/mint/nexus-system-bridge.py scripts/check-linux-bridge.py linux/test/nexus-guest-test.py linux/test/qemu-graphical-runner.py linux/test/nexus-browser-bench.py linux/lite/scripts/nexus-lite-compare.py
python3 scripts/check-linux-bridge.py

bash scripts/check-prototype.sh
