# NEXUS OS Release Engineering & Verification Guide

## 1. Release Stages & Promotion Gates

1. **`development`**: Automated CI checks pass (`check-foundation.sh`, `check-prototype.sh`, `nexus-security-audit.sh --strict`). Not VM-verified.
2. **`testing` / `alpha` / `beta` / `rc`**: ISO built with `sudo bash linux/build/build-nexus-iso.sh --edition <edition>`, verified with `bash linux/build/verify-nexus-iso.sh --edition <edition>`, and packaged with `bash linux/build/prepare-release.sh`.
3. **`stable`**: **Strictly gated** (`prepare-release.sh --stage stable --vm-verified`). Promotion is blocked unless live VM boot, installation, reboot, and post-install checks pass.

---

## 2. Checksums, Manifest & Build Provenance

Generate `nexus-release-manifest.json` (with Git commit/branch provenance and package list SHA-256 digests) and `SHA256SUMS`:

```sh
bash linux/build/prepare-release.sh \
  --stage beta \
  --version 0.3.0 \
  --edition xfce \
  --build-info build/iso/out/build-info.json
```

If no maintainer GPG signing key has been invoked, `prepare-release.sh` explicitly records `"signature_status": "unsigned"` — never treat an unsigned build as signed.

---

## 3. GPG Signing Workflow (Maintainer Offline Key)

Sign release checksums only on a trusted maintainer machine holding the release signing key (never embed private keys in CI or the repository):

```sh
cd build/iso/out
gpg --armor --detach-sign --output SHA256SUMS.asc SHA256SUMS
gpg --armor --export <KEY_FINGERPRINT> > NEXUS-OS-RELEASE-KEY.asc
```

---

## 4. User Release Verification Instructions

Users downloading a release should verify both the GPG signature (when `SHA256SUMS.asc` is published) and the ISO SHA-256 digest before writing installation media:

```sh
gpg --import NEXUS-OS-RELEASE-KEY.asc
gpg --verify SHA256SUMS.asc SHA256SUMS
sha256sum -c SHA256SUMS
```

Write to a USB drive using Linux Mint's **USB Image Writer** (`mintstick -m iso`) or `dd` after confirming the target device with `lsblk`:

```sh
sudo dd if=nexus-os-22.3-xfce-amd64.iso of=/dev/sdX bs=4M status=progress oflag=sync
```

---

## 5. Dependency & Security Auditing

Before tagging or publishing a release:

```sh
bash linux/security/nexus-security-audit.sh --repo-only --repo . --strict
bash linux/build/validate-packages.sh linux/config/mint-packages.list
bash linux/build/validate-packages.sh linux/config/cinnamon-packages.list
bash linux/build/validate-packages.sh linux/lite/manifests/lite-openbox-packages.list
bash linux/build/validate-packages.sh linux/lite/manifests/lite-lxqt-packages.list
```

---

## 6. Release Checklist

- [ ] `npm run check:prototype` and `npm test` pass (`scripts/check-foundation.sh` + ShellCheck + `desktop-file-validate`)
- [ ] `bash linux/test/test-installer-safety.sh` passes
- [ ] `bash linux/security/nexus-security-audit.sh --repo-only --repo . --strict` passes with `0` failures
- [ ] `iso-and-qemu-validation.yml` matrix passes across `cinnamon`, `xfce`, `lite-lxqt`, and `lite`
- [ ] `verify-nexus-iso.sh` confirms zero test-harness artifacts in initramfs/squashfs
- [ ] `prepare-release.sh` generated `SHA256SUMS` and `nexus-release-manifest.json`
- [ ] `SHA256SUMS.asc` signed by maintainer key (or release explicitly marked `unsigned` for dev/testing)
- [ ] Known issues and hardware compatibility gaps updated in `docs/RELEASE_READINESS_REPORT.md`
