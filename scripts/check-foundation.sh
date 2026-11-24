#!/usr/bin/env bash
# Lightweight static checks for foundation scripts, configuration, and prototype code.
set -euo pipefail
ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

for script in scripts/download-linux-mint.sh scripts/download-ubuntu.sh scripts/launch-qemu.sh scripts/check-foundation.sh scripts/check-prototype.sh; do
  [[ -f "$script" ]] || { printf 'Missing required script: %s\n' "$script" >&2; exit 1; }
  bash -n "$script"
  printf 'PASS bash syntax: %s\n' "$script"
done

if command -v shellcheck >/dev/null 2>&1; then
  shellcheck scripts/download-linux-mint.sh scripts/download-ubuntu.sh scripts/launch-qemu.sh scripts/check-foundation.sh scripts/check-prototype.sh
  printf 'PASS shellcheck lint on foundation scripts\n'
else
  printf 'INFO shellcheck not installed; skipping shell lint\n'
fi

for required in .gitignore LICENSE package.json linux/config/README.md linux/config/nexus-system.conf docs/LINUX_FOUNDATION_SETUP.md; do
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
printf 'PASS expected files, Linux Mint config, dry-run CLI checks, signed-checksum, and UEFI/QEMU wiring\n'

bash scripts/check-prototype.sh
