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
    return `
      <h2 class="content-title">Terminal</h2>
      <p class="content-sub">Ubuntu Bash preview · native shell backend not connected.</p>
      <section class="nexus-terminal" aria-label="NEXUS Terminal preview">
        <div class="terminal-toolbar">
          <span class="terminal-leds" aria-hidden="true"><i></i><i></i><i></i></span>
          <span class="terminal-toolbar-title">NEXUS // TERMINAL</span>
          <span class="terminal-mode">${available ? "CONNECTED" : "PREVIEW"}</span>
        </div>
        <div class="terminal-screen" id="terminalOut" role="log" aria-live="polite">
          <p class="terminal-welcome">NEXUS Terminal</p>
          <p class="terminal-muted">Ubuntu GNU Bash is the planned native shell.</p>
          <p class="terminal-warning">Preview mode — no shell process is connected. Commands are not executed.</p>
          <p class="terminal-prompt"><span>user@nexus</span>:<span>~</span>$ <span class="terminal-caret" aria-hidden="true"></span></p>
        </div>
        <div class="terminal-input">
          <span class="terminal-input-prompt" aria-hidden="true">$</span>
          <input id="terminalInput" autocomplete="off" autocapitalize="off" spellcheck="false" placeholder="Bash unavailable in browser preview" aria-label="Terminal command">
          <button class="action-button" id="terminalSend" type="button">Send</button>
        </div>
        <p class="terminal-footnote" id="terminalStatus" role="status">Native Bash backend: ${available ? "available" : "unavailable"} · Browser JavaScript cannot run Ubuntu commands.</p>
      </section>`;
  }

  function mount(root) {
    const inp = root.querySelector("#terminalInput");
    const out = root.querySelector("#terminalOut");
    const send = root.querySelector("#terminalSend");

    const reportUnavailable = () => {
      const line = document.createElement("p");
      line.className = "terminal-warning";
      line.textContent = "Bash backend unavailable — command was not executed.";
      out.append(line);
      inp.value = "";
      out.scrollTop = out.scrollHeight;
    };

    send.addEventListener("click", reportUnavailable);
    inp.addEventListener("keydown", event => {
      if (event.key === "Enter") {
        event.preventDefault();
        reportUnavailable();
      }
    });
  }

  window.NexusAppRegistry.register({ id: "terminal", name: "Terminal", render, mount });
})();
