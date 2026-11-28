#!/usr/bin/env bash
# Generate a NEXUS OS release manifest, SHA256SUMS, provenance metadata, and
# dependency/security audit record from verified build artifacts.
# Enforces strict promotion gates and never fabricates cryptographic signatures.
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/../.." && pwd)"
BUILD_INFO="${NEXUS_BUILD_INFO:-$REPO_ROOT/build/iso/out/build-info.json}"
OUT_MANIFEST="${NEXUS_RELEASE_MANIFEST:-$REPO_ROOT/build/iso/out/nexus-release-manifest.json}"
OUT_CHECKSUMS="${NEXUS_RELEASE_CHECKSUMS:-$REPO_ROOT/build/iso/out/SHA256SUMS}"
SECURITY_AUDIT="$REPO_ROOT/linux/security/nexus-security-audit.sh"
VALIDATE_PKGS="$SCRIPT_DIR/validate-packages.sh"

STAGE="development"
VERSION="0.3.0"
EDITION=""
VM_VERIFIED=false
DRY_RUN=false
SKIP_AUDIT=false

usage() {
  cat <<'USAGE'
Usage: bash linux/build/prepare-release.sh [OPTIONS]

Prepares release metadata (nexus-release-manifest.json), SHA256SUMS, and build
provenance from a built ISO's build-info.json. Never marks an image 'stable'
without --vm-verified, and never invents GPG signatures when no key was used.

Options:
  --stage STAGE        Release stage: development | alpha | beta | rc | testing | stable (default: development)
  --version VER        NEXUS OS release version (default: 0.3.0)
  --edition NAME       Optional edition label: cinnamon | xfce | lite | lite-lxqt
  --vm-verified        Confirm live VM boot + disk installation test passed
  --build-info PATH    Override build-info.json input path
  --out PATH           Override output release manifest path
  --checksums-out PATH Override output SHA256SUMS path
  --skip-audit         Skip repository security/package audit (not recommended)
  --dry-run            Validate stage gates & audits without requiring build-info.json
  --help, -h           Show this help message
USAGE
}

while (($#)); do
  case "$1" in
    --stage) [[ $# -ge 2 ]] || { echo '--stage requires a value' >&2; exit 2; }; STAGE="$2"; shift 2 ;;
    --version) [[ $# -ge 2 ]] || { echo '--version requires a value' >&2; exit 2; }; VERSION="$2"; shift 2 ;;
    --edition) [[ $# -ge 2 ]] || { echo '--edition requires a value' >&2; exit 2; }; EDITION="$2"; shift 2 ;;
    --vm-verified) VM_VERIFIED=true; shift ;;
    --build-info) [[ $# -ge 2 ]] || { echo '--build-info requires a path' >&2; exit 2; }; BUILD_INFO="$2"; shift 2 ;;
    --out) [[ $# -ge 2 ]] || { echo '--out requires a path' >&2; exit 2; }; OUT_MANIFEST="$2"; shift 2 ;;
    --checksums-out) [[ $# -ge 2 ]] || { echo '--checksums-out requires a path' >&2; exit 2; }; OUT_CHECKSUMS="$2"; shift 2 ;;
    --skip-audit) SKIP_AUDIT=true; shift ;;
    --dry-run) DRY_RUN=true; shift ;;
    --help|-h) usage; exit 0 ;;
    *) printf 'Unknown option: %s\n' "$1" >&2; usage >&2; exit 2 ;;
  esac
done

case "$STAGE" in
  development|alpha|beta|rc|testing|stable) ;;
  *) printf 'Invalid --stage: %s\n' "$STAGE" >&2; exit 2 ;;
esac

if [[ "$STAGE" == "stable" && "$VM_VERIFIED" == false ]]; then
  echo 'Refusing to mark an image stable without --vm-verified confirmation of live boot and disk installation.' >&2
  exit 1
fi

audit_passed=false
if [[ "$SKIP_AUDIT" == false ]]; then
  if [[ -x "$SECURITY_AUDIT" ]]; then
    bash "$SECURITY_AUDIT" --repo-only --repo "$REPO_ROOT" --strict >/dev/null
  fi
  if [[ -x "$VALIDATE_PKGS" ]]; then
    bash "$VALIDATE_PKGS" "$REPO_ROOT/linux/config/mint-packages.list" >/dev/null
    bash "$VALIDATE_PKGS" "$REPO_ROOT/linux/config/cinnamon-packages.list" >/dev/null
    bash "$VALIDATE_PKGS" "$REPO_ROOT/linux/lite/manifests/lite-openbox-packages.list" >/dev/null
    bash "$VALIDATE_PKGS" "$REPO_ROOT/linux/lite/manifests/lite-lxqt-packages.list" >/dev/null
  fi
  audit_passed=true
fi

if [[ "$DRY_RUN" == true ]]; then
  printf '[dry-run] Release stage=%s version=%s edition=%s vm_verified=%s audit_passed=%s -> %s (checksums: %s, signature: unsigned)\n' \
    "$STAGE" "$VERSION" "${EDITION:-auto}" "$VM_VERIFIED" "$audit_passed" "$OUT_MANIFEST" "$OUT_CHECKSUMS"
  exit 0
fi

[[ -r "$BUILD_INFO" ]] || { printf 'Missing build-info.json: %s (build and verify the ISO first)\n' "$BUILD_INFO" >&2; exit 1; }

python3 - "$BUILD_INFO" "$OUT_MANIFEST" "$OUT_CHECKSUMS" "$STAGE" "$VERSION" "$EDITION" "$VM_VERIFIED" "$audit_passed" "$REPO_ROOT" <<'PY'
import datetime
import hashlib
import json
from pathlib import Path
import subprocess
import sys

info_path = Path(sys.argv[1])
info = json.loads(info_path.read_text(encoding="utf-8"))
out_path = Path(sys.argv[2])
checksums_path = Path(sys.argv[3])
stage = sys.argv[4]
version = sys.argv[5]
edition_override = sys.argv[6].strip()
vm_verified = sys.argv[7] == "true"
audit_passed = sys.argv[8] == "true"
repo_root = Path(sys.argv[9])

edition = edition_override or str(info.get("edition") or "unknown")

def git_val(args):
    try:
        res = subprocess.run(["git", "-C", str(repo_root), *args], capture_output=True, text=True, timeout=4)
        if res.returncode == 0:
            return res.stdout.strip()
    except Exception:
        pass
    return "unknown"

pkg_lists = {}
for rel in (
    "linux/config/mint-packages.list",
    "linux/config/cinnamon-packages.list",
    "linux/lite/manifests/lite-openbox-packages.list",
    "linux/lite/manifests/lite-lxqt-packages.list",
):
    p = repo_root / rel
    if p.is_file():
        pkg_lists[rel] = hashlib.sha256(p.read_bytes()).hexdigest()

iso_rel = info.get("output_iso")
iso_sha = info.get("output_iso_sha256")
iso_candidate = None
if iso_rel:
    cand = Path(iso_rel)
    if not cand.is_absolute():
        cand = info_path.parent / cand
    if cand.is_file():
        iso_candidate = cand
        iso_sha = hashlib.sha256(cand.read_bytes()).hexdigest()

checksum_lines = []
if iso_candidate and iso_sha:
    checksum_lines.append(f"{iso_sha}  {iso_candidate.name}")
elif iso_rel and iso_sha:
    checksum_lines.append(f"{iso_sha}  {Path(iso_rel).name}")
checksum_lines.append(f"{hashlib.sha256(info_path.read_bytes()).hexdigest()}  {info_path.name}")

checksums_path.parent.mkdir(parents=True, exist_ok=True)
checksums_path.write_text("\n".join(checksum_lines) + "\n", encoding="utf-8")

sig_asc = checksums_path.with_suffix(checksums_path.suffix + ".asc")
signature_status = "detached_asc_present_unverified" if sig_asc.is_file() else "unsigned"

manifest = {
    "schema_version": 2,
    "product": "NEXUS OS",
    "version": version,
    "edition": edition,
    "stage": stage,
    "release_date_utc": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    "foundation": f"{info.get('base_distro')} {info.get('base_version')} ({edition})",
    "arch": info.get("arch"),
    "build_id": (iso_sha or "")[:12],
    "output_iso": info.get("output_iso"),
    "output_iso_sha256": iso_sha,
    "checksums_file": checksums_path.name,
    "signature_status": signature_status,
    "vm_verified": vm_verified,
    "provenance": {
        "git_commit": git_val(["rev-parse", "HEAD"]),
        "git_branch": git_val(["rev-parse", "--abbrev-ref", "HEAD"]),
        "security_and_package_audit_passed": audit_passed,
        "package_manifest_sha256": pkg_lists,
    },
}
out_path.parent.mkdir(parents=True, exist_ok=True)
out_path.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
print(f"Wrote release manifest ({stage}, signature={signature_status}): {out_path}")
print(f"Wrote SHA256SUMS: {checksums_path}")
PY
