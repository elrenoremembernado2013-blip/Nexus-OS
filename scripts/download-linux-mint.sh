#!/usr/bin/env bash
# Download Linux Mint 22.3 (Xfce or Cinnamon) and verify its signed checksum manifest and ISO.
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT_DIR="${NEXUS_DOWNLOAD_DIR:-$ROOT_DIR/build/downloads}"
BASE_URL="${LINUX_MINT_RELEASE_BASE_URL:-https://mirrors.kernel.org/linuxmint/stable/22.3}"
MIRROR_URLS_ENV="${LINUX_MINT_MIRROR_URLS:-}"
EDITION="${LINUX_MINT_EDITION:-xfce}"
ISO_NAME="${LINUX_MINT_ISO_NAME:-}"
SIGNING_FINGERPRINT="27DEB15644C6B3CF3BD7D291300F846BA25BAE09"
GPG_KEYSERVER="${NEXUS_GPG_KEYSERVER:-hkps://keys.openpgp.org}"
KEYRING_PATH="${NEXUS_MINT_KEYRING:-}"

usage() {
  cat <<'USAGE'
Usage: bash scripts/download-linux-mint.sh
       bash scripts/download-linux-mint.sh --edition cinnamon|xfce [--output-dir DIR]

Downloads a pinned Linux Mint 22.3 ISO and its SHA-256 manifest from a Linux
Mint mirror. Checks the manifest signature against the published Linux Mint ISO
signing-key fingerprint, then verifies the ISO digest.

Environment overrides: NEXUS_DOWNLOAD_DIR, LINUX_MINT_RELEASE_BASE_URL,
LINUX_MINT_MIRROR_URLS, LINUX_MINT_EDITION, LINUX_MINT_ISO_NAME,
NEXUS_GPG_KEYSERVER, NEXUS_MINT_KEYRING.
USAGE
}

while (($#)); do
  case "$1" in
    --edition) (($# >= 2)) || { usage >&2; exit 2; }; EDITION="$2"; shift 2 ;;
    --output-dir) (($# >= 2)) || { usage >&2; exit 2; }; OUTPUT_DIR="$2"; shift 2 ;;
    --help|-h) usage; exit 0 ;;
    *) printf 'Unknown option: %s\n' "$1" >&2; usage >&2; exit 2 ;;
  esac
done

case "$EDITION" in
  xfce|cinnamon) ;;
  *) printf 'Unsupported --edition: %s (expected xfce or cinnamon)\n' "$EDITION" >&2; exit 2 ;;
esac
if [[ -z "$ISO_NAME" ]]; then
  ISO_NAME="linuxmint-22.3-${EDITION}-64bit.iso"
fi

case "$BASE_URL" in https://*) ;; *) echo 'Release base URL must use HTTPS.' >&2; exit 2 ;; esac
MIRRORS=("${BASE_URL%/}")
if [[ -n "$MIRROR_URLS_ENV" ]]; then
  IFS=', ' read -r -a extra_mirrors <<< "$MIRROR_URLS_ENV"
  for m in "${extra_mirrors[@]}"; do
    [[ -n "$m" ]] || continue
    case "$m" in
      https://*)
        m="${m%/}"
        [[ "$m" == "${BASE_URL%/}" ]] || MIRRORS+=("$m")
        ;;
      *) echo 'Every fallback mirror URL must use HTTPS.' >&2; exit 2 ;;
    esac
  done
fi
case "$GPG_KEYSERVER" in hkps://*|hkp://*) ;; *) echo 'GPG keyserver URL must use hkps:// or hkp://.' >&2; exit 2 ;; esac
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

curl_fetch_small() {
  local rel_path="$1" dest="$2" mirror
  for mirror in "${MIRRORS[@]}"; do
    if curl --http1.1 --proto '=https' --tlsv1.2 --fail --location --silent --show-error \
      --connect-timeout 30 --speed-limit 2048 --speed-time 30 \
      --retry 8 --retry-delay 5 --retry-all-errors \
      "${mirror}/${rel_path}" -o "${dest}.part"; then
      mv -- "${dest}.part" "$dest"
      return 0
    fi
    rm -f -- "${dest}.part"
    echo "Mirror ${mirror} failed for ${rel_path}; trying next if available..." >&2
  done
  return 1
}

curl_fetch_small "sha256sum.txt" "$CHECKSUMS" || { echo 'Failed to download sha256sum.txt from all mirrors.' >&2; exit 1; }
curl_fetch_small "sha256sum.txt.gpg" "$SIGNATURE" || { echo 'Failed to download sha256sum.txt.gpg from all mirrors.' >&2; exit 1; }
if [[ -n "$KEYRING_PATH" ]]; then
  [[ -r "$KEYRING_PATH" ]] || { printf 'Mint signing keyring not readable: %s\n' "$KEYRING_PATH" >&2; exit 1; }
  gpg --batch --homedir "$GPG_HOME" --import "$KEYRING_PATH"
else
  key_imported=false
  for ks in "$GPG_KEYSERVER" hkps://keyserver.ubuntu.com hkps://pgp.mit.edu; do
    if gpg --batch --homedir "$GPG_HOME" --keyserver "$ks" --recv-keys "$SIGNING_FINGERPRINT"; then
      key_imported=true
      break
    fi
    echo "Keyserver $ks failed; trying next..." >&2
    sleep 2
  done
  [[ "$key_imported" == true ]] || { echo 'Failed to fetch Mint signing key from all keyservers.' >&2; exit 1; }
fi
IMPORTED_FINGERPRINT="$(gpg --batch --homedir "$GPG_HOME" --with-colons --fingerprint "$SIGNING_FINGERPRINT" | awk -F: '$1 == "fpr" { print $10; exit }')"
[[ "$IMPORTED_FINGERPRINT" == "$SIGNING_FINGERPRINT" ]] || { echo 'Linux Mint signing-key fingerprint mismatch.' >&2; exit 1; }
gpg --batch --homedir "$GPG_HOME" --status-fd 1 --verify "$SIGNATURE" "$CHECKSUMS" >"$STATUS_FILE"
grep -Fq "[GNUPG:] VALIDSIG $SIGNING_FINGERPRINT " "$STATUS_FILE" || { echo 'Checksum manifest was not signed by the expected Linux Mint key.' >&2; exit 1; }
echo 'Verified Linux Mint checksum-manifest signature.'

download_iso_once() {
  local mirror
  echo "Downloading $ISO_NAME (large file)…"
  for mirror in "${MIRRORS[@]}"; do
    if curl --http1.1 --proto '=https' --tlsv1.2 --fail --location --show-error \
      --connect-timeout 30 --speed-limit 10240 --speed-time 60 \
      --retry 8 --retry-delay 5 --retry-all-errors \
      --continue-at - "${mirror}/${ISO_NAME}" -o "$ISO_PATH.part"; then
      mv -- "$ISO_PATH.part" "$ISO_PATH"
      return 0
    fi
    # Guard against HTTP 416 / corrupted partial files by resetting .part once
    echo "Resumable download from ${mirror} failed; retrying clean transfer without stale .part..." >&2
    rm -f -- "$ISO_PATH.part"
    if curl --http1.1 --proto '=https' --tlsv1.2 --fail --location --show-error \
      --connect-timeout 30 --speed-limit 10240 --speed-time 60 \
      --retry 4 --retry-delay 5 --retry-all-errors \
      --continue-at - "${mirror}/${ISO_NAME}" -o "$ISO_PATH.part"; then
      mv -- "$ISO_PATH.part" "$ISO_PATH"
      return 0
    fi
    rm -f -- "$ISO_PATH.part"
  done
  return 1
}

compute_sha256() {
  local f="$1"
  if [[ "$HASH_COMMAND" == sha256sum ]]; then
    "$HASH_COMMAND" -- "$f" | awk '{print $1}'
  else
    "$HASH_COMMAND" -a 256 "$f" | awk '{print $1}'
  fi
}

EXPECTED="$(awk -v file="$ISO_NAME" '$2 == file || $2 == "*" file { print $1; exit }' "$CHECKSUMS")"
[[ "$EXPECTED" =~ ^[[:xdigit:]]{64}$ ]] || { printf 'No valid SHA-256 entry for %s in the signed manifest.\n' "$ISO_NAME" >&2; exit 1; }
EXPECTED_NORMALIZED="$(printf '%s' "$EXPECTED" | tr '[:upper:]' '[:lower:]')"

if [[ ! -s "$ISO_PATH" ]]; then
  download_iso_once || { echo "Failed to download $ISO_NAME from all mirrors." >&2; exit 1; }
fi

ACTUAL="$(compute_sha256 "$ISO_PATH")"
ACTUAL_NORMALIZED="$(printf '%s' "$ACTUAL" | tr '[:upper:]' '[:lower:]')"
if [[ "$ACTUAL_NORMALIZED" != "$EXPECTED_NORMALIZED" ]]; then
  printf 'SHA-256 mismatch for %s\nExpected: %s\nActual:   %s\n' "$ISO_NAME" "$EXPECTED" "$ACTUAL" >&2
  rm -f -- "$ISO_PATH"
  exit 1
fi
printf 'Verified: %s\nSHA-256: %s\n' "$ISO_PATH" "$ACTUAL"
echo 'The manifest signature and ISO checksum both verified.'
