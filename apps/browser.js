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
      return true;
    } catch {
      return false;
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
    const goButton = root.querySelector("#browserGo");
    const bookmarkAddButton = root.querySelector("#browserBookmarkAdd");
    let bookmarks = readBookmarks();
    let mounted = true;

    const openExternal = url => {
      const validUrl = validateExternalUrl(url);
      if (!validUrl) {
        msg.textContent = "Please enter a valid HTTP or HTTPS address.";
        return;
      }
      let opened = null;
      try {
        opened = window.open(validUrl, "_blank", "noopener,noreferrer");
      } catch {
        opened = null;
      }
      if (opened) {
        opened.opener = null;
        msg.textContent = `Opened ${validUrl} in your system browser.`;
      } else {
        msg.textContent = `Popup blocked by your browser. Allow popups to open ${validUrl}.`;
      }
    };

    const drawBookmarks = () => {
      if (!mounted) return;
      bookmarksEl.replaceChildren();
      if (!bookmarks.length) {
        const empty = document.createElement("span");
        empty.className = "content-sub";
        empty.textContent = "No bookmarks saved.";
        bookmarksEl.append(empty);
        return;
      }
      bookmarks.forEach(url => {
        const chip = document.createElement("span");
        chip.style.display = "inline-flex";
        chip.style.alignItems = "center";
        chip.style.gap = "4px";
        const btn = document.createElement("button");
        btn.type = "button";
        btn.className = "action-button secondary-button";
        btn.textContent = url.replace(/^https?:\/\//, "").replace(/\/$/, "");
        btn.addEventListener("click", () => openExternal(url));
        const removeBtn = document.createElement("button");
        removeBtn.type = "button";
        removeBtn.className = "action-button secondary-button";
        removeBtn.textContent = "×";
        removeBtn.setAttribute("aria-label", `Remove bookmark ${url}`);
        removeBtn.addEventListener("click", () => {
          bookmarks = bookmarks.filter(item => item !== url);
          const saved = saveBookmarks(bookmarks);
          drawBookmarks();
          msg.textContent = saved
            ? `Removed bookmark ${url}.`
            : `Removed bookmark ${url} for this session (storage unavailable).`;
        });
        chip.append(btn, removeBtn);
        bookmarksEl.append(chip);
      });
    };

    const submitAddress = () => {
      const raw = input.value.trim();
      if (!raw) {
        msg.textContent = "Please enter a valid HTTP or HTTPS address or search query.";
        return;
      }
      const hasExplicitScheme = /^[a-zA-Z][a-zA-Z0-9+.-]*:/.test(raw);
      if (hasExplicitScheme && !/^https?:/i.test(raw)) {
        msg.textContent = "Only HTTP and HTTPS web addresses are allowed.";
        return;
      }
      const looksLikeAddress = hasExplicitScheme || (raw.includes(".") && !/\s/.test(raw));
      const target = looksLikeAddress ? validateExternalUrl(raw) : buildSearchUrl(raw, engineSelect.value);
      if (!target) {
        msg.textContent = "Please enter a valid HTTP or HTTPS address or search query.";
        return;
      }
      openExternal(target);
    };

    const handleAddBookmark = () => {
      const valid = validateExternalUrl(input.value);
      if (!valid) {
        msg.textContent = "Only valid HTTP or HTTPS URLs can be bookmarked.";
        return;
      }
      if (bookmarks.includes(valid)) {
        msg.textContent = `Bookmark already saved: ${valid}.`;
        return;
      }
      bookmarks = [valid, ...bookmarks].slice(0, 12);
      const saved = saveBookmarks(bookmarks);
      drawBookmarks();
      msg.textContent = saved
        ? `Bookmarked ${valid}.`
        : `Bookmarked ${valid} for this session (storage unavailable).`;
    };

    const handleKeydown = event => {
      if (event.key === "Enter") {
        event.preventDefault();
        submitAddress();
      }
    };

    goButton.addEventListener("click", submitAddress);
    bookmarkAddButton.addEventListener("click", handleAddBookmark);
    input.addEventListener("keydown", handleKeydown);
    drawBookmarks();

    return () => {
      mounted = false;
      goButton.removeEventListener("click", submitAddress);
      bookmarkAddButton.removeEventListener("click", handleAddBookmark);
      input.removeEventListener("keydown", handleKeydown);
    };
  }

  window.NexusBrowser = Object.freeze({ validateExternalUrl, buildSearchUrl });
  window.NexusAppRegistry.register({ id: "browser", name: "Browser", render, mount });
})();
