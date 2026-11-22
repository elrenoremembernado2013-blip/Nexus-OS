#!/usr/bin/env bash
# Lightweight static checks for the foundation helper scripts and tracked config.
set -euo pipefail
ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

for script in scripts/download-ubuntu.sh scripts/launch-qemu.sh scripts/check-foundation.sh; do
  [[ -f "$script" ]] || { printf 'Missing required script: %s\n' "$script" >&2; exit 1; }
  bash -n "$script"
  printf 'PASS bash syntax: %s\n' "$script"
done

for required in .gitignore linux/config/README.md linux/config/nexus-system.conf docs/LINUX_FOUNDATION_SETUP.md; do
  [[ -f "$required" ]] || { printf 'Missing required foundation file: %s\n' "$required" >&2; exit 1; }
done

grep -Fqx '/build/' .gitignore
grep -Fqx '*.qcow2' .gitignore
grep -Fq 'gpgv --keyring' scripts/download-ubuntu.sh
grep -Fq 'sha256sum' scripts/download-ubuntu.sh
grep -Fq 'if=pflash' scripts/launch-qemu.sh
grep -Fq 'NEXUS_RAM_MB' scripts/launch-qemu.sh
grep -Fq 'NexusNativeServices' apps/native-services.js
grep -Fq 'NativeIntegrationUnavailableError' apps/native-services.js
grep -Fq 'native-services.js' index.html
if grep -R -n -E '(^|[^[:alnum:]_])(eval|Function)[[:space:]]*\(' app.js apps >/dev/null 2>&1; then
  printf 'Unexpected eval() or Function() usage in executable prototype code\n' >&2
  exit 1
fi
printf 'PASS expected files, generated-output exclusions, signed-checksum, and UEFI/QEMU wiring\n'
