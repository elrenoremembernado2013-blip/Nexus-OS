#!/usr/bin/env bash
# Download Linux Mint 22.3 Xfce and verify its signed checksum manifest and ISO.
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT_DIR="${NEXUS_DOWNLOAD_DIR:-$ROOT_DIR/build/downloads}"
BASE_URL="${LINUX_MINT_RELEASE_BASE_URL:-https://mirrors.kernel.org/linuxmint/stable/22.3}"
ISO_NAME="${LINUX_MINT_ISO_NAME:-linuxmint-22.3-xfce-64bit.iso}"
SIGNING_FINGERPRINT="27DEB15644C6B3CF3BD7D291300F846BA25BAE09"

usage() {
  cat <<'USAGE'
Usage: bash scripts/download-linux-mint.sh
       bash scripts/download-linux-mint.sh --output-dir DIR

Downloads the pinned Linux Mint 22.3 Xfce ISO and its SHA-256 manifest from a
Linux Mint mirror. It checks the manifest signature against the published Linux
Mint ISO signing-key fingerprint, then verifies the ISO digest.

Environment overrides: NEXUS_DOWNLOAD_DIR, LINUX_MINT_RELEASE_BASE_URL,
LINUX_MINT_ISO_NAME.
USAGE
}

while (($#)); do
  case "$1" in
    --output-dir) (($# >= 2)) || { usage >&2; exit 2; }; OUTPUT_DIR="$2"; shift 2 ;;
    --help|-h) usage; exit 0 ;;
    *) printf 'Unknown option: %s\n' "$1" >&2; usage >&2; exit 2 ;;
  esac
done

case "$BASE_URL" in https://*) ;; *) echo 'Release base URL must use HTTPS.' >&2; exit 2 ;; esac
[[ "$ISO_NAME" =~ ^[A-Za-z0-9._-]+$ ]] || { echo 'ISO name must be a simple filename.' >&2; exit 2; }
for command in curl gpg awk tr; do
  command -v "$command" >/dev/null 2>&1 || { printf 'Missing required command: %s\n' "$command" >&2; exit 1; }
done
if command -v sha256sum >/dev/null 2>&1; then
  HASH_COMMAND=sha256sum
elif command -v shasum >/dev/null 2>&1; then
  HASH_COMMAND=shasum
else
  echo 'Missing SHA-256 utility (install coreutils or use macOS shasum).' >&2
  exit 1
fi

mkdir -p -- "$OUTPUT_DIR"
OUTPUT_DIR="$(cd -- "$OUTPUT_DIR" && pwd)"
CHECKSUMS="$OUTPUT_DIR/sha256sum.txt"
SIGNATURE="$OUTPUT_DIR/sha256sum.txt.gpg"
ISO_PATH="$OUTPUT_DIR/$ISO_NAME"
GPG_HOME="$(mktemp -d "${TMPDIR:-/tmp}/nexus-mint-gpg.XXXXXX")"
STATUS_FILE="$GPG_HOME/verification.status"
trap 'rm -rf -- "$GPG_HOME"' EXIT

curl --proto '=https' --tlsv1.2 --fail --location --silent --show-error "$BASE_URL/sha256sum.txt" -o "$CHECKSUMS"
curl --proto '=https' --tlsv1.2 --fail --location --silent --show-error "$BASE_URL/sha256sum.txt.gpg" -o "$SIGNATURE"
gpg --batch --homedir "$GPG_HOME" --keyserver hkp://keys.openpgp.org:80 --recv-keys "$SIGNING_FINGERPRINT"
IMPORTED_FINGERPRINT="$(gpg --batch --homedir "$GPG_HOME" --with-colons --fingerprint "$SIGNING_FINGERPRINT" | awk -F: '$1 == "fpr" { print $10; exit }')"
[[ "$IMPORTED_FINGERPRINT" == "$SIGNING_FINGERPRINT" ]] || { echo 'Linux Mint signing-key fingerprint mismatch.' >&2; exit 1; }
gpg --batch --homedir "$GPG_HOME" --status-fd 1 --verify "$SIGNATURE" "$CHECKSUMS" >"$STATUS_FILE"
grep -Fq "[GNUPG:] VALIDSIG $SIGNING_FINGERPRINT " "$STATUS_FILE" || { echo 'Checksum manifest was not signed by the expected Linux Mint key.' >&2; exit 1; }
echo 'Verified Linux Mint checksum-manifest signature.'

if [[ ! -s "$ISO_PATH" ]]; then
  echo "Downloading $ISO_NAME (large file)…"
  curl --proto '=https' --tlsv1.2 --fail --location --show-error "$BASE_URL/$ISO_NAME" -o "$ISO_PATH.part"
  mv -- "$ISO_PATH.part" "$ISO_PATH"
fi

EXPECTED="$(awk -v file="$ISO_NAME" '$2 == file || $2 == "*" file { print $1; exit }' "$CHECKSUMS")"
[[ "$EXPECTED" =~ ^[[:xdigit:]]{64}$ ]] || { printf 'No valid SHA-256 entry for %s in the signed manifest.\n' "$ISO_NAME" >&2; exit 1; }
if [[ "$HASH_COMMAND" == sha256sum ]]; then
  ACTUAL="$("$HASH_COMMAND" -- "$ISO_PATH" | awk '{print $1}')"
else
  ACTUAL="$("$HASH_COMMAND" -a 256 "$ISO_PATH" | awk '{print $1}')"
fi
ACTUAL_NORMALIZED="$(printf '%s' "$ACTUAL" | tr '[:upper:]' '[:lower:]')"
EXPECTED_NORMALIZED="$(printf '%s' "$EXPECTED" | tr '[:upper:]' '[:lower:]')"
if [[ "$ACTUAL_NORMALIZED" != "$EXPECTED_NORMALIZED" ]]; then
  printf 'SHA-256 mismatch for %s\nExpected: %s\nActual:   %s\n' "$ISO_NAME" "$EXPECTED" "$ACTUAL" >&2
  exit 1
fi
printf 'Verified: %s\nSHA-256: %s\n' "$ISO_PATH" "$ACTUAL"
echo 'The manifest signature and ISO checksum both verified.'
