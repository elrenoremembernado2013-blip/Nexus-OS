# Quantum Learning Studio — Design

## Intent

Quantum is NEXUS's playful learning app. It should grow into a place where a learner can explore many subjects, including quantum computing, languages, and coding. This first milestone adds a useful, offline-capable browser prototype to the existing NEXUS desktop.

## Goals

- Add Quantum to the desktop launcher and Store as a working bundled app.
- Offer short lessons, practice questions, helpful feedback, and saved local progress.
- Include starter content for quantum concepts, Spanish and French vocabulary, and Python fundamentals.
- Include a real single-qubit state-vector lab with reset, Hadamard (H), Pauli-X, Pauli-Z, and measurement.
- Provide an offline lesson guide that can explain terms and give lesson-specific hints.
- Make learning encouraging and accessible by keyboard, with clear status messages and reduced-motion support.

## Non-goals

- This milestone is not a complete course covering every subject or language.
- It does not execute learner-written code or claim to be a general-purpose programming IDE.
- It does not connect to a generative AI model. The offline guide uses reviewed local lesson content and must identify itself as such.
- It does not add accounts, cloud sync, tracking, ads, subscriptions, or third-party runtime dependencies.
- It does not create a native Linux app, bootable NEXUS image, or Chromebook hardware integration.

## Approaches

1. Online AI-first tutor: broad and conversational, but needs a trusted backend, provider selection, privacy rules, and credentials. A public browser client must not contain API secrets.
2. Offline-first learning app (selected): curated short lessons, quizzes, progress, a lesson-aware guide, and a small real simulator. It runs within the existing static browser prototype and suits the limited Chromebook resources. Its content is narrower at first, but remains available without a network.
3. Native Linux app: could later integrate with the desktop, but NEXUS has no installable base image or app service protocol yet.

## Architecture

- apps/quantum-engine.js owns the pure single-qubit math and exposes window.NexusQuantumEngine. State is represented by normalized complex amplitudes; measurement accepts an injectable random value so outcomes are testable.
- apps/quantum-content.js owns local lesson, quiz, vocabulary, and Python practice content.
- apps/quantum.js registers the Quantum app with the existing app registry. It renders Learn, Quantum Lab, Languages, Coding, and Guide views; it uses DOM text APIs for learner input and never evaluates arbitrary code or HTML.
- apps/store-catalog.js makes Quantum a bundled, installed-by-default NEXUS app. The existing launcher and Store state remain the source of app availability.
- styles.css styles Quantum using existing NEXUS tokens and includes responsive and reduced-motion behavior.
- index.html loads the new modules before app.js.
- scripts/check-quantum.js verifies the math, content, registration, and key UI hooks without a browser dependency; the existing foundation check invokes it.

## Progress and privacy

Completed lesson IDs and earned XP are stored in browser local storage, namespaced and versioned. If storage is unavailable or malformed, the app starts with empty progress and tells the user progress could not be saved. It does not store names, contact information, or free-form questions. Guide responses are selected from local explanations and hints; no prompt is sent to a service.

## Acceptance

- The app appears in the launcher, opens, and shows the five learning areas.
- Lesson questions accept and reject answers correctly, explain the result, and award XP only once per lesson.
- Spanish and French starter lessons and Python concept exercises work without code execution.
- The qubit engine resets to |0⟩, H creates equal measurement probabilities, H followed by H restores |0⟩, X flips basis states, Z changes phase without changing probabilities, and measurement follows Born probabilities.
- The simulator displays amplitudes and probabilities and visibly records gate and measurement steps.
- Progress survives reload in the same browser profile; unavailable storage does not crash the app.
- Keyboard navigation and reduced-motion settings remain usable.
- Existing prototype checks still pass. Native AI, native Linux operation, comprehensive curriculum coverage, and Chromebook qualification remain unclaimed.

## Calls left for future work

A real conversational AI tutor needs an owner-approved provider or local model, an authenticated backend or runtime integration, privacy/retention rules, and a separate resource/security review. The offline guide is the first working version and leaves a clear boundary for that later decision.
