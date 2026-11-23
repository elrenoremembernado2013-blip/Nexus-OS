(() => {
  const windows = new Map();
  const listeners = new Set();
  let nextId = 1;
  let nextZ = 10;
  let activeId = null;

  function snapshot(win) {
    return { id: win.id, appId: win.appId, title: win.title, state: win.state, zIndex: win.zIndex };
  }
  function emit(type, win) {
    const event = { type, window: win ? snapshot(win) : null, activeId };
    listeners.forEach(listener => listener(event));
  }
  function activate(id) {
    const win = windows.get(id);
    if (!win || win.state === "minimized") return false;
    activeId = id;
    win.zIndex = ++nextZ;
    emit("focus", win);
    return true;
  }

  window.NexusWindowManager = {
    open(appId, title, options = {}) {
      if (typeof appId !== "string" || !/^[a-z][a-z0-9-]*$/.test(appId)) throw new TypeError("A window requires a valid app ID.");
      const win = { id: "nexus-window-" + nextId++, appId, title: String(title || appId), state: "normal", zIndex: ++nextZ, onClose: typeof options.onClose === "function" ? options.onClose : null };
      windows.set(win.id, win);
      activeId = win.id;
      emit("open", win);
      return win.id;
    },
    get(id) {
      const win = windows.get(id);
      return win ? snapshot(win) : null;
    },
    list() {
      return [...windows.values()].sort((a, b) => a.zIndex - b.zIndex).map(snapshot);
    },
    getActive() {
      const win = activeId ? windows.get(activeId) : null;
      return win ? snapshot(win) : null;
    },
    setTitle(id, title) {
      const win = windows.get(id);
      if (!win) return false;
      win.title = String(title || win.appId);
      emit("title", win);
      return true;
    },
    focus(id) {
      return activate(id);
    },
    minimize(id) {
      const win = windows.get(id);
      if (!win || win.state === "closed") return false;
      win.state = "minimized";
      if (activeId === id) {
        activeId = null;
        const candidates = [...windows.values()].filter(item => item.state === "normal").sort((a, b) => b.zIndex - a.zIndex);
        if (candidates.length) activate(candidates[0].id);
      }
      emit("minimize", win);
      return true;
    },
    restore(id) {
      const win = windows.get(id);
      if (!win || win.state === "closed") return false;
      win.state = "normal";
      activate(id);
      emit("restore", win);
      return true;
    },
    close(id) {
      const win = windows.get(id);
      if (!win) return false;
      windows.delete(id);
      if (typeof win.onClose === "function") win.onClose(snapshot(win));
      if (activeId === id) {
        activeId = null;
        const candidates = [...windows.values()].filter(item => item.state === "normal").sort((a, b) => b.zIndex - a.zIndex);
        if (candidates.length) activate(candidates[0].id);
      }
      win.state = "closed";
      emit("close", win);
      return true;
    },
    minimizeApp(appId) {
      const ids = [...windows.values()].filter(win => win.appId === appId && win.state === "normal").map(win => win.id);
      ids.forEach(id => this.minimize(id));
      return ids.length;
    },
    closeApp(appId) {
      const ids = [...windows.values()].filter(win => win.appId === appId).map(win => win.id);
      ids.forEach(id => this.close(id));
      return ids.length;
    },
    subscribe(listener) {
      if (typeof listener !== "function") throw new TypeError("Window manager listener must be a function.");
      listeners.add(listener);
      return () => listeners.delete(listener);
    }
  };
})();