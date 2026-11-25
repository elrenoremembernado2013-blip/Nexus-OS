#!/usr/bin/env bash
# Generate a NEXUS OS release manifest and release notes from verified build
# artifacts. Enforces strict promotion gates so untested images are never marked stable.
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/../.." && pwd)"
BUILD_INFO="${NEXUS_BUILD_INFO:-$REPO_ROOT/build/iso/out/build-info.json}"
OUT_MANIFEST="${NEXUS_RELEASE_MANIFEST:-$REPO_ROOT/build/iso/out/nexus-release-manifest.json}"

STAGE="development"
VERSION="0.3.0"
VM_VERIFIED=false
DRY_RUN=false

usage() {
  cat <<'USAGE'
Usage: bash linux/build/prepare-release.sh [OPTIONS]

Prepares release metadata (nexus-release-manifest.json) from a built ISO's
build-info.json. Never marks an image 'stable' without --vm-verified.

Options:
  --stage STAGE     Release stage: development | testing | stable (default: development)
  --version VER     NEXUS OS release version (default: 0.3.0)
  --vm-verified     Confirm live VM boot + Ubiquity installation test passed
  --build-info PATH Override build-info.json input path
  --out PATH        Override output release manifest path
  --dry-run         Validate stage gates without requiring build-info.json
  --help, -h        Show this help message
USAGE
}

while (($#)); do
  case "$1" in
    --stage) [[ $# -ge 2 ]] || { echo '--stage requires a value' >&2; exit 2; }; STAGE="$2"; shift 2 ;;
    --version) [[ $# -ge 2 ]] || { echo '--version requires a value' >&2; exit 2; }; VERSION="$2"; shift 2 ;;
    --vm-verified) VM_VERIFIED=true; shift ;;
    --build-info) [[ $# -ge 2 ]] || { echo '--build-info requires a path' >&2; exit 2; }; BUILD_INFO="$2"; shift 2 ;;
    --out) [[ $# -ge 2 ]] || { echo '--out requires a path' >&2; exit 2; }; OUT_MANIFEST="$2"; shift 2 ;;
    --dry-run) DRY_RUN=true; shift ;;
    --help|-h) usage; exit 0 ;;
    *) printf 'Unknown option: %s\n' "$1" >&2; usage >&2; exit 2 ;;
  esac
done

case "$STAGE" in
  development|testing|stable) ;;
  *) printf 'Invalid --stage: %s\n' "$STAGE" >&2; exit 2 ;;
esac

if [[ "$STAGE" == "stable" && "$VM_VERIFIED" == false ]]; then
  echo 'Refusing to mark an image stable without --vm-verified confirmation of live boot and disk installation.' >&2
  exit 1
fi

if [[ "$DRY_RUN" == true ]]; then
  printf '[dry-run] Release stage=%s version=%s vm_verified=%s -> %s\n' "$STAGE" "$VERSION" "$VM_VERIFIED" "$OUT_MANIFEST"
  exit 0
fi

[[ -r "$BUILD_INFO" ]] || { printf 'Missing build-info.json: %s (build and verify the ISO first)\n' "$BUILD_INFO" >&2; exit 1; }

python3 - "$BUILD_INFO" "$OUT_MANIFEST" "$STAGE" "$VERSION" "$VM_VERIFIED" <<'PY'
import datetime
import json
from pathlib import Path
import sys

info = json.load(open(sys.argv[1], encoding="utf-8"))
out_path = Path(sys.argv[2])
stage = sys.argv[3]
version = sys.argv[4]
vm_verified = sys.argv[5] == "true"

manifest = {
    "product": "NEXUS OS",
    "version": version,
    "stage": stage,
    "release_date_utc": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    "foundation": f"{info.get('base_distro')} {info.get('base_version')} ({info.get('edition')})",
    "arch": info.get("arch"),
    "build_id": info.get("output_iso_sha256", "")[:12],
    "output_iso": info.get("output_iso"),
    "output_iso_sha256": info.get("output_iso_sha256"),
    "vm_verified": vm_verified,
}
out_path.parent.mkdir(parents=True, exist_ok=True)
out_path.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
print(f"Wrote release manifest ({stage}): {out_path}")
PY
