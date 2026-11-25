(() => {
  function terminalAvailable() {
    try {
      return Boolean(window.NexusNativeServices?.status("terminal")?.available);
    } catch {
      return false;
    }
  }

  function render() {
    const available = terminalAvailable();
    const subtitle = available
      ? "Ubuntu GNU Bash session · connected via native PTY service."
      : "Ubuntu Bash preview · native shell backend not connected.";
    const modeLabel = available ? "CONNECTED" : "PREVIEW";
    const placeholder = available
      ? "Enter command for native Bash session"
      : "Bash unavailable in browser preview";
    const footnote = available
      ? "Native Bash backend: available · Session isolated to the logged-in desktop user."
      : "Native Bash backend: unavailable · Browser JavaScript cannot run Ubuntu commands.";

    return `
      <h2 class="content-title">Terminal</h2>
      <p class="content-sub">${subtitle}</p>
      <section class="nexus-terminal" aria-label="NEXUS Terminal preview">
        <div class="terminal-toolbar">
          <span class="terminal-leds" aria-hidden="true"><i></i><i></i><i></i></span>
          <span class="terminal-toolbar-title">NEXUS // TERMINAL</span>
          <span class="terminal-mode">${modeLabel}</span>
        </div>
        <div class="terminal-screen" id="terminalOut" role="log" aria-live="polite">
          <p class="terminal-welcome">NEXUS Terminal</p>
          <p class="terminal-muted">${available ? "Interactive GNU Bash PTY session ready." : "Ubuntu GNU Bash is the planned native shell."}</p>
          ${available ? "" : '<p class="terminal-warning">Preview mode — no shell process is connected. Commands are not executed.</p>'}
          <p class="terminal-prompt"><span>user@nexus</span>:<span>~</span>$ <span class="terminal-caret" aria-hidden="true"></span></p>
        </div>
        <div class="terminal-input">
          <span class="terminal-input-prompt" aria-hidden="true">$</span>
          <input id="terminalInput" autocomplete="off" autocapitalize="off" spellcheck="false" placeholder="${placeholder}" aria-label="Terminal command">
          <button class="action-button secondary-button" id="terminalInterrupt" type="button" ${available ? "" : "disabled"} title="Send interrupt signal (Ctrl+C)">Ctrl+C</button>
          <button class="action-button" id="terminalSend" type="button">Send</button>
        </div>
        <p class="terminal-footnote" id="terminalStatus" role="status">${footnote}</p>
      </section>`;
  }

  function appendLine(out, text, className) {
    const line = document.createElement("p");
    if (className) line.className = className;
    line.textContent = String(text ?? "");
    out.append(line);
    out.scrollTop = out.scrollHeight;
  }

  function mount(root) {
    const inp = root.querySelector("#terminalInput");
    const out = root.querySelector("#terminalOut");
    const send = root.querySelector("#terminalSend");
    const interruptBtn = root.querySelector("#terminalInterrupt");
    const modeEl = root.querySelector(".terminal-mode");
    const statusEl = root.querySelector("#terminalStatus");
    let sessionId = null;

    const reportUnavailable = () => {
      appendLine(out, "Bash backend unavailable — command was not executed.", "terminal-warning");
      inp.value = "";
    };

    const connectNativeSession = () => {
      if (!terminalAvailable()) return false;
      try {
        const opened = window.NexusNativeServices.call("terminal", "openSession", {
          cols: 80,
          rows: 24,
          onOutput(chunk) {
            appendLine(out, chunk, "terminal-output");
          },
          onExit(code) {
            sessionId = null;
            if (modeEl) modeEl.textContent = "CLOSED";
            if (interruptBtn) interruptBtn.disabled = true;
            appendLine(out, `Session exited (${code ?? 0}).`, "terminal-muted");
          },
          onError(err) {
            appendLine(out, err?.message || String(err), "terminal-warning");
          },
        });
        sessionId = typeof opened === "string" ? opened : opened?.sessionId || null;
        return Boolean(sessionId);
      } catch (err) {
        if (modeEl) modeEl.textContent = "PREVIEW";
        if (statusEl) statusEl.textContent = "Native Bash backend: unavailable · Browser JavaScript cannot run Ubuntu commands.";
        if (interruptBtn) interruptBtn.disabled = true;
        appendLine(out, err?.message || "Bash backend unavailable — command was not executed.", "terminal-warning");
        sessionId = null;
        return false;
      }
    };

    connectNativeSession();

    const submitCommand = () => {
      if (!sessionId) {
        reportUnavailable();
        return;
      }
      const value = inp.value;
      inp.value = "";
      try {
        window.NexusNativeServices.call("terminal", "write", sessionId, `${value}\n`);
      } catch (err) {
        appendLine(out, err?.message || "Failed to write to native terminal session.", "terminal-warning");
      }
    };

    const sendInterrupt = () => {
      if (!sessionId) return;
      try {
        window.NexusNativeServices.call("terminal", "interrupt", sessionId);
      } catch (err) {
        appendLine(out, err?.message || "Failed to interrupt native terminal session.", "terminal-warning");
      }
    };

    const handleKeydown = event => {
      if (event.key === "Enter") {
        event.preventDefault();
        submitCommand();
      } else if (event.ctrlKey && event.key.toLowerCase() === "c" && !inp.value) {
        event.preventDefault();
        sendInterrupt();
      } else if (event.ctrlKey && event.key.toLowerCase() === "l") {
        event.preventDefault();
        out.replaceChildren();
        appendLine(out, sessionId ? "NEXUS Terminal (cleared)" : "Preview mode — no shell process is connected. Commands are not executed.", sessionId ? "terminal-muted" : "terminal-warning");
      }
    };

    send.addEventListener("click", submitCommand);
    if (interruptBtn) interruptBtn.addEventListener("click", sendInterrupt);
    inp.addEventListener("keydown", handleKeydown);

    return () => {
      send.removeEventListener("click", submitCommand);
      if (interruptBtn) interruptBtn.removeEventListener("click", sendInterrupt);
      inp.removeEventListener("keydown", handleKeydown);
      if (sessionId) {
        const closingId = sessionId;
        sessionId = null;
        try {
          window.NexusNativeServices.call("terminal", "closeSession", closingId);
        } catch {
          // Ignore errors during teardown if native adapter was unregistered first.
        }
      }
    };
  }

  window.NexusAppRegistry.register({ id: "terminal", name: "Terminal", render, mount });
})();
