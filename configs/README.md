# Configuration files

This directory will contain reviewed, version-controlled NEXUS Buildroot configuration and related build inputs.

Planned structure (not yet present):

- `nexus_x86_64_defconfig` — minimal x86-64 Buildroot configuration.
- `rootfs_overlay/` — NEXUS-specific filesystem additions.
- `linux.config` — kernel configuration fragment, if needed.
- `package/` — project-specific Buildroot packages, only when upstream packages are insufficient.

Do not add a guessed or hand-written defconfig and label it buildable. Generate the initial defconfig from the pinned Buildroot tree, build it, and commit the exact tested configuration alongside its Buildroot version and build instructions.

Keep credentials, signing keys, private certificates, and machine-specific secrets out of this directory and out of Git.
