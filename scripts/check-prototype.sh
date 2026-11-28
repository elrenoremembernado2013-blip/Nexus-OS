#!/usr/bin/env bash
# Validate browser-prototype JavaScript syntax, unit tests, and local asset/script references.
set -euo pipefail
ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

command -v node >/dev/null 2>&1 || {
  echo "Node.js is required for prototype checks (node --check)." >&2
  exit 1
}

JS_FILES=()
while IFS= read -r file; do
  JS_FILES+=("$file")
done < <(find app.js apps -type f -name '*.js' -print | sort)
[[ ${#JS_FILES[@]} -gt 0 ]] || { echo "No JavaScript files found." >&2; exit 1; }
for file in "${JS_FILES[@]}"; do
  node --check "$file"
  printf 'PASS JavaScript syntax: %s\n' "$file"
done

node scripts/check-app-registry.js
node scripts/check-window-manager.js
node scripts/check-native-services.js
node scripts/check-calculator.js
node scripts/check-browser.js
node scripts/check-store-catalog.js
node scripts/check-store-native.js
node scripts/check-files-helpers.js
node scripts/check-calendar.js
node scripts/check-quantum.js
node scripts/check-settings-sections.js
node scripts/check-security-privacy.js
node scripts/check-gaming.js
node scripts/check-personalisation.js
node scripts/check-installer.js
node scripts/check-system-monitor.js
node scripts/check-terminal-preview.js
node scripts/check-desktop-integration.js
node scripts/check-phase18-integration.js
node scripts/check-phase19-hardware-release.js
node scripts/check-phase20-performance.js
node scripts/check-phase21-ecosystem.js
node scripts/check-phase22-compatibility.js
node scripts/check-phase23-validation.js
node scripts/check-phase24-reliability.js
node scripts/check-phase24-1-iso-pipeline.js
bash scripts/check-native-launchers.sh

python3 - <<'PY'
from pathlib import Path
import re
root = Path(".")
html = (root / "index.html").read_text(encoding="utf-8")
scripts = re.findall(r'<script[^>]+src="([^"]+)"', html)
styles = re.findall(r'<link[^>]+href="([^"]+)"', html)
for rel in scripts + styles:
    if rel.startswith(("http://", "https://", "//")):
        continue
    if not (root / rel).is_file():
        raise SystemExit(f"Missing local page resource: {rel}")

# Ensure every apps/*.js module is actually loaded by index.html.
loaded_scripts = set(scripts)
for app_file in sorted((root / "apps").glob("*.js")):
    rel = app_file.as_posix()
    if rel not in loaded_scripts:
        raise SystemExit(f"App module not loaded by index.html: {rel}")

# Verify every icon referenced by index.html and store-catalog.js exists on disk.
catalog = (root / "apps/store-catalog.js").read_text(encoding="utf-8")
for icon in sorted(set(re.findall(r'assets/icons/[A-Za-z0-9._-]+\.svg', html + "\n" + catalog))):
    if not (root / icon).is_file():
        raise SystemExit(f"Missing icon: {icon}")
print("PASS index.html local scripts, stylesheet, and all icon references")
PY

if grep -R -n -E '(^|[^[:alnum:]_])(eval|Function)[[:space:]]*\(' app.js apps >/dev/null 2>&1; then
  echo "Unexpected eval() or Function() usage in prototype code." >&2
  exit 1
fi
printf 'PASS no eval()/Function() execution patterns in prototype code\n'
