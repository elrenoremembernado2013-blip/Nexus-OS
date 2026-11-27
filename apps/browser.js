(() => {
  const bookmarkStorageKey = "nexus-browser-bookmarks-v1";
  const searchEngines = {
    duckduckgo: { name: "DuckDuckGo", template: "https://duckduckgo.com/?q=" },
    startpage: { name: "Startpage", template: "https://www.startpage.com/sp/search?query=" },
    wikipedia: { name: "Wikipedia", template: "https://en.wikipedia.org/wiki/Special:Search?search=" }
  };

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

  function buildSearchUrl(query, engineId = "duckduckgo") {
    const trimmed = typeof query === "string" ? query.trim() : "";
    if (!trimmed) return null;
    const engine = searchEngines[engineId] || searchEngines.duckduckgo;
    return engine.template + encodeURIComponent(trimmed);
  }

  function readBookmarks() {
    try {
      const raw = window.localStorage.getItem(bookmarkStorageKey);
      if (!raw) return ["https://linuxmint.com/", "https://example.com/"];
      const parsed = JSON.parse(raw);
      if (!Array.isArray(parsed)) return ["https://linuxmint.com/", "https://example.com/"];
      return parsed.map(validateExternalUrl).filter(Boolean).slice(0, 12);
    } catch {
      return ["https://linuxmint.com/", "https://example.com/"];
    }
  }

  function saveBookmarks(list) {
    try {
      window.localStorage.setItem(bookmarkStorageKey, JSON.stringify(list));
    } catch {
      // Ignore restricted storage contexts.
    }
  }

  function render() {
    return `
      <h2 class="content-title">Browser</h2>
      <p class="content-sub">Launches validated web addresses and searches in your host system browser.</p>
      <div class="browser-address">
        <input id="browserUrl" value="https://linuxmint.com" aria-label="URL or search query">
        <select id="browserEngine" class="store-select" aria-label="Search engine">
          <option value="duckduckgo">DuckDuckGo</option>
          <option value="startpage">Startpage</option>
          <option value="wikipedia">Wikipedia</option>
        </select>
        <button class="action-button" id="browserGo" type="button">Open</button>
        <button class="action-button secondary-button" id="browserBookmarkAdd" type="button">Bookmark</button>
      </div>
      <div class="content-card" style="margin-top:14px">
        <h3>Bookmarks</h3>
        <div id="browserBookmarks" style="display:flex;flex-wrap:wrap;gap:8px;margin-top:8px"></div>
      </div>
      <div class="content-card" style="margin-top:14px">
        <h3>System browser integration</h3>
        <p class="content-sub" id="browserMsg">External pages are opened in your system browser (Firefox/Chromium on Linux Mint) rather than an embedded webview.</p>
      </div>`;
  }

  function mount(root) {
    const input = root.querySelector("#browserUrl");
    const engineSelect = root.querySelector("#browserEngine");
    const msg = root.querySelector("#browserMsg");
    const bookmarksEl = root.querySelector("#browserBookmarks");
    let bookmarks = readBookmarks();

    const openExternal = url => {
      const validUrl = validateExternalUrl(url);
      if (!validUrl) {
        msg.textContent = "Please enter a valid HTTP or HTTPS address.";
        return;
      }
      const opened = window.open(validUrl, "_blank", "noopener,noreferrer");
      if (opened) opened.opener = null;
      msg.textContent = `Opened ${validUrl} in your system browser.`;
    };

    const drawBookmarks = () => {
      bookmarksEl.replaceChildren();
      if (!bookmarks.length) {
        const empty = document.createElement("span");
        empty.className = "content-sub";
        empty.textContent = "No bookmarks saved.";
        bookmarksEl.append(empty);
        return;
      }
      bookmarks.forEach(url => {
        const btn = document.createElement("button");
        btn.type = "button";
        btn.className = "action-button secondary-button";
        btn.textContent = url.replace(/^https?:\/\//, "").replace(/\/$/, "");
        btn.addEventListener("click", () => openExternal(url));
        bookmarksEl.append(btn);
      });
    };

    const submitAddress = () => {
      const raw = input.value.trim();
      const direct = raw.includes(".") || /^[a-zA-Z][a-zA-Z0-9+.-]*:/.test(raw) ? validateExternalUrl(raw) : null;
      const target = direct || buildSearchUrl(raw, engineSelect.value);
      if (!target) {
        msg.textContent = "Please enter a valid HTTP or HTTPS address or search query.";
        return;
      }
      openExternal(target);
    };

    root.querySelector("#browserGo").addEventListener("click", submitAddress);
    root.querySelector("#browserBookmarkAdd").addEventListener("click", () => {
      const valid = validateExternalUrl(input.value);
      if (!valid) {
        msg.textContent = "Only valid HTTP or HTTPS URLs can be bookmarked.";
        return;
      }
      if (!bookmarks.includes(valid)) {
        bookmarks = [valid, ...bookmarks].slice(0, 12);
        saveBookmarks(bookmarks);
        drawBookmarks();
        msg.textContent = `Bookmarked ${valid}.`;
      }
    });
    input.addEventListener("keydown", event => {
      if (event.key === "Enter") {
        event.preventDefault();
        submitAddress();
      }
    });
    drawBookmarks();
  }

  window.NexusBrowser = Object.freeze({ validateExternalUrl, buildSearchUrl });
  window.NexusAppRegistry.register({ id: "browser", name: "Browser", render, mount });
})();
