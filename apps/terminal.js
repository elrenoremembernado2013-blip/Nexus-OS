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

  const maxTerminalLines = 500;

  function appendLine(out, text, className) {
    const line = document.createElement("p");
    if (className) line.className = className;
    line.textContent = String(text ?? "");
    out.append(line);
    while (out.childElementCount > maxTerminalLines && out.firstElementChild) {
      out.firstElementChild.remove();
    }
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
    let disposed = false;

    const reportUnavailable = () => {
      appendLine(out, "Bash backend unavailable — command was not executed.", "terminal-warning");
      inp.value = "";
    };

    const setDisconnectedState = (message, modeText = "PREVIEW") => {
      sessionId = null;
      if (modeEl) modeEl.textContent = modeText;
      if (statusEl) statusEl.textContent = "Native Bash backend: unavailable · Browser JavaScript cannot run Ubuntu commands.";
      if (interruptBtn) interruptBtn.disabled = true;
      if (message) appendLine(out, message, "terminal-warning");
    };

    const finalizeOpen = opened => {
      const nextId = typeof opened === "string" ? opened : opened?.sessionId || null;
      if (disposed) {
        if (nextId) {
          try {
            const c = window.NexusNativeServices.call("terminal", "closeSession", nextId);
            if (c && typeof c.then === "function") c.catch(() => {});
          } catch {
            // Ignore errors during teardown after async open
          }
        }
        return false;
      }
      sessionId = nextId;
      if (!sessionId) {
        setDisconnectedState("Bash backend unavailable — native PTY session did not return a session ID.");
        return false;
      }
      return true;
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
        if (opened && typeof opened.then === "function") {
          opened
            .then(finalizeOpen)
            .catch(err => {
              if (!disposed) setDisconnectedState(err?.message || "Bash backend unavailable — command was not executed.");
            });
          return true;
        }
        return finalizeOpen(opened);
      } catch (err) {
        setDisconnectedState(err?.message || "Bash backend unavailable — command was not executed.");
        return false;
      }
    };

    connectNativeSession();

    const handleAsyncError = (err, fallbackMsg) => {
      if (err?.name === "NativeIntegrationUnavailableError") {
        setDisconnectedState(err.message || "Native terminal session disconnected.", "CLOSED");
        return;
      }
      appendLine(out, err?.message || fallbackMsg, "terminal-warning");
    };

    const submitCommand = () => {
      if (!sessionId) {
        reportUnavailable();
        return;
      }
      const value = inp.value;
      inp.value = "";
      try {
        const res = window.NexusNativeServices.call("terminal", "write", sessionId, `${value}\n`);
        if (res && typeof res.then === "function") {
          res.catch(err => handleAsyncError(err, "Failed to write to native terminal session."));
        }
      } catch (err) {
        handleAsyncError(err, "Failed to write to native terminal session.");
      }
    };

    const sendInterrupt = () => {
      if (!sessionId) return;
      try {
        const res = window.NexusNativeServices.call("terminal", "interrupt", sessionId);
        if (res && typeof res.then === "function") {
          res.catch(err => handleAsyncError(err, "Failed to interrupt native terminal session."));
        }
      } catch (err) {
        handleAsyncError(err, "Failed to interrupt native terminal session.");
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
      disposed = true;
      send.removeEventListener("click", submitCommand);
      if (interruptBtn) interruptBtn.removeEventListener("click", sendInterrupt);
      inp.removeEventListener("keydown", handleKeydown);
      if (sessionId) {
        const closingId = sessionId;
        sessionId = null;
        try {
          const c = window.NexusNativeServices.call("terminal", "closeSession", closingId);
          if (c && typeof c.then === "function") c.catch(() => {});
        } catch {
          // Ignore errors during teardown if native adapter was unregistered first.
        }
      }
    };
  }

  window.NexusAppRegistry.register({ id: "terminal", name: "Terminal", render, mount });
})();
