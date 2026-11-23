# Copilot Instructions — NEXUS OS

You are the implementation engineer for NEXUS OS. Work directly in this repository, preserve existing features and visual identity, and make changes in small tested increments.

## Project goal
Build a lightweight, secure, customizable desktop environment designed to run smoothly on older computers. Current files are a browser prototype; do not misrepresent it as a bootable operating system or as native hardware control.

## Linux-native desktop direction

The first native desktop prototype baseline is KWin on Wayland with the KDE Plasma shell and Qt Quick/QML, on the Ubuntu foundation. Treat this as a prototype choice pending QEMU and memory validation, not a delivered or tested feature. Start with a Plasma theme/layout and one focused QML widget; do not build a custom compositor. Keep the existing browser prototype clearly identified as a prototype and visual reference. See `docs/PLATFORM_ARCHITECTURE.md` and `docs/LINUX_FOUNDATION.md`.

## Design
- Premium, cinematic, minimalist dark UI with glass panels, warm copper/orange accents with optional cool theme variants, real non-AI photographic wallpapers, and careful typography.
- Keep UI uncluttered and responsive.
- Add a lightweight mode that reduces blur, shadows, animation and unnecessary work.
- Respect prefers-reduced-motion and keyboard navigation.

## Engineering
- Inspect the repository and current implementation before modifying it.
- Keep app code modular, readable, and maintainable. Avoid unnecessary dependencies.
- Make interactions genuinely functional within prototype limitations; never label simulated behavior as real.
- No arbitrary shell execution in the browser terminal. Never use eval(), Function(), or dynamic code execution to interpret user input.
- Validate URLs before opening external pages; prefer HTTPS and use safe window.open options.
- Store only appropriate user preferences locally and provide clear reset/erase actions.
- Avoid collecting personal data. Explain any external resource usage.
- Preserve existing work. Avoid destructive rewrites unless necessary and explain why.
- Add tests or manual verification steps for meaningful changes. Run available checks and report what was and was not tested.

## Current next tasks
1. Review existing desktop/window code and correct bugs first.
2. Review and test the updated window manager: focus/z-order, drag, resize, minimise, maximise/restore, edge snap; ensure snap/maximise states can restore cleanly. Check for syntax errors and pointer edge cases.
3. Keep the calculator's hand-written arithmetic parser free of eval()/Function(); add regression tests if its logic changes.
4. Improve keyboard accessibility, escape-to-close panels, and reduced motion.
5. Keep notifications integrated in Control Centre.
6. Do not claim system-level RAM, CPU, storage, network, power, security scans, or Steam integration unless connected to a native backend.

## Report format
After work, provide: summary, changed files, tests/checks run, known limitations, and suggested next task. Commit only focused, descriptive changes.
