# NEXUS OS — Development Roadmap

This roadmap distinguishes planned work from verified implementation. A milestone is complete only when its acceptance criteria have evidence in the repository.

## Milestone 0 — Repository and engineering baseline

- [x] Establish project README and honest status statement.
- [x] Document proposed architecture and roadmap.
- [x] Add a read-only project diagnostic helper.
- [ ] Add a pinned Buildroot source tree/reference and reproducible build instructions.
- [ ] Add contribution and release procedures.

**Exit criteria:** a clean checkout can identify required tools and follow documented, reproducible build steps.

## Milestone 1 — Minimal bootable Linux image

- [ ] Select and pin Buildroot release/commit.
- [ ] Add a reviewed NEXUS defconfig and any required rootfs overlay.
- [ ] Build a minimal x86-64 image in a documented environment.
- [ ] Boot the image in QEMU and save the exact command and result.
- [ ] Record image size, boot time, kernel version, and hardware profile.

**Exit criteria:** a fresh build boots to a shell in QEMU with no undocumented manual steps.

## Milestone 2 — Hardware validation

- [ ] Test on a representative low-end x86-64 machine.
- [ ] Verify storage, networking, audio, keyboard, touchpad, display, and suspend where applicable.
- [ ] Record driver/firmware gaps.
- [ ] Measure idle memory using a defined baseline and repeatable method.

**Exit criteria:** compatibility table contains actual test evidence, not assumptions.

## Milestone 3 — Graphical foundation

- [ ] Select a lightweight Wayland compositor.
- [ ] Start a graphical session automatically and safely.
- [ ] Add input, display, audio, and session management.
- [ ] Verify shell/compositor restart behaviour and accessibility fallbacks.

**Exit criteria:** graphical session starts reliably on QEMU and at least one physical test device.

## Milestone 4 — NEXUS desktop and ORBIT

- [ ] Implement desktop shell frame and window/session integration.
- [ ] Build ORBIT search, app grid, categories, pins, and keyboard navigation.
- [ ] Add Control Centre and notification presentation.
- [ ] Add wallpaper gallery with source/attribution metadata.
- [ ] Add theme, reduced-motion, and high-contrast settings.

**Exit criteria:** core interactions work with keyboard and pointer; UI can run with effects disabled.

## Milestone 5 — Security and maintenance

- [ ] Write a threat model.
- [ ] Review users, groups, capabilities, services, and filesystem permissions.
- [ ] Define signed update and recovery strategy.
- [ ] Add automated configuration and image checks.
- [ ] Document vulnerability reporting and release signing.

**Exit criteria:** security controls are documented and tested; update recovery is demonstrated.

## Milestone 6 — Applications and gaming

- [ ] Define optional application delivery mechanism.
- [ ] Test browser and developer-tool choices.
- [ ] Evaluate graphics APIs and driver availability.
- [ ] Test Steam compatibility on supported hardware only.
- [ ] Publish a clear compatibility matrix.

**Exit criteria:** every advertised application/game capability has reproducible test evidence.

## Performance reporting

For each test, record:
- Device/VM CPU, RAM, GPU, and storage.
- Buildroot commit, kernel version, and config hash.
- Boot-to-login time and image size.
- Idle `MemAvailable` after a documented settling period.
- Services/processes included in the measurement.
- Test command, date, and raw output.

Do not treat the 128 MB idle-memory aspiration as achieved until measurements support it.
