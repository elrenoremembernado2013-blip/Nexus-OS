(() => {
  function validateExternalUrl(raw) {
    if (typeof raw !== "string") return null;
    let url = raw.trim();
    if (!url || /\s/.test(url)) return null;
    if (/^[a-zA-Z][a-zA-Z0-9+.-]*:/.test(url)) {
      if (!/^https?:/i.test(url)) return null;
    } else {
      url = "https://" + url;
    }
    try {
      const parsed = new URL(url);
      if (!["http:", "https:"].includes(parsed.protocol) || !parsed.hostname) return null;
      return parsed.href;
    } catch {
      return null;
    }
  }

  function render() {
    return `
      <h2 class="content-title">Browser</h2>
      <p class="content-sub">Safe browser interface mockup.</p>
      <div class="browser-address">
        <input id="browserUrl" value="https://example.com" aria-label="URL">
        <button class="action-button" id="browserGo" type="button">Open</button>
      </div>
      <div class="content-card" style="margin-top:14px">
        <h3>Browser preview</h3>
        <p class="content-sub" id="browserMsg">External pages are not loaded inside this demo. Use Open to visit a site in a new tab.</p>
      </div>`;
  }

  function mount(root) {
    const input = root.querySelector("#browserUrl");
    const msg = root.querySelector("#browserMsg");
    const openLink = () => {
      const validUrl = validateExternalUrl(input.value);
      if (!validUrl) {
        msg.textContent = "Please enter a valid HTTP or HTTPS address.";
        return;
      }
      const opened = window.open(validUrl, "_blank", "noopener,noreferrer");
      if (opened) opened.opener = null;
      msg.textContent = "Opened external site in a new tab.";
    };
    root.querySelector("#browserGo").addEventListener("click", openLink);
    input.addEventListener("keydown", event => {
      if (event.key === "Enter") {
        event.preventDefault();
        openLink();
      }
    });
  }

  window.NexusBrowser = Object.freeze({ validateExternalUrl });
  window.NexusAppRegistry.register({ id: "browser", name: "Browser", render, mount });
})();
