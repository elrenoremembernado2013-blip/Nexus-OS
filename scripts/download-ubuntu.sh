#!/usr/bin/env bash
# Download Ubuntu 26.04.1 Server media and verify its signed official checksum manifest.
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT_DIR="${NEXUS_DOWNLOAD_DIR:-$ROOT_DIR/build/downloads}"
BASE_URL="${UBUNTU_RELEASE_BASE_URL:-https://releases.ubuntu.com/26.04}"
ISO_NAME="${UBUNTU_ISO_NAME:-ubuntu-26.04.1-live-server-amd64.iso}"
KEYRING="${UBUNTU_ARCHIVE_KEYRING:-/usr/share/keyrings/ubuntu-archive-keyring.gpg}"

usage() {
  cat <<'USAGE'
Usage: bash scripts/download-ubuntu.sh [--output-dir DIR] [--base-url HTTPS_URL]
                                      [--iso-name NAME] [--keyring FILE]

Downloads the Ubuntu Server ISO, SHA256SUMS, and SHA256SUMS.gpg, verifies the
manifest signature using the supplied Ubuntu archive keyring, then compares the
ISO SHA-256 with the signed manifest. No checksum is embedded in this script.

Environment overrides: NEXUS_DOWNLOAD_DIR, UBUNTU_RELEASE_BASE_URL,
UBUNTU_ISO_NAME, UBUNTU_ARCHIVE_KEYRING.
USAGE
}

while (($#)); do
  case "$1" in
    --output-dir) (($# >= 2)) || { usage >&2; exit 2; }; OUTPUT_DIR="$2"; shift 2 ;;
    --base-url) (($# >= 2)) || { usage >&2; exit 2; }; BASE_URL="$2"; shift 2 ;;
    --iso-name) (($# >= 2)) || { usage >&2; exit 2; }; ISO_NAME="$2"; shift 2 ;;
    --keyring) (($# >= 2)) || { usage >&2; exit 2; }; KEYRING="$2"; shift 2 ;;
    --help|-h) usage; exit 0 ;;
    *) printf 'Unknown option: %s\n' "$1" >&2; usage >&2; exit 2 ;;
  esac
done

case "$BASE_URL" in https://*) ;; *) echo 'Release base URL must use HTTPS.' >&2; exit 2 ;; esac
[[ "$ISO_NAME" =~ ^[A-Za-z0-9._-]+$ ]] || { echo 'ISO name must be a simple filename.' >&2; exit 2; }
for command in curl gpgv sha256sum awk; do
  command -v "$command" >/dev/null 2>&1 || { printf 'Missing required command: %s\n' "$command" >&2; exit 1; }
done
[[ -r "$KEYRING" ]] || { printf 'Ubuntu archive keyring not readable: %s\nInstall ubuntu-keyring or pass --keyring.\n' "$KEYRING" >&2; exit 1; }
mkdir -p -- "$OUTPUT_DIR"
OUTPUT_DIR="$(cd -- "$OUTPUT_DIR" && pwd)"
CHECKSUMS="$OUTPUT_DIR/SHA256SUMS"
SIGNATURE="$OUTPUT_DIR/SHA256SUMS.gpg"
ISO_PATH="$OUTPUT_DIR/$ISO_NAME"
TMP_CHECKSUMS="$(mktemp "$OUTPUT_DIR/.nexus-checksum.XXXXXX")"
trap 'rm -f -- "$TMP_CHECKSUMS"' EXIT

curl --proto '=https' --tlsv1.2 --fail --location --silent --show-error "$BASE_URL/SHA256SUMS" -o "$CHECKSUMS"
curl --proto '=https' --tlsv1.2 --fail --location --silent --show-error "$BASE_URL/SHA256SUMS.gpg" -o "$SIGNATURE"
echo 'Verifying the signed Ubuntu checksum manifest…'
gpgv --keyring "$KEYRING" "$SIGNATURE" "$CHECKSUMS"

if [[ ! -s "$ISO_PATH" ]]; then
  echo "Downloading $ISO_NAME (large file)…"
  curl --proto '=https' --tlsv1.2 --fail --location --show-error "$BASE_URL/$ISO_NAME" -o "$ISO_PATH.part"
  mv -- "$ISO_PATH.part" "$ISO_PATH"
fi

EXPECTED="$(awk -v file="$ISO_NAME" '$2 == file || $2 == "*" file { print $1; exit }' "$CHECKSUMS")"
[[ "$EXPECTED" =~ ^[[:xdigit:]]{64}$ ]] || { printf 'No valid SHA-256 entry for %s in signed manifest.\n' "$ISO_NAME" >&2; exit 1; }
ACTUAL="$(sha256sum -- "$ISO_PATH" | awk '{print $1}')"
if [[ "${ACTUAL,,}" != "${EXPECTED,,}" ]]; then
  printf 'SHA-256 mismatch for %s\nExpected: %s\nActual:   %s\n' "$ISO_NAME" "$EXPECTED" "$ACTUAL" >&2
  exit 1
fi
printf 'Verified: %s\nSHA-256: %s\n' "$ISO_PATH" "$ACTUAL"
echo 'The manifest signature and ISO checksum both verified.'
