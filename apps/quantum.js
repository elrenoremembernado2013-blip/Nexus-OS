(() => {
  function el(tagName, className, text) {
    const node = document.createElement(tagName);
    if (className) node.className = className;
    if (text !== undefined) node.textContent = text;
    return node;
  }

  function formatAmplitude(z) {
    const re = z.re.toFixed(3);
    const absIm = Math.abs(z.im);
    if (absIm < 0.0005) return re;
    const sign = z.im >= 0 ? "+" : "−";
    return `${re} ${sign} ${absIm.toFixed(3)}i`;
  }

  function render() {
    const views = [
      ["learn", "Learn"],
      ["lab", "Quantum Lab"],
      ["languages", "Languages"],
      ["coding", "Coding"],
      ["guide", "Guide"]
    ];
    return `
      <section class="quantum-studio" aria-labelledby="quantumTitle">
        <header class="quantum-header">
          <div>
            <p class="app-eyebrow">OFFLINE LEARNING STUDIO</p>
            <h2 class="content-title" id="quantumTitle">Quantum</h2>
            <p class="content-sub">Curated lessons, a real single-qubit lab, and an offline guide.</p>
          </div>
          <div class="quantum-stats" aria-label="Learning progress">
            <span class="quantum-pill" id="quantumXp">0 XP</span>
            <span class="quantum-pill" id="quantumCompleted">0 / 0 lessons</span>
          </div>
        </header>
        <nav class="quantum-tabs" aria-label="Quantum sections">
          ${views.map(([id, label], idx) =>
            `<button type="button" class="quantum-tab${idx === 0 ? " active" : ""}" data-quantum-view="${id}" aria-pressed="${idx === 0 ? "true" : "false"}">${label}</button>`
          ).join("")}
        </nav>
        <p class="quantum-storage-status" id="quantumStorageStatus" role="status" aria-live="polite"></p>
        <div class="quantum-body" id="quantumBody"></div>
      </section>`;
  }

  function mount(root, context = {}) {
    const engine = window.NexusQuantumEngine;
    const content = window.NexusQuantumContent;
    if (!engine || !content) throw new Error("Quantum engine or content module is missing.");

    const body = root.querySelector("#quantumBody");
    const xpBadge = root.querySelector("#quantumXp");
    const completedBadge = root.querySelector("#quantumCompleted");
    const storageStatus = root.querySelector("#quantumStorageStatus");

    const allLessons = content.getLessons();
    let activeView = "learn";
    let activeLessonId = allLessons[0]?.id || null;
    let qubitState = engine.createState();
    let lastMeasurementText = "Not measured yet.";
    let guideResult = content.queryGuide("", activeLessonId);
    let lastGuideQuery = "";
    const lessonFeedback = new Map();

    let progress = content.createEmptyProgress();
    let storageWritable = true;

    function loadSavedProgress() {
      try {
        const raw = window.localStorage.getItem(content.storageKey);
        if (raw) progress = content.parseProgress(raw);
        storageStatus.textContent = "";
        storageStatus.classList.remove("error");
      } catch (error) {
        progress = content.createEmptyProgress();
        storageStatus.textContent = `Could not load saved progress (${error.message}). Starting with 0 XP.`;
        storageStatus.classList.add("error");
      }
    }

    function saveProgress(nextProgress) {
      progress = nextProgress;
      if (!storageWritable) return;
      try {
        window.localStorage.setItem(content.storageKey, JSON.stringify(progress));
      } catch (error) {
        storageWritable = false;
        storageStatus.textContent = `Progress could not be saved locally (${error.message}).`;
        storageStatus.classList.add("error");
      }
    }

    function syncProgressHeader() {
      xpBadge.textContent = `${progress.xp} XP`;
      completedBadge.textContent = `${progress.completedLessonIds.length} / ${allLessons.length} lessons`;
    }

    function makeLessonCard(lesson) {
      const done = progress.completedLessonIds.includes(lesson.id);
      const card = el("article", "quantum-card");
      card.dataset.lessonId = lesson.id;

      const top = el("div", "quantum-card-top");
      const title = el("h3", "", lesson.title);
      const badge = el("span", `quantum-badge${done ? " done" : ""}`, done ? "Completed · +10 XP" : "+10 XP");
      top.append(title, badge);

      const summary = el("p", "quantum-summary", lesson.summary);
      card.append(top, summary);

      if (Array.isArray(lesson.vocab)) {
        const list = el("ul", "quantum-vocab");
        lesson.vocab.forEach(([term, meaning]) => {
          const item = el("li");
          item.append(el("strong", "", term), document.createTextNode(` — ${meaning}`));
          list.append(item);
        });
        card.append(list);
      }

      if (lesson.snippet) {
        const pre = el("pre", "quantum-snippet");
        pre.textContent = lesson.snippet;
        card.append(pre);
      }

      const prompt = el("p", "quantum-prompt", lesson.prompt);
      card.append(prompt);

      const form = el("form", "quantum-answer-form");
      const input = el("input", "quantum-answer-input");
      input.type = "text";
      input.placeholder = "Type your answer or pick below";
      input.setAttribute("aria-label", `Answer for ${lesson.title}`);

      const submit = el("button", "action-button", "Check");
      submit.type = "submit";
      form.append(input, submit);

      if (Array.isArray(lesson.choices)) {
        const choicesRow = el("div", "quantum-choices");
        lesson.choices.forEach(choice => {
          const choiceBtn = el("button", "quantum-choice", choice);
          choiceBtn.type = "button";
          choiceBtn.addEventListener("click", () => {
            input.value = choice;
            submitAnswer(lesson, choice);
          });
          choicesRow.append(choiceBtn);
        });
        card.append(choicesRow);
      }

      const guideBtn = el("button", "quantum-link-btn", "Ask offline guide for a hint");
      guideBtn.type = "button";
      guideBtn.addEventListener("click", () => {
        activeLessonId = lesson.id;
        guideResult = content.queryGuide("hint", lesson.id);
        setView("guide");
      });

      form.addEventListener("submit", event => {
        event.preventDefault();
        submitAnswer(lesson, input.value);
      });

      card.append(form, guideBtn);

      const savedFeedback = lessonFeedback.get(lesson.id);
      if (savedFeedback) {
        const msg = el("p", `quantum-feedback ${savedFeedback.correct ? "ok" : "bad"}`);
        if (savedFeedback.submitted) {
          msg.append(
            el("span", "quantum-submitted", `Your answer: ${savedFeedback.submitted} · `),
            document.createTextNode(savedFeedback.explanation)
          );
        } else {
          msg.textContent = savedFeedback.explanation;
        }
        card.append(msg);
      }

      return card;
    }

    function submitAnswer(lesson, rawAnswer) {
      activeLessonId = lesson.id;
      const verdict = content.checkAnswer(lesson.id, rawAnswer);
      const trimmed = String(rawAnswer || "").trim();
      lessonFeedback.set(lesson.id, {
        correct: verdict.correct,
        explanation: verdict.explanation,
        submitted: trimmed
      });
      if (verdict.correct) {
        const outcome = content.completeLesson(progress, lesson.id);
        if (outcome.awardedXp > 0) {
          saveProgress(outcome.progress);
          context.notify?.(`Completed ${lesson.title} (+${outcome.awardedXp} XP)`);
        }
      }
      renderActiveView();
    }

    function renderLearnView() {
      const intro = el("div", "quantum-section-intro");
      intro.append(
        el("h3", "", "Quantum Basics & Tracks"),
        el("p", "", "Start with single-qubit concepts or jump to Quantum Lab, Languages, or Coding.")
      );
      body.append(intro);

      const trackGrid = el("div", "quantum-track-grid");
      content.getTracks().forEach(track => {
        const trackLessons = content.getLessons(track.id);
        const doneCount = trackLessons.filter(l => progress.completedLessonIds.includes(l.id)).length;
        const tile = el("button", "quantum-track-card");
        tile.type = "button";
        tile.append(
          el("strong", "", track.title),
          el("p", "", track.summary),
          el("small", "", `${doneCount} / ${trackLessons.length} completed`)
        );
        tile.addEventListener("click", () => setView(track.view));
        trackGrid.append(tile);
      });
      body.append(trackGrid);

      const lessonGrid = el("div", "quantum-lesson-grid");
      content.getLessons("quantum").forEach(lesson => lessonGrid.append(makeLessonCard(lesson)));
      body.append(lessonGrid);
    }

    function renderLabView() {
      const probs = engine.probabilities(qubitState);
      const pct0 = (probs.zero * 100).toFixed(1);
      const pct1 = (probs.one * 100).toFixed(1);

      const intro = el("div", "quantum-section-intro");
      intro.append(
        el("h3", "", "Single-Qubit State-Vector Lab"),
        el("p", "", "Apply real single-qubit gates (H, X, Z), inspect amplitudes, and measure according to Born probabilities.")
      );

      const controls = el("div", "quantum-lab-controls");
      [
        ["H", "H (Hadamard)", () => {
          qubitState = engine.applyGate(qubitState, "H");
          lastMeasurementText = "Superposition / gate applied.";
          renderActiveView();
        }],
        ["X", "X (Pauli-X)", () => {
          qubitState = engine.applyGate(qubitState, "X");
          lastMeasurementText = "Bit-flip gate applied.";
          renderActiveView();
        }],
        ["Z", "Z (Pauli-Z)", () => {
          qubitState = engine.applyGate(qubitState, "Z");
          lastMeasurementText = "Phase-flip gate applied.";
          renderActiveView();
        }],
        ["Measure", "Measure", () => {
          const result = engine.measure(qubitState);
          qubitState = result.state;
          lastMeasurementText = `Measured ${result.outcome} (state collapsed to |${result.outcome}⟩).`;
          renderActiveView();
        }],
        ["Reset", "Reset |0⟩", () => {
          qubitState = engine.createState();
          lastMeasurementText = "Reset to |0⟩.";
          renderActiveView();
        }]
      ].forEach(([id, label, handler]) => {
        const button = el("button", "action-button quantum-gate-btn", label);
        button.type = "button";
        button.dataset.quantumGate = id;
        button.addEventListener("click", handler);
        controls.append(button);
      });

      const readout = el("div", "quantum-lab-grid");
      const ampCard = el("div", "quantum-card");
      ampCard.append(
        el("h4", "", "State amplitudes"),
        el("p", "quantum-mono", `α |0⟩ = ${formatAmplitude(qubitState.alpha)}`),
        el("p", "quantum-mono", `β |1⟩ = ${formatAmplitude(qubitState.beta)}`),
        el("p", "quantum-lab-note", lastMeasurementText)
      );

      const probCard = el("div", "quantum-card");
      probCard.append(el("h4", "", "Born probabilities"));
      [
        ["P(0)", pct0, probs.zero],
        ["P(1)", pct1, probs.one]
      ].forEach(([label, pctText, ratio]) => {
        const row = el("div", "quantum-prob-row");
        row.append(el("span", "", `${label}: ${pctText}%`));
        const track = el("div", "quantum-prob-bar");
        const fill = el("div", "quantum-prob-fill");
        fill.style.width = `${(ratio * 100).toFixed(1)}%`;
        track.append(fill);
        row.append(track);
        probCard.append(row);
      });

      readout.append(ampCard, probCard);

      const historyCard = el("div", "quantum-card");
      historyCard.append(
        el("h4", "", "Gate & measurement history"),
        el("p", "quantum-mono", qubitState.gates.length ? `|0⟩ → ${qubitState.gates.join(" → ")}` : "|0⟩ (initial state)")
      );

      body.append(intro, controls, readout, historyCard);
    }

    function renderLanguagesView() {
      const intro = el("div", "quantum-section-intro");
      intro.append(
        el("h3", "", "Starter Languages"),
        el("p", "", "Practice beginner Spanish and French vocabulary offline.")
      );
      body.append(intro);

      const grid = el("div", "quantum-lesson-grid");
      [...content.getLessons("spanish"), ...content.getLessons("french")].forEach(lesson => {
        grid.append(makeLessonCard(lesson));
      });
      body.append(grid);
    }

    function renderCodingView() {
      const intro = el("div", "quantum-section-intro");
      intro.append(
        el("h3", "", "Python Concept Practice"),
        el("p", "", "Read short Python snippets and trace their results. Code is not executed in this browser prototype.")
      );
      body.append(intro);

      const grid = el("div", "quantum-lesson-grid");
      content.getLessons("python").forEach(lesson => grid.append(makeLessonCard(lesson)));
      body.append(grid);
    }

    function renderGuideView() {
      const intro = el("div", "quantum-section-intro");
      intro.append(
        el("h3", "", "Offline Lesson Guide"),
        el("p", "", "Reviewed local explanations and hints. This offline guide is not a connected generative AI service.")
      );

      const form = el("form", "quantum-guide-form");
      const input = el("input", "quantum-guide-input");
      input.id = "quantumGuideInput";
      input.type = "search";
      input.value = lastGuideQuery;
      input.placeholder = "Ask about qubit, Hadamard, Pauli-Z, gracias, merci, Python…";
      input.setAttribute("aria-label", "Ask the offline guide");

      const askBtn = el("button", "action-button", "Look up");
      askBtn.type = "submit";
      form.append(input, askBtn);

      form.addEventListener("submit", event => {
        event.preventDefault();
        lastGuideQuery = input.value;
        guideResult = content.queryGuide(lastGuideQuery, activeLessonId);
        renderActiveView();
      });

      const responseCard = el("div", "quantum-card quantum-guide-card");
      responseCard.append(
        el("span", "integration-status", "Local offline guide · no remote AI"),
        el("h4", "", guideResult.title)
      );
      if (lastGuideQuery.trim()) {
        responseCard.append(el("p", "quantum-submitted", `Query: ${lastGuideQuery.trim()}`));
      }
      responseCard.append(el("p", "", guideResult.body));

      body.append(intro, form, responseCard);
    }

    function setView(viewId) {
      activeView = viewId;
      root.querySelectorAll("[data-quantum-view]").forEach(btn => {
        const selected = btn.dataset.quantumView === viewId;
        btn.classList.toggle("active", selected);
        btn.setAttribute("aria-pressed", String(selected));
      });
      renderActiveView();
    }

    function renderActiveView() {
      syncProgressHeader();
      body.replaceChildren();
      if (activeView === "lab") renderLabView();
      else if (activeView === "languages") renderLanguagesView();
      else if (activeView === "coding") renderCodingView();
      else if (activeView === "guide") renderGuideView();
      else renderLearnView();
    }

    root.querySelectorAll("[data-quantum-view]").forEach(button => {
      button.addEventListener("click", () => setView(button.dataset.quantumView));
    });

    loadSavedProgress();
    renderActiveView();
  }

  window.NexusAppRegistry.register({ id: "quantum", name: "Quantum", render, mount });
})();
