(() => {
  const invSqrt2 = Math.SQRT1_2;

  function cloneComplex(z) {
    if (!z || typeof z.re !== "number" || typeof z.im !== "number" || !Number.isFinite(z.re) || !Number.isFinite(z.im)) {
      throw new TypeError("Complex amplitude must have finite numeric re and im fields.");
    }
    return { re: z.re, im: z.im };
  }

  function normSquared(alpha, beta) {
    return (
      alpha.re * alpha.re +
      alpha.im * alpha.im +
      beta.re * beta.re +
      beta.im * beta.im
    );
  }

  function normalizeState(alpha, beta, gates) {
    const a = cloneComplex(alpha);
    const b = cloneComplex(beta);
    const magSq = normSquared(a, b);
    if (!(magSq > 0) || !Number.isFinite(magSq)) {
      throw new RangeError("Qubit state vector must have non-zero norm.");
    }
    const invNorm = 1 / Math.sqrt(magSq);
    const clean = x => (Math.abs(x) < 1e-15 ? 0 : x);
    return {
      alpha: { re: clean(a.re * invNorm), im: clean(a.im * invNorm) },
      beta: { re: clean(b.re * invNorm), im: clean(b.im * invNorm) },
      gates: Array.isArray(gates) ? [...gates] : []
    };
  }

  function createState() {
    return {
      alpha: { re: 1, im: 0 },
      beta: { re: 0, im: 0 },
      gates: []
    };
  }

  function applyGate(state, gate) {
    const current = normalizeState(state?.alpha, state?.beta, state?.gates);
    const { alpha, beta, gates } = current;
    let nextAlpha;
    let nextBeta;

    if (gate === "H") {
      nextAlpha = {
        re: (alpha.re + beta.re) * invSqrt2,
        im: (alpha.im + beta.im) * invSqrt2
      };
      nextBeta = {
        re: (alpha.re - beta.re) * invSqrt2,
        im: (alpha.im - beta.im) * invSqrt2
      };
    } else if (gate === "X") {
      nextAlpha = beta;
      nextBeta = alpha;
    } else if (gate === "Z") {
      nextAlpha = alpha;
      nextBeta = { re: -beta.re, im: -beta.im };
    } else {
      throw new RangeError(`Unknown single-qubit gate: ${gate}`);
    }

    return normalizeState(nextAlpha, nextBeta, [...gates, gate]);
  }

  function probabilities(state) {
    const current = normalizeState(state?.alpha, state?.beta, state?.gates);
    let zero =
      current.alpha.re * current.alpha.re +
      current.alpha.im * current.alpha.im;
    if (Math.abs(zero) < 1e-14) zero = 0;
    else if (Math.abs(zero - 1) < 1e-14) zero = 1;
    else if (Math.abs(zero - 0.5) < 1e-14) zero = 0.5;
    zero = Math.min(1, Math.max(0, zero));
    const one = Math.min(1, Math.max(0, 1 - zero));
    return { zero, one };
  }

  function measure(state, randomValue = Math.random()) {
    if (typeof randomValue !== "number" || !Number.isFinite(randomValue) || randomValue < 0 || randomValue > 1) {
      throw new RangeError("Measurement randomValue must be a finite number between 0 and 1.");
    }
    const current = normalizeState(state?.alpha, state?.beta, state?.gates);
    const { zero } = probabilities(current);
    const outcome = zero === 1 || (zero > 0 && randomValue < zero) ? 0 : 1;
    const collapsedState = {
      alpha: { re: outcome === 0 ? 1 : 0, im: 0 },
      beta: { re: outcome === 1 ? 1 : 0, im: 0 },
      gates: [...current.gates, `M→${outcome}`]
    };
    return { outcome, state: collapsedState };
  }

  window.NexusQuantumEngine = Object.freeze({
    createState,
    applyGate,
    probabilities,
    measure
  });
})();
