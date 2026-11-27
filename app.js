(() => {
  const $ = selector => document.querySelector(selector);
  const $$ = selector => [...document.querySelectorAll(selector)];

  const desktop = $("#desktop");
  const control = $("#controlPanel");
  const launcher = $("#launcher");
  const windowLayer = $("#windowLayer");
  const toast = $("#toast");

  const wallpaperCatalog = Object.fromEntries(
    (window.NexusPersonalisationCatalog?.WALLPAPERS || []).map(wp => [wp.id, wp])
  );

  function getWallpaperUrl(id) {
    const entry = wallpaperCatalog[id];
    if (!entry) return null;
    const res = readStorage("nexus-wallpaper-resolution") || "uhd";
    return res === "hd" ? (entry.hd || entry.uhd) : (entry.uhd || entry.hd);
  }

  let activeCustomWallpaperUrl = null;
  let toastTimer = null;
  let panelTrigger = null;

  function readStorage(key) {
    try {
      return window.localStorage.getItem(key);
    } catch {
      return null;
    }
  }

  function writeStorage(key, value) {
    try {
      window.localStorage.setItem(key, value);
    } catch {
      // Ignore storage quota or sandbox restrictions in browser preview.
    }
  }

  function setDesktopBackground(url) {
    desktop.style.backgroundImage =
      `linear-gradient(120deg,rgba(8,13,25,.72),rgba(11,13,30,.24)),url("${url}")`;
  }

  function clearCustomDesktopWallpaper() {
    if (activeCustomWallpaperUrl) {
      URL.revokeObjectURL(activeCustomWallpaperUrl);
      activeCustomWallpaperUrl = null;
    }
  }

  function setDesktopWallpaper(id, persist = true) {
    const image = getWallpaperUrl(id);
    if (!image) return false;
    setDesktopBackground(image);
    if (persist) writeStorage("nexus-wallpaper", id);
    return true;
  }

  function setCustomDesktopWallpaper(url, persist = true) {
    if (activeCustomWallpaperUrl && activeCustomWallpaperUrl !== url) {
      URL.revokeObjectURL(activeCustomWallpaperUrl);
    }
    activeCustomWallpaperUrl = url;
    setDesktopBackground(url);
    if (persist) writeStorage("nexus-wallpaper", "custom");
  }

  async function restoreCustomWallpaperAtStartup() {
    if (readStorage("nexus-wallpaper") !== "custom" || !("indexedDB" in window)) return;
    try {
      const db = await new Promise((resolve, reject) => {
        const request = window.indexedDB.open("nexus-wallpaper-store", 1);
        request.onupgradeneeded = () => {
          if (!request.result.objectStoreNames.contains("wallpapers")) {
            request.result.createObjectStore("wallpapers");
          }
        };
        request.onsuccess = () => resolve(request.result);
        request.onerror = () => reject(new Error("Could not open local wallpaper storage."));
      });
      const blob = await new Promise((resolve, reject) => {
        const tx = db.transaction("wallpapers", "readonly");
        const request = tx.objectStore("wallpapers").get("custom");
        request.onsuccess = () => resolve(request.result || null);
        request.onerror = () => reject(new Error("Could not read the saved wallpaper."));
        tx.oncomplete = () => db.close();
      });
      if (blob && (typeof Blob === "undefined" || blob instanceof Blob) &&
          ["image/jpeg", "image/png", "image/webp"].includes(blob.type)) {
        setCustomDesktopWallpaper(URL.createObjectURL(blob), false);
      } else {
        writeStorage("nexus-wallpaper", "alpine");
        setDesktopWallpaper("alpine", false);
      }
    } catch (error) {
      console.warn("NEXUS custom wallpaper restore:", error);
      writeStorage("nexus-wallpaper", "alpine");
      setDesktopWallpaper("alpine", false);
    }
  }

  const appNames = Object.fromEntries(
    window.NexusApplicationCatalog.getAll()
      .filter(app => app.launchTarget)
      .map(app => [app.launchTarget, app.launcherName || app.name])
  );
  window.NexusAppRegistry.list().forEach(app => {
    appNames[app.id] = app.name;
  });

  function updateClock() {
    const now = new Date();
    const use24 = readStorage("nexus-clock-24h") === "true";
    $("#clock").textContent = now.toLocaleTimeString([], { hour: "2-digit", minute: "2-digit", hour12: !use24 });
  }
  updateClock();
  window.setInterval(updateClock, 30000);

  function notify(msg) {
    toast.textContent = msg;
    toast.classList.remove("hidden");
    window.clearTimeout(toastTimer);
    toastTimer = window.setTimeout(() => toast.classList.add("hidden"), 2200);
  }

  function renderLauncher() {
    const grid = $("#appGrid");
    if (!grid) return;
    const term = $("#appSearch").value.trim().toLocaleLowerCase();
    const apps = window.NexusApplicationCatalog.getLauncherApps();
    grid.replaceChildren();
    if (!apps.length) {
      const empty = document.createElement("p");
      empty.className = "launcher-empty";
      empty.textContent = "No apps available in the launcher.";
      grid.append(empty);
      return;
    }
    apps.forEach(app => {
      const button = document.createElement("button");
      button.type = "button";
      button.className = "app-item";
      button.dataset.app = app.launchTarget;
      button.style.display = (app.name + " " + app.launcherName + " " + app.category)
        .toLocaleLowerCase()
        .includes(term)
        ? "flex"
        : "none";
      const icon = document.createElement("img");
      icon.className = "app-icon-img";
      icon.src = app.icon;
      icon.alt = "";
      icon.setAttribute("aria-hidden", "true");
      icon.decoding = "async";
      button.append(icon, document.createTextNode(app.launcherName || app.name));
      grid.append(button);
    });
  }

  function syncPanelExpanded() {
    const controlOpen = !control.classList.contains("hidden");
    const launcherOpen = !launcher.classList.contains("hidden");
    ["#controlButton", "#notificationButton"].forEach(selector =>
      $(selector).setAttribute("aria-expanded", String(controlOpen))
    );
    $("#launcherButton").setAttribute("aria-expanded", String(launcherOpen));
  }

  function closePanels() {
    control.classList.add("hidden");
    launcher.classList.add("hidden");
    panelTrigger = null;
    syncPanelExpanded();
  }

  $("#controlButton").addEventListener("click", event => {
    const opening = control.classList.contains("hidden");
    launcher.classList.add("hidden");
    control.classList.toggle("hidden");
    panelTrigger = opening ? event.currentTarget : null;
    syncPanelExpanded();
  });

  $("#notificationButton").addEventListener("click", event => {
    launcher.classList.add("hidden");
    control.classList.remove("hidden");
    panelTrigger = event.currentTarget;
    syncPanelExpanded();
    $("#controlNotifications").scrollIntoView({
      block: "nearest",
      behavior: document.body.classList.contains("reduced-motion") ? "auto" : "smooth"
    });
  });

  $("#clearNotifications").addEventListener("click", () => {
    const list = $("#notificationList");
    list.replaceChildren();
    const empty = document.createElement("div");
    empty.className = "notification-empty";
    const title = document.createElement("p");
    title.textContent = "You're all caught up.";
    const sub = document.createElement("small");
    sub.textContent = "Notifications will appear here.";
    empty.append(title, sub);
    list.append(empty);
    notify("Notifications cleared");
  });

  $("#launcherButton").addEventListener("click", event => {
    const opening = launcher.classList.contains("hidden");
    control.classList.add("hidden");
    launcher.classList.toggle("hidden");
    panelTrigger = opening ? event.currentTarget : null;
    syncPanelExpanded();
    if (opening) $("#appSearch").focus();
    else event.currentTarget.focus();
  });

  document.querySelectorAll("[data-close]").forEach(button => {
    button.addEventListener("click", () => {
      const panel = $("#" + button.dataset.close);
      panel.classList.add("hidden");
      syncPanelExpanded();
      if (panelTrigger) {
        const trigger = panelTrigger;
        panelTrigger = null;
        trigger.focus();
      }
    });
  });

  document.addEventListener("pointerdown", event => {
    const target = event.target;
    if (
      target.closest &&
      target.closest("#controlPanel, #controlButton, #notificationButton, #launcher, #launcherButton")
    ) {
      return;
    }
    if (!control.classList.contains("hidden") || !launcher.classList.contains("hidden")) {
      closePanels();
    }
  });

  document.addEventListener("keydown", event => {
    if (event.key !== "Escape") return;
    const launcherWasOpen = !launcher.classList.contains("hidden");
    const controlWasOpen = !control.classList.contains("hidden");
    if (!launcherWasOpen && !controlWasOpen) return;
    const trigger = launcherWasOpen ? $("#launcherButton") : panelTrigger || $("#controlButton");
    control.classList.add("hidden");
    launcher.classList.add("hidden");
    panelTrigger = null;
    syncPanelExpanded();
    trigger.focus();
  });

  const controlDefaults = { dnd: false, power: false };
  const controlState = { ...controlDefaults };
  const controlListeners = new Set();

  function applyControlToggle(button, enabled) {
    const key = button.dataset.toggle;
    controlState[key] = enabled;
    button.classList.toggle("active", enabled);
    button.setAttribute("aria-pressed", String(enabled));
    button.querySelector("small").textContent = (enabled ? "On" : "Off") + " · preview";
    writeStorage("nexus-control-" + key, String(enabled));
    if (key === "power") desktop.classList.toggle("lightweight", enabled);
    controlListeners.forEach(listener => {
      try {
        listener({ ...controlState });
      } catch (error) {
        console.error("NEXUS control listener failed:", error);
      }
    });
  }

  function setControlPreference(key, enabled) {
    const button = $(`[data-toggle="${key}"]`);
    if (button) applyControlToggle(button, enabled);
  }

  $$("[data-toggle]").forEach(button => {
    const key = button.dataset.toggle;
    const saved = readStorage("nexus-control-" + key);
    applyControlToggle(button, saved === null ? controlDefaults[key] : saved === "true");
    button.addEventListener("click", () => applyControlToggle(button, !controlState[key]));
  });

  const brightness = $("#brightness");
  const savedBrightness = readStorage("nexus-brightness");
  if (savedBrightness !== null) brightness.value = savedBrightness;

  function updateBrightness() {
    const output = $("#brightnessValue");
    output.value = brightness.value + "%";
    output.textContent = brightness.value + "%";
    writeStorage("nexus-brightness", brightness.value);
    desktop.style.filter = "brightness(" + Number(brightness.value) / 100 + ")";
  }
  brightness.addEventListener("input", updateBrightness);
  updateBrightness();

  function syncNativeControlBoundary() {
    const services = window.NexusNativeServices;
    const soundAvailable = Boolean(services?.status("sound")?.available);
    $("#volumeValue").textContent = soundAvailable ? "Connected" : "Unavailable";
    $("#volume").disabled = !soundAvailable;

    const networkAvailable = Boolean(services?.status("network")?.available);
    const bluetoothAvailable = Boolean(services?.status("bluetooth")?.available);
    const tiles = control.querySelectorAll(".tile[disabled]");
    if (tiles[0]) tiles[0].querySelector("small").textContent = networkAvailable ? "Connected" : "Native service unavailable";
    if (tiles[1]) tiles[1].querySelector("small").textContent = bluetoothAvailable ? "Connected" : "Native service unavailable";
  }
  syncNativeControlBoundary();

  function setThemePreset(presetId, persist = true) {
    const preset = window.NexusPersonalisationCatalog?.THEME_PRESETS?.[presetId];
    if (!preset) return false;
    desktop.dataset.nexusTheme = presetId;
    if (persist) writeStorage("nexus-theme-preset", presetId);
    return true;
  }

  function setWallpaperFit(fit, persist = true) {
    const map = { cover: "cover", contain: "contain", fill: "100% 100%", center: "auto" };
    if (!map[fit]) return false;
    document.documentElement.style.setProperty("--wallpaper-fit", map[fit]);
    if (persist) writeStorage("nexus-wallpaper-fit", fit);
    return true;
  }

  function setEffectLevel(level, persist = true) {
    if (!["off", "subtle", "balanced", "enhanced"].includes(level)) return false;
    desktop.classList.remove("effects-off", "effects-subtle", "effects-enhanced");
    if (level !== "balanced") desktop.classList.add("effects-" + level);
    if (persist) writeStorage("nexus-effect-level", level);
    return true;
  }

  function setDockPreferences(prefs = {}, persist = true) {
    if (prefs.position && ["bottom", "left", "right"].includes(prefs.position)) {
      desktop.classList.remove("dock-left", "dock-right");
      if (prefs.position !== "bottom") desktop.classList.add("dock-" + prefs.position);
      if (persist) writeStorage("nexus-dock-position", prefs.position);
    }
    if (prefs.size) {
      document.documentElement.style.setProperty("--dock-icon-size", String(prefs.size) + "px");
      if (persist) writeStorage("nexus-dock-size", String(prefs.size));
    }
    if (prefs.gap) {
      document.documentElement.style.setProperty("--dock-gap", String(prefs.gap) + "px");
      if (persist) writeStorage("nexus-dock-gap", String(prefs.gap));
    }
    if (typeof prefs.autoHide === "boolean") {
      desktop.classList.toggle("dock-autohide", prefs.autoHide);
      if (persist) writeStorage("nexus-dock-autohide", String(prefs.autoHide));
    }
    if (prefs.style && ["glass", "solid", "minimal"].includes(prefs.style)) {
      desktop.classList.remove("dock-style-solid", "dock-style-minimal");
      if (prefs.style !== "glass") desktop.classList.add("dock-style-" + prefs.style);
      if (persist) writeStorage("nexus-dock-style", prefs.style);
    }
    if (typeof prefs.showIndicators === "boolean") {
      desktop.classList.toggle("hide-dock-indicators", !prefs.showIndicators);
      if (persist) writeStorage("nexus-dock-indicators", String(prefs.showIndicators));
    }
  }

  function setDesktopPreferences(prefs = {}, persist = true) {
    if (typeof prefs.showShortcuts === "boolean") {
      desktop.classList.toggle("hide-shortcuts", !prefs.showShortcuts);
      if (persist) writeStorage("nexus-desktop-shortcuts", String(prefs.showShortcuts));
    }
    if (typeof prefs.clock24h === "boolean") {
      if (persist) writeStorage("nexus-clock-24h", String(prefs.clock24h));
      updateClock();
    }
  }

  window.NexusDesktopShell = Object.freeze({
    setDesktopWallpaper,
    getWallpaperUrl,
    setCustomDesktopWallpaper,
    clearCustomDesktopWallpaper,
    getCustomDesktopWallpaperUrl: () => activeCustomWallpaperUrl,
    setThemePreset,
    setWallpaperFit,
    setEffectLevel,
    setDockPreferences,
    setDesktopPreferences,
    getControlState: () => ({ ...controlState }),
    setControlPreference,
    onControlChange(listener) {
      if (typeof listener !== "function") return () => {};
      controlListeners.add(listener);
      return () => controlListeners.delete(listener);
    },
    resetControls: () => Object.entries(controlDefaults).forEach(([key, value]) => setControlPreference(key, value)),
    resetBrightness: () => {
      brightness.value = "100";
      updateBrightness();
    },
    openApp: appId => openApp(appId),
    notify
  });

  const windowRecords = new Map();

  function focusAppButton(appId) {
    const button = $(`.dock-app[data-app="${appId}"]`);
    if (button) {
      button.focus();
      return;
    }
    const nextActive = window.NexusWindowManager.getActive();
    if (nextActive) {
      windowRecords.get(nextActive.id)?.contentEl.focus();
      return;
    }
    $("#launcherButton")?.focus();
  }

  function syncDockIndicators() {
    const openWindows = window.NexusWindowManager.list();
    document.querySelectorAll(".dock-app[data-app]").forEach(button => {
      const appId = button.dataset.app;
      const matching = openWindows.filter(win => win.appId === appId);
      const isRunning = matching.length > 0;
      const allMinimized = isRunning && matching.every(win => win.state === "minimized");
      button.classList.toggle("running", isRunning);
      button.classList.toggle("minimized", allMinimized);
    });
  }

  function syncWindowElements() {
    const active = window.NexusWindowManager.getActive();
    for (const [id, record] of windowRecords) {
      const state = window.NexusWindowManager.get(id);
      if (!state) continue;
      record.el.style.zIndex = String(state.zIndex);
      record.el.classList.toggle("hidden", state.state === "minimized");
      record.el.classList.toggle("is-active", active?.id === id && state.state !== "minimized");
      record.titleEl.textContent = state.title;
    }
    syncDockIndicators();
  }

  window.NexusWindowManager.subscribe(syncWindowElements);

  function createWindowElement(appId, titleText) {
    const el = document.createElement("section");
    el.className = "window";
    el.dataset.appId = appId;
    el.setAttribute("role", "dialog");
    el.tabIndex = -1;

    const titlebar = document.createElement("div");
    titlebar.className = "window-titlebar";
    titlebar.title =
      "Drag to move · Double-click to maximise · Alt+F9 minimise · Alt+F10 maximise · Alt+F4 close · Ctrl+Alt+←/→ snap";

    const controls = document.createElement("div");
    controls.className = "window-controls";

    const closeBtn = document.createElement("button");
    closeBtn.type = "button";
    closeBtn.className = "window-control close";
    closeBtn.setAttribute("aria-label", "Close");
    closeBtn.title = "Close app (Alt+F4)";
    closeBtn.textContent = "×";

    const minBtn = document.createElement("button");
    minBtn.type = "button";
    minBtn.className = "window-control minimize";
    minBtn.setAttribute("aria-label", "Minimize");
    minBtn.title = "Minimise app (Alt+F9)";
    minBtn.textContent = "−";

    controls.append(closeBtn, minBtn);

    const titleSpan = document.createElement("span");
    titleSpan.textContent = titleText;

    const maxBtn = document.createElement("button");
    maxBtn.type = "button";
    maxBtn.className = "window-control maximize";
    maxBtn.setAttribute("aria-label", "Maximize");
    maxBtn.title = "Maximise or restore (Alt+F10)";
    maxBtn.textContent = "□";

    titlebar.append(controls, titleSpan, maxBtn);

    const contentEl = document.createElement("div");
    contentEl.className = "window-content";
    contentEl.tabIndex = -1;

    el.append(titlebar, contentEl);

    const cascadeOffset = (windowRecords.size % 5) * 22;
    if (cascadeOffset > 0) {
      el.style.left = `calc(50% + ${cascadeOffset}px)`;
      el.style.top = `calc(50% + ${cascadeOffset}px)`;
    }

    const record = {
      id: null,
      appId,
      el,
      titlebar,
      titleEl: titleSpan,
      contentEl,
      maxBtn,
      maximized: false,
      snapped: null,
      restoreRect: null,
      dragging: null
    };

    function clearWindowGeometry() {
      el.classList.remove("maximized", "snapped-left", "snapped-right");
      el.style.left = "";
      el.style.top = "";
      el.style.width = "";
      el.style.height = "";
      el.style.transform = "";
    }

    function saveRestoreRect() {
      const rect = el.getBoundingClientRect();
      record.restoreRect = { left: rect.left, top: rect.top, width: rect.width, height: rect.height };
    }

    function restoreGeometry() {
      clearWindowGeometry();
      if (record.restoreRect) {
        el.style.left = record.restoreRect.left + "px";
        el.style.top = record.restoreRect.top + "px";
        el.style.width = record.restoreRect.width + "px";
        el.style.height = record.restoreRect.height + "px";
        el.style.transform = "none";
      }
      record.maximized = false;
      record.snapped = null;
      maxBtn.setAttribute("aria-label", "Maximize");
    }

    function maximizeGeometry() {
      if (!record.maximized && !record.snapped) saveRestoreRect();
      clearWindowGeometry();
      el.classList.add("maximized");
      record.maximized = true;
      record.snapped = null;
      maxBtn.setAttribute("aria-label", "Restore");
    }

    function snapGeometry(side) {
      if (!record.maximized && !record.snapped) saveRestoreRect();
      clearWindowGeometry();
      el.classList.add(side === "left" ? "snapped-left" : "snapped-right");
      el.style.left = side === "left" ? "8px" : "calc(50vw + 4px)";
      el.style.top = "64px";
      el.style.width = "calc(50vw - 12px)";
      el.style.height = "calc(100vh - 148px)";
      el.style.transform = "none";
      record.snapped = side;
      record.maximized = false;
      maxBtn.setAttribute("aria-label", "Restore");
    }

    record.toggleMaximize = () => {
      if (record.maximized || record.snapped) restoreGeometry();
      else maximizeGeometry();
    };
    record.restoreGeometry = restoreGeometry;
    record.snapGeometry = snapGeometry;

    el.addEventListener("pointerdown", () => {
      if (record.id) window.NexusWindowManager.focus(record.id);
    });

    titlebar.addEventListener("pointerdown", event => {
      if (event.target.closest(".window-control") || event.button !== 0) return;
      if (record.maximized || record.snapped) {
        const old = record.restoreRect;
        clearWindowGeometry();
        record.maximized = false;
        record.snapped = null;
        maxBtn.setAttribute("aria-label", "Maximize");
        el.style.transform = "none";
        if (old) {
          const ratio = Math.min(1, Math.max(0.15, (event.clientX - old.left) / old.width));
          el.style.width = old.width + "px";
          el.style.height = old.height + "px";
          el.style.left = event.clientX - old.width * ratio + "px";
          el.style.top = Math.max(56, event.clientY - 18) + "px";
        }
      }
      const rect = el.getBoundingClientRect();
      record.dragging = {
        dx: event.clientX - rect.left,
        dy: event.clientY - rect.top,
        pointerId: event.pointerId
      };
      titlebar.setPointerCapture(event.pointerId);
    });

    titlebar.addEventListener("pointermove", event => {
      if (!record.dragging || record.dragging.pointerId !== event.pointerId) return;
      const w = el.offsetWidth;
      const h = el.offsetHeight;
      el.style.left = Math.max(0, Math.min(window.innerWidth - w, event.clientX - record.dragging.dx)) + "px";
      el.style.top = Math.max(56, Math.min(window.innerHeight - h - 65, event.clientY - record.dragging.dy)) + "px";
      el.style.transform = "none";
    });

    function finishDrag(event) {
      if (!record.dragging || record.dragging.pointerId !== event.pointerId) return;
      record.dragging = null;
      if (event.clientX <= 14) snapGeometry("left");
      else if (event.clientX >= window.innerWidth - 14) snapGeometry("right");
      else {
        el.classList.remove("snapped-left", "snapped-right");
        record.snapped = null;
      }
    }

    titlebar.addEventListener("pointerup", finishDrag);
    titlebar.addEventListener("pointercancel", event => {
      if (record.dragging?.pointerId === event.pointerId) record.dragging = null;
    });
    titlebar.addEventListener("dblclick", event => {
      if (!event.target.closest(".window-control")) record.toggleMaximize();
    });

    closeBtn.addEventListener("click", () => {
      if (record.id) window.NexusWindowManager.close(record.id);
    });
    minBtn.addEventListener("click", () => {
      if (record.id) {
        window.NexusWindowManager.minimize(record.id);
        focusAppButton(appId);
        notify("Window minimised");
      }
    });
    maxBtn.addEventListener("click", () => record.toggleMaximize());

    return record;
  }

  function openApp(appId) {
    if (!appNames[appId] || !window.NexusApplicationCatalog.isTargetInstalled(appId)) {
      notify("This app is not installed in the NEXUS launcher.");
      return;
    }

    closePanels();
    launcher.classList.add("hidden");

    const existing = window.NexusWindowManager.list().find(win => win.appId === appId);
    if (existing) {
      if (existing.state === "minimized") window.NexusWindowManager.restore(existing.id);
      else window.NexusWindowManager.focus(existing.id);
      windowRecords.get(existing.id)?.contentEl.focus();
      return;
    }

    const app = window.NexusAppRegistry.get(appId);
    if (!app) {
      notify("This app is not registered.");
      return;
    }

    const record = createWindowElement(appId, appNames[appId]);
    const renderErrorFallback = error => {
      console.error(`NEXUS app failed (${appId}):`, error);
      record.contentEl.replaceChildren();
      const box = document.createElement("section");
      box.className = "content-card";
      const heading = document.createElement("h2");
      heading.className = "content-title";
      heading.textContent = `${appNames[appId]} encountered an error`;
      const desc = document.createElement("p");
      desc.className = "content-sub";
      desc.textContent = error?.message
        ? `This application could not finish loading: ${error.message}`
        : "This application could not finish loading. Other NEXUS apps are unaffected.";
      const actions = document.createElement("div");
      actions.style.marginTop = "12px";
      const closeFallback = document.createElement("button");
      closeFallback.type = "button";
      closeFallback.className = "action-button";
      closeFallback.textContent = "Close window";
      closeFallback.addEventListener("click", () => {
        if (record.id) window.NexusWindowManager.close(record.id);
      });
      actions.append(closeFallback);
      box.append(heading, desc, actions);
      record.contentEl.append(box);
      notify(`${appNames[appId]} failed to load`);
    };

    let html = "";
    let renderFailed = null;
    try {
      html = app.render();
    } catch (error) {
      renderFailed = error;
    }

    if (!renderFailed) {
      record.contentEl.innerHTML = html;
    }
    windowLayer.append(record.el);

    const winId = window.NexusWindowManager.open(appId, appNames[appId], {
      onClose() {
        window.NexusAppRegistry.unmountRoot(record.contentEl);
        record.el.remove();
        windowRecords.delete(winId);
        syncDockIndicators();
        focusAppButton(appId);
      }
    });

    record.id = winId;
    record.el.id = winId;
    const titleId = winId + "-title";
    record.titleEl.id = titleId;
    record.el.setAttribute("aria-labelledby", titleId);
    windowRecords.set(winId, record);

    if (renderFailed) {
      renderErrorFallback(renderFailed);
    } else {
      try {
        window.NexusAppRegistry.mountApp(appId, record.contentEl, {
          notify,
          launchApp: openApp,
          desktopShell: window.NexusDesktopShell,
          windowId: winId
        });
      } catch (error) {
        renderErrorFallback(error);
      }
    }

    syncWindowElements();
    record.contentEl.focus();
  }

  $$("[data-app]:not(.app-item)").forEach(button => {
    button.addEventListener("click", () => {
      const appId = button.dataset.app;
      const existing = window.NexusWindowManager.list().find(win => win.appId === appId);
      if (button.classList.contains("dock-app") && existing) {
        if (existing.state === "minimized") window.NexusWindowManager.restore(existing.id);
        else window.NexusWindowManager.focus(existing.id);
        windowRecords.get(existing.id)?.contentEl.focus();
        closePanels();
        return;
      }
      openApp(appId);
    });
  });

  document.addEventListener("keydown", event => {
    const active = window.NexusWindowManager.getActive();
    if (!active || active.state === "minimized") return;
    const record = windowRecords.get(active.id);
    if (!record) return;

    if (event.altKey && !event.ctrlKey && !event.shiftKey && event.key === "F4") {
      event.preventDefault();
      window.NexusWindowManager.close(active.id);
      return;
    }
    if (event.altKey && !event.ctrlKey && !event.shiftKey && event.key === "F9") {
      event.preventDefault();
      window.NexusWindowManager.minimize(active.id);
      focusAppButton(active.appId);
      notify("Window minimised");
      return;
    }
    if (event.altKey && !event.ctrlKey && !event.shiftKey && event.key === "F10") {
      event.preventDefault();
      record.toggleMaximize();
      return;
    }
    if (event.ctrlKey && event.altKey && !event.shiftKey && event.key === "ArrowLeft") {
      event.preventDefault();
      record.snapGeometry("left");
      return;
    }
    if (event.ctrlKey && event.altKey && !event.shiftKey && event.key === "ArrowRight") {
      event.preventDefault();
      record.snapGeometry("right");
      return;
    }
    if (event.ctrlKey && event.altKey && !event.shiftKey && event.key === "ArrowDown") {
      event.preventDefault();
      record.restoreGeometry();
    }
  });

  $("#appSearch").addEventListener("input", renderLauncher);
  $("#appSearch").addEventListener("keydown", event => {
    const items = Array.from(document.querySelectorAll(".app-item")).filter(item => item.style.display !== "none");
    if (event.key === "Enter" && items.length) {
      event.preventDefault();
      items[0].click();
    } else if (event.key === "ArrowDown" && items.length) {
      event.preventDefault();
      items[0].focus();
    }
  });

  $("#appGrid").addEventListener("keydown", event => {
    const items = Array.from(document.querySelectorAll(".app-item")).filter(item => item.style.display !== "none");
    const index = items.indexOf(event.target.closest(".app-item"));
    if (index < 0 || !items.length) return;
    let next = index;
    if (event.key === "ArrowDown" || event.key === "ArrowRight") next = (index + 1) % items.length;
    else if (event.key === "ArrowUp" || event.key === "ArrowLeft") next = (index - 1 + items.length) % items.length;
    else if (event.key === "Home") next = 0;
    else if (event.key === "End") next = items.length - 1;
    else return;
    event.preventDefault();
    items[next].focus();
  });

  $("#appGrid").addEventListener("click", event => {
    const item = event.target.closest(".app-item[data-app]");
    if (item) openApp(item.dataset.app);
  });

  window.NexusApplicationCatalog.subscribe(() => {
    renderLauncher();
    window.NexusWindowManager.list().forEach(win => {
      if (!window.NexusApplicationCatalog.isTargetInstalled(win.appId)) {
        window.NexusWindowManager.close(win.id);
      }
    });
  });

  window.addEventListener("resize", () => {
    const maxW = Math.max(320, windowLayer.clientWidth || window.innerWidth || 0);
    const maxH = Math.max(240, windowLayer.clientHeight || window.innerHeight || 0);
    windowRecords.forEach(record => {
      if (!record.el || record.el.classList.contains("maximized")) return;
      const curLeft = parseFloat(record.el.style.left);
      const curTop = parseFloat(record.el.style.top);
      const curWidth = record.el.offsetWidth || parseFloat(record.el.style.width) || 320;
      const curHeight = record.el.offsetHeight || parseFloat(record.el.style.height) || 240;
      if (Number.isFinite(curLeft)) {
        const clampedLeft = Math.max(8, Math.min(curLeft, Math.max(8, maxW - Math.min(curWidth, maxW) - 8)));
        record.el.style.left = `${clampedLeft}px`;
      }
      if (Number.isFinite(curTop)) {
        const clampedTop = Math.max(8, Math.min(curTop, Math.max(8, maxH - Math.min(curHeight, maxH) - 8)));
        record.el.style.top = `${clampedTop}px`;
      }
    });
  });

  renderLauncher();
  if (readStorage("nexus-wallpaper") === "custom") {
    restoreCustomWallpaperAtStartup();
  } else {
    setDesktopWallpaper(readStorage("nexus-wallpaper") || "alpine", false);
  }
  const savedAccent = readStorage("nexus-accent");
  document.documentElement.style.setProperty("--accent", savedAccent || "#ffad7a");
  const savedBlur = readStorage("nexus-blur");
  document.documentElement.style.setProperty("--blur", (savedBlur || "18") + "px");
  if (readStorage("nexus-reduced-motion") === "true") {
    document.body.classList.add("reduced-motion");
  }
  const savedTheme = readStorage("nexus-theme") || "dark";
  const systemPrefersLight = window.matchMedia && window.matchMedia("(prefers-color-scheme: light)").matches;
  desktop.classList.toggle("theme-light", savedTheme === "light" || (savedTheme === "system" && systemPrefersLight));
  const savedPreset = readStorage("nexus-theme-preset");
  if (savedPreset) setThemePreset(savedPreset, false);
  const savedFit = readStorage("nexus-wallpaper-fit");
  if (savedFit) setWallpaperFit(savedFit, false);
  const savedEffect = readStorage("nexus-effect-level");
  if (savedEffect) setEffectLevel(savedEffect, false);
  setDockPreferences({
    position: readStorage("nexus-dock-position") || "bottom",
    size: readStorage("nexus-dock-size") || "43",
    gap: readStorage("nexus-dock-gap") || "8",
    autoHide: readStorage("nexus-dock-autohide") === "true",
    style: readStorage("nexus-dock-style") || "glass",
    showIndicators: readStorage("nexus-dock-indicators") !== "false"
  }, false);
  setDesktopPreferences({
    showShortcuts: readStorage("nexus-desktop-shortcuts") !== "false",
    clock24h: readStorage("nexus-clock-24h") === "true"
  }, false);
})();
