(() => {
  const storageKey = "nexus-quantum-progress-v1";
  const xpPerLesson = 10;

  const tracks = [
    {
      id: "quantum",
      title: "Quantum Basics",
      view: "learn",
      summary: "Qubits, superposition, phase, and measurement."
    },
    {
      id: "spanish",
      title: "Spanish Basics",
      view: "languages",
      summary: "Essential greetings, courtesy phrases, and everyday nouns."
    },
    {
      id: "french",
      title: "French Basics",
      view: "languages",
      summary: "Everyday greetings, polite expressions, and starter words."
    },
    {
      id: "python",
      title: "Python Basics",
      view: "coding",
      summary: "Variables, lists, loops, and functions without executing code."
    }
  ];

  const lessons = [
    {
      id: "q-qubit",
      trackId: "quantum",
      title: "What is a qubit?",
      summary: "Unlike a classical bit that is strictly 0 or 1, a qubit state is a complex linear combination α|0⟩ + β|1⟩ where |α|² + |β|² = 1.",
      prompt: "If a qubit is prepared in |0⟩, what is the probability of measuring 0?",
      choices: ["0", "0.5", "1"],
      acceptedAnswers: ["1", "100%", "one"],
      hint: "In the |0⟩ basis state, α = 1 and β = 0, so |α|² = 1.",
      explanation: "Correct: |α|² = 1² = 1, so measuring |0⟩ always yields 0."
    },
    {
      id: "q-hadamard",
      trackId: "quantum",
      title: "Superposition & the Hadamard gate",
      summary: "Applying the Hadamard (H) gate to |0⟩ maps it to (|0⟩ + |1⟩)/√2, giving equal 50%/50% measurement odds. Applying H a second time returns it to |0⟩.",
      prompt: "What gate restores H|0⟩ back to |0⟩ when applied a second time?",
      choices: ["X", "H", "Z"],
      acceptedAnswers: ["h", "hadamard"],
      hint: "The Hadamard gate is its own inverse: H · H = I.",
      explanation: "Correct: Hadamard is self-inverse (H² = I), so applying H twice returns to |0⟩."
    },
    {
      id: "q-pauli",
      trackId: "quantum",
      title: "Pauli-X and Pauli-Z gates",
      summary: "Pauli-X flips |0⟩ ↔ |1⟩ like a classical NOT gate. Pauli-Z leaves |0⟩ unchanged and flips the sign (phase) of |1⟩ to −|1⟩ without changing basis probabilities.",
      prompt: "Which Pauli gate changes relative phase without changing |0⟩/|1⟩ probabilities?",
      choices: ["X", "Z"],
      acceptedAnswers: ["z", "pauli-z", "pauli z"],
      hint: "Sign flips on |1⟩ change phase while keeping |β|² identical.",
      explanation: "Correct: Pauli-Z flips the sign of |1⟩ (phase) while |−β|² = |β|² preserves probabilities."
    },
    {
      id: "es-greetings",
      trackId: "spanish",
      title: "Spanish greetings & courtesy",
      summary: "Hola = Hello · Buenos días = Good morning · Por favor = Please · Gracias = Thank you.",
      vocab: [
        ["Hola", "Hello"],
        ["Buenos días", "Good morning"],
        ["Gracias", "Thank you"],
        ["Por favor", "Please"]
      ],
      prompt: "How do you say “Thank you” in Spanish?",
      choices: ["Hola", "Gracias", "Por favor"],
      acceptedAnswers: ["gracias"],
      hint: "It starts with 'g' and is used after someone helps you.",
      explanation: "Correct: “Gracias” means “Thank you”."
    },
    {
      id: "es-nouns",
      trackId: "spanish",
      title: "Spanish everyday words",
      summary: "El libro = the book · El agua = the water · La casa = the house · El tiempo = the time/weather.",
      vocab: [
        ["El libro", "The book"],
        ["La casa", "The house"],
        ["El agua", "The water"],
        ["Amigo / Amiga", "Friend"]
      ],
      prompt: "What does “la casa” mean in English?",
      choices: ["The book", "The house", "The water"],
      acceptedAnswers: ["the house", "house"],
      hint: "Think of a place where people live.",
      explanation: "Correct: “la casa” means “the house”."
    },
    {
      id: "fr-greetings",
      trackId: "french",
      title: "French greetings & politeness",
      summary: "Bonjour = Hello · Merci = Thank you · S'il vous plaît = Please · Au revoir = Goodbye.",
      vocab: [
        ["Bonjour", "Hello / Good day"],
        ["Merci", "Thank you"],
        ["S'il vous plaît", "Please"],
        ["Au revoir", "Goodbye"]
      ],
      prompt: "How do you say “Thank you” in French?",
      choices: ["Bonjour", "Merci", "Au revoir"],
      acceptedAnswers: ["merci"],
      hint: "A short two-syllable word starting with 'm'.",
      explanation: "Correct: “Merci” means “Thank you”."
    },
    {
      id: "fr-phrases",
      trackId: "french",
      title: "French starter phrases",
      summary: "Oui = Yes · Non = No · Pomme = Apple · Livre = Book.",
      vocab: [
        ["Oui / Non", "Yes / No"],
        ["Le livre", "The book"],
        ["La pomme", "The apple"],
        ["Bonne nuit", "Good night"]
      ],
      prompt: "What does “oui” mean in English?",
      choices: ["No", "Yes", "Please"],
      acceptedAnswers: ["yes"],
      hint: "The opposite of “non”.",
      explanation: "Correct: “oui” means “yes”."
    },
    {
      id: "py-variables",
      trackId: "python",
      title: "Python variables & strings",
      summary: "In Python, `name = \"NEXUS\"` binds a string value without a type keyword. `len(name)` returns the character count.",
      snippet: "name = \"NEXUS\"\nprint(len(name))",
      prompt: "What number does len(\"NEXUS\") evaluate to?",
      choices: ["4", "5", "6"],
      acceptedAnswers: ["5", "five"],
      hint: "Count the letters in N-E-X-U-S.",
      explanation: "Correct: \"NEXUS\" has 5 characters, so len(\"NEXUS\") is 5."
    },
    {
      id: "py-lists",
      trackId: "python",
      title: "Python lists & indexing",
      summary: "Python lists use zero-based indexing. For `items = [10, 20, 30]`, `items[0]` is `10` and `items[1]` is `20`.",
      snippet: "items = [10, 20, 30]\ntotal = items[0] + items[2]",
      prompt: "In the snippet above, what is the value of total?",
      choices: ["30", "40", "50"],
      acceptedAnswers: ["40"],
      hint: "Index 0 is 10 and index 2 is 30.",
      explanation: "Correct: items[0] is 10 and items[2] is 30, so total is 40."
    },
    {
      id: "py-functions",
      trackId: "python",
      title: "Python functions & return",
      summary: "A function defined with `def` sends a value back to the caller using `return`.",
      snippet: "def double(n):\n    return n * 2",
      prompt: "Which Python keyword sends a value back from a function?",
      choices: ["yield", "return", "print"],
      acceptedAnswers: ["return"],
      hint: "`print` displays text, while this keyword hands a value back to the caller.",
      explanation: "Correct: `return` exits the function and passes the computed value back."
    }
  ];

  const glossary = [
    {
      keywords: ["qubit", "bit", "superposition", "alpha", "beta", "ket"],
      title: "Qubit & Superposition",
      body: "A qubit holds complex amplitudes α and β for |0⟩ and |1⟩ with |α|² + |β|² = 1. Superposition means both amplitudes can be non-zero before measurement."
    },
    {
      keywords: ["hadamard", "h gate", "50", "equal"],
      title: "Hadamard (H) Gate",
      body: "H maps |0⟩ to (|0⟩ + |1⟩)/√2 and |1⟩ to (|0⟩ − |1⟩)/√2. Applying H twice returns any state to itself (H² = I)."
    },
    {
      keywords: ["pauli", "x gate", "z gate", "phase", "flip"],
      title: "Pauli-X & Pauli-Z Gates",
      body: "X swaps |0⟩ and |1⟩ (bit flip). Z leaves |0⟩ unchanged and negates |1⟩ (phase flip), keeping measurement probabilities unchanged."
    },
    {
      keywords: ["measure", "measurement", "born", "collapse", "probability"],
      title: "Born Rule & Measurement",
      body: "Measuring yields 0 with probability |α|² and 1 with probability |β|², collapsing the qubit to the observed basis state."
    },
    {
      keywords: ["spanish", "gracias", "hola", "casa", "buenos"],
      title: "Spanish Starter Notes",
      body: "Hola (hello), Buenos días (good morning), Por favor (please), Gracias (thank you), and La casa (the house)."
    },
    {
      keywords: ["french", "merci", "bonjour", "oui", "pomme"],
      title: "French Starter Notes",
      body: "Bonjour (hello), Merci (thank you), S'il vous plaît (please), Au revoir (goodbye), Oui (yes), Non (no)."
    },
    {
      keywords: ["python", "len", "list", "index", "def", "return", "function"],
      title: "Python Concept Notes",
      body: "Python strings and lists are 0-indexed (`items[0]`), `len()` counts elements, and `def` functions return results with `return`. Quantum does not execute code."
    }
  ];

  const trackById = new Map(tracks.map(t => [t.id, t]));
  const lessonById = new Map(lessons.map(l => [l.id, l]));

  function clone(value) {
    return JSON.parse(JSON.stringify(value));
  }

  function normalizeAnswer(value) {
    if (typeof value !== "string") return "";
    return value.trim().replace(/\s+/g, " ").toLocaleLowerCase();
  }

  function checkAnswer(lessonId, answer) {
    const lesson = lessonById.get(lessonId);
    if (!lesson) throw new RangeError(`Unknown lesson: ${lessonId}`);
    const normalized = normalizeAnswer(answer);
    if (!normalized) {
      return {
        correct: false,
        explanation: "Enter or select an answer first.",
        hint: lesson.hint
      };
    }
    const correct = lesson.acceptedAnswers.some(candidate => normalizeAnswer(candidate) === normalized);
    return {
      correct,
      explanation: correct ? lesson.explanation : `Not quite — ${lesson.hint}`,
      hint: lesson.hint
    };
  }

  function createEmptyProgress() {
    return { version: 1, completedLessonIds: [], xp: 0 };
  }

  function parseProgress(raw) {
    if (!raw) return createEmptyProgress();
    const parsed = typeof raw === "string" ? JSON.parse(raw) : raw;
    if (
      !parsed ||
      parsed.version !== 1 ||
      !Array.isArray(parsed.completedLessonIds) ||
      typeof parsed.xp !== "number" ||
      !Number.isInteger(parsed.xp) ||
      parsed.xp < 0 ||
      parsed.completedLessonIds.some(id => typeof id !== "string" || !lessonById.has(id))
    ) {
      throw new Error("Saved Quantum progress has an unsupported format.");
    }
    const uniqueIds = [...new Set(parsed.completedLessonIds)];
    return {
      version: 1,
      completedLessonIds: uniqueIds,
      xp: uniqueIds.length * xpPerLesson
    };
  }

  function completeLesson(progress, lessonId) {
    if (!lessonById.has(lessonId)) throw new RangeError(`Unknown lesson: ${lessonId}`);
    const base = parseProgress(progress || createEmptyProgress());
    if (base.completedLessonIds.includes(lessonId)) {
      return { progress: base, awardedXp: 0 };
    }
    const completedLessonIds = [...base.completedLessonIds, lessonId];
    return {
      progress: {
        version: 1,
        completedLessonIds,
        xp: completedLessonIds.length * xpPerLesson
      },
      awardedXp: xpPerLesson
    };
  }

  function queryGuide(question, activeLessonId) {
    const normalized = normalizeAnswer(question);
    const activeLesson = activeLessonId ? lessonById.get(activeLessonId) : null;

    if (!normalized) {
      return {
        mode: "prompt",
        title: "Offline Lesson Guide",
        body: activeLesson
          ? `Current lesson hint (${activeLesson.title}): ${activeLesson.hint}`
          : "Choose a lesson or ask about a term like qubit, Hadamard, Pauli-Z, gracias, merci, or Python return."
      };
    }

    if (normalized.includes("hint") && activeLesson) {
      return {
        mode: "lesson-hint",
        title: `Hint · ${activeLesson.title}`,
        body: activeLesson.hint
      };
    }

    const glossaryMatch = glossary.find(entry =>
      entry.keywords.some(keyword => normalized.includes(keyword))
    );
    if (glossaryMatch) {
      return {
        mode: "glossary",
        title: glossaryMatch.title,
        body: glossaryMatch.body
      };
    }

    const lessonMatch = lessons.find(lesson =>
      normalizeAnswer(lesson.title).includes(normalized) ||
      normalizeAnswer(lesson.summary).includes(normalized)
    );
    if (lessonMatch) {
      return {
        mode: "lesson",
        title: lessonMatch.title,
        body: `${lessonMatch.summary} Hint: ${lessonMatch.hint}`
      };
    }

    return {
      mode: "unmatched",
      title: "Offline topic not found",
      body: activeLesson
        ? `No local entry matched that query. Try a keyword like qubit, Hadamard, Spanish, French, or Python, or use this hint for ${activeLesson.title}: ${activeLesson.hint}`
        : "No local entry matched that query. Pick a lesson in Learn, Languages, or Coding, or search for qubit, Hadamard, Pauli, gracias, merci, or Python."
    };
  }

  window.NexusQuantumContent = Object.freeze({
    storageKey,
    xpPerLesson,
    getTracks: () => clone(tracks),
    getTrack: id => clone(trackById.get(id) || null),
    getLessons: trackId => clone(trackId ? lessons.filter(l => l.trackId === trackId) : lessons),
    getLesson: id => clone(lessonById.get(id) || null),
    normalizeAnswer,
    checkAnswer,
    createEmptyProgress,
    parseProgress,
    completeLesson,
    queryGuide
  });
})();
