# Quantum Learning Studio Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an offline-first Quantum learning app with beginner lessons, practice, saved progress, a local guide, and a single-qubit simulator.

**Architecture:** Split pure qubit math and course content from the app UI. Register the UI through NEXUS's existing app registry and catalogue, with browser-local progress and no remote or native service calls.

**Tech Stack:** Existing vanilla JavaScript, HTML, CSS, Node.js built-in assert/vm for checks; no new packages.

**Spec:** docs/superpowers/specs/2026-11-24-quantum-learning-studio-design.md

## Global Constraints

- This milestone is a browser prototype, not a native app or bootable OS.
- No external runtime dependencies, network calls, tracking, accounts, or API secrets.
- Never execute learner-provided code or render learner text as HTML.
- Guide content is local and must not be described as a connected generative AI service.
- Persist only versioned lesson IDs and XP in local storage; degrade clearly if storage fails.
- Keep initial content to beginner quantum concepts, Spanish and French vocabulary, and Python fundamentals.
- Preserve existing launcher, app registry, Store semantics, theme, keyboard support, and reduced-motion behavior.

## Review Focus

- Measurement at probability boundaries and invalid random inputs: test basis states and random values 0 and 1.
- Floating-point drift after repeated gates: test normalized state after a repeated gate sequence.
- Malformed or unavailable local storage: test fallback and a visible non-crashing status.
- Repeated lesson completion: test XP cannot be earned twice for one lesson.
- Learner text containing HTML-like strings: test it is inserted as text and not interpreted.

---

### Task 1: Single-qubit engine

**Files:**
- Create: apps/quantum-engine.js
- Create: scripts/check-quantum.js
- Modify: scripts/check-foundation.sh

**Interfaces:**
- window.NexusQuantumEngine.createState() returns a fresh normalized { alpha: { re, im }, beta: { re, im }, gates: [] } state at |0⟩.
- applyGate(state, gate) returns a new state for H, X, or Z; unknown gates throw RangeError.
- probabilities(state) returns { zero, one }, normalized to sum to 1.
- measure(state, randomValue) returns { outcome: 0 | 1, state: collapsedState }; randomValue must be finite in [0, 1].
- Tests load the engine with Node vm and use the real exported functions.

- [ ] Step 1: Add failing assertions for reset, H probabilities, H-H, X, Z, deterministic measurement, boundaries, invalid inputs, and normalization.
- [ ] Step 2: Run node scripts/check-quantum.js; confirm it fails because the engine file/API is missing.
- [ ] Step 3: Implement only the complex-amplitude operations and validation required by the tests.
- [ ] Step 4: Re-run the focused check and confirm all engine assertions pass.
- [ ] Step 5: Add the new check to scripts/check-foundation.sh.

### Task 2: Local curriculum and lesson state

**Files:**
- Create: apps/quantum-content.js
- Modify: scripts/check-quantum.js

**Interfaces:**
- window.NexusQuantumContent exposes immutable course data and pure helpers for validating quiz answers and calculating completion state.
- Initial tracks: Quantum Basics (qubit and superposition), Spanish Basics, French Basics, and Python Basics.
- Lesson completion awards 10 XP once per lesson. The stored schema is { version: 1, completedLessonIds: string[], xp: number }.

- [ ] Step 1: Add failing tests for each required track, answer normalization, XP award once, unknown lesson IDs, and malformed persisted state.
- [ ] Step 2: Run node scripts/check-quantum.js; confirm expected failures.
- [ ] Step 3: Implement the local content and pure progress helpers.
- [ ] Step 4: Re-run the focused check and confirm the curriculum assertions pass.

### Task 3: Quantum app, guide, and catalogue integration

**Files:**
- Create: apps/quantum.js
- Modify: apps/store-catalog.js
- Modify: index.html
- Modify: scripts/check-quantum.js

**Interfaces:**
- Register app ID quantum, display name Quantum, with render() and mount(root).
- Render Learn, Quantum Lab, Languages, Coding, and Guide sections; use safe text nodes for user answers and guide queries.
- Guide lookup uses local course explanations and hints. Empty/unmatched queries show a calm prompt to choose a lesson; no fake AI response or remote request.
- Simulator controls add H/X/Z, reset, and measure, update probabilities/amplitudes, and show the gate history.
- Lesson answers show correctness and an explanation; completion persists locally and does not award XP more than once.
- Add catalog entry id quantum, launchTarget quantum, installMode system, installedByDefault true.
- Load engine and content before apps/quantum.js; load app module before app.js.

- [ ] Step 1: Add failing checks for app registration, required views, safe text handling hooks, simulator controls, catalog metadata, and script load order.
- [ ] Step 2: Run node scripts/check-quantum.js; confirm the UI/catalog checks fail before implementation.
- [ ] Step 3: Implement the registered app and catalogue wiring, with event listeners scoped to the mounted root.
- [ ] Step 4: Re-run node scripts/check-quantum.js and confirm all integration assertions pass.
- [ ] Step 5: Run bash scripts/check-foundation.sh to verify existing app and foundation checks.

### Task 4: Responsive Quantum presentation and documentation

**Files:**
- Modify: styles.css
- Modify: README.md
- Modify: docs/PREINSTALLED_APPS.md

- [ ] Step 1: Add the Quantum layout, lesson cards, progress, simulator, guide, focus states, small-screen layout, and reduced-motion rules using existing CSS tokens.
- [ ] Step 2: Update docs to describe the working browser-prototype features and explicitly state the offline guide is not connected AI; do not claim a native or complete OS app.
- [ ] Step 3: Run bash scripts/check-foundation.sh and inspect the changed-file diff.
- [ ] Step 4: Record that no interactive browser validation was possible if the browser security boundary still blocks the local preview; do not claim the UI was manually tested.
