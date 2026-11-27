(() => {
  function evaluateExpression(input) {
    if (typeof input !== "string") throw new TypeError("Expression must be a string");
    const source = input.replace(/\s/g, "");
    if (!source || source.length > 120) throw new Error("Invalid expression length");
    const tokens = source.match(/\d+(?:\.\d*)?|\.\d+|[()+\-*/]/g) || [];
    if (tokens.length > 64 || tokens.join("") !== source) throw new Error("Invalid expression");
    let pos = 0;

    function primary() {
      const t = tokens[pos++];
      if (t === "(") {
        const value = addSub();
        if (tokens[pos++] !== ")") throw new Error("Missing )");
        return value;
      }
      if (t === "+" || t === "-") {
        const value = primary();
        return t === "-" ? -value : value;
      }
      if (!t || !/^(?:\d+(?:\.\d*)?|\.\d+)$/.test(t)) throw new Error("Expected number");
      const value = Number(t);
      if (!Number.isFinite(value)) throw new Error("Invalid number");
      return value;
    }

    function mulDiv() {
      let value = primary();
      while (tokens[pos] === "*" || tokens[pos] === "/") {
        const op = tokens[pos++];
        const rhs = primary();
        if (op === "/" && rhs === 0) throw new Error("Division by zero");
        value = op === "*" ? value * rhs : value / rhs;
      }
      return value;
    }

    function addSub() {
      let value = mulDiv();
      while (tokens[pos] === "+" || tokens[pos] === "-") {
        const op = tokens[pos++];
        const rhs = mulDiv();
        value = op === "+" ? value + rhs : value - rhs;
      }
      return value;
    }

    const result = addSub();
    if (pos !== tokens.length || !Number.isFinite(result)) throw new Error("Invalid result");
    return result;
  }

  function formatResult(value) {
    if (!Number.isFinite(value)) throw new Error("Invalid result");
    if (Object.is(value, -0)) return "0";
    return String(Number(value.toPrecision(12)));
  }

  function render() {
    const keys = ["7", "8", "9", "÷", "4", "5", "6", "×", "1", "2", "3", "−", "C", "0", ".", "+", "="];
    return `
      <h2 class="content-title">Calculator</h2>
      <p class="content-sub">Basic calculator.</p>
      <div class="calc">
        <input id="calcDisplay" class="calc-display" readonly value="0" aria-label="Calculator display">
        <div class="calc-buttons">
          ${keys.map(k => `<button type="button" data-calc="${k}">${k}</button>`).join("")}
        </div>
      </div>`;
  }

  function mount(root) {
    let exp = "";
    const display = root.querySelector("#calcDisplay");
    const operatorMap = { "÷": "/", "×": "*", "−": "-" };

    function pressKey(k) {
      if (k === "C") {
        exp = "";
        display.value = "0";
      } else if (k === "=") {
        if (!exp) return;
        try {
          display.value = formatResult(evaluateExpression(exp));
          exp = display.value;
        } catch {
          display.value = "Error";
          exp = "";
        }
      } else if (k === "Backspace") {
        exp = exp.slice(0, -1);
        display.value = exp || "0";
      } else if (exp.length < 120) {
        exp += operatorMap[k] || k;
        display.value = exp;
      } else {
        display.value = "Limit reached";
      }
    }

    root.querySelectorAll("[data-calc]").forEach(button => {
      button.addEventListener("click", () => pressKey(button.dataset.calc));
    });

    const onKeyDown = event => {
      if (event.metaKey || event.ctrlKey || event.altKey) return;
      const key = event.key;
      if (/^[0-9.+\-*/()]$/.test(key)) {
        event.preventDefault();
        pressKey(key);
      } else if (key === "Enter" || key === "=") {
        event.preventDefault();
        pressKey("=");
      } else if (key === "Escape") {
        event.preventDefault();
        pressKey("C");
      } else if (key === "Backspace") {
        event.preventDefault();
        pressKey("Backspace");
      }
    };
    root.addEventListener("keydown", onKeyDown);
    return () => root.removeEventListener("keydown", onKeyDown);
  }

  window.NexusCalculator = Object.freeze({ evaluateExpression, formatResult });
  window.NexusAppRegistry.register({ id: "calculator", name: "Calculator", render, mount });
})();
