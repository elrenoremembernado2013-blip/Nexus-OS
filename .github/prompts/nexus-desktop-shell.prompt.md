# Copilot Task — NEXUS OS desktop shell and window manager

Work on the `nexus-linux-foundation` branch. Read `.github/copilot-instructions.md` first.

## Scope
This prompt covers the browser prototype only. The Linux-native prototype direction is documented in `docs/PLATFORM_ARCHITECTURE.md`; do not treat browser changes here as native desktop integration.

## Context
The current browser prototype has a warm copper/orange accent, smoky charcoal glass surfaces, a photographic mountain wallpaper, a translucent dock, and floating application windows. Preserve this visual direction and existing apps.

## Task
1. Inspect `app.js`, `styles.css`, and `index.html` before editing.
2. Run a JavaScript syntax check and fix any parse errors.
3. Test and correct the window manager:
   - pointer drag without selecting title text
   - focus/z-index ordering
   - resize behaviour
   - minimise, restore, close
   - maximise and restore original geometry
   - left/right edge snapping and restoring from snapped state
   - responsive viewport changes
4. Ensure Escape closes open panels and does not unexpectedly discard unsaved note content.
5. Make the dock show which apps are open/minimised; clicking a minimised app should restore its window.
6. Keep notifications accessible from inside Control Centre, not a separate floating notification panel.
7. Persist theme accent, blur, reduced-motion and lightweight preferences safely.
8. Keep the prototype honest: no fake system telemetry, shell access, native Steam claims, or OS-level controls.
9. Add or update tests where practical. If no test framework exists, provide reproducible manual test steps.

## Constraints
- Do not use `eval()`, `Function()`, or dynamic code execution.
- Do not add dependencies without explaining why.
- Preserve the existing design and features.
- Make focused commits on this branch only. Do not merge into main.

## Report
Summarise changed files, commits, checks run and their results, known limitations, and the next recommended task.
