#!/usr/bin/env bash
# Validate browser-prototype JavaScript syntax and local asset/script references.
set -euo pipefail
ROOT_DIR="$(cd -- "$(dirname -- "\${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

command -v node >/dev/null 2>&1 || {
  echo "Node.js is required for prototype checks (node --check)." >&2
  exit 1
}

mapfile -t JS_FILES < <(find app.js apps -type f -name '*.js' -print | sort)
(("\${#JS_FILES[@]}" > 0)) || { echo "No JavaScript files found." >&2; exit 1; }
for file in "\${JS_FILES[@]}"; do
  node --check "$file"
  printf 'PASS JavaScript syntax: %s\n' "$file"
done

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
for icon in re.findall(r'assets/icons/[A-Za-z0-9._-]+\.svg', html):
    if not (root / icon).is_file():
        raise SystemExit(f"Missing icon: {icon}")
print("PASS index.html local script, stylesheet, and icon references")
PY

if grep -R -n -E '(^|[^[:alnum:]_])(eval|Function)[[:space:]]*\(' app.js apps >/dev/null 2>&1; then
  echo "Unexpected eval() or Function() usage in prototype code." >&2
  exit 1
fi
printf 'PASS no eval()/Function() execution patterns in prototype code\n'
