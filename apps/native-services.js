(() => {
  const nativeServices = new Map();
  const listeners = new Set();
  const knownServiceIds = new Set([
    "display",
    "sound",
    "network",
    "bluetooth",
    "power",
    "accounts",
    "privacy-security",
    "packages",
    "telemetry",
    "notifications",
    "files",
    "terminal",
    "gaming",
    "hardware",
    "performance",
    "quantum",
    "compatibility",
    "installer",
    "control-centre",
    "personalisation",
  ]);

  class NativeIntegrationUnavailableError extends Error {
    constructor(serviceId) {
      super(`Native service unavailable: ${serviceId}`);
      this.name = "NativeIntegrationUnavailableError";
      this.serviceId = serviceId;
      this.code = "NATIVE_SERVICE_UNAVAILABLE";
    }
  }

  function notifyListeners(serviceId) {
    listeners.forEach(fn => {
      try {
        fn(serviceId);
      } catch (err) {
        console.error("NexusNativeServices listener error:", err);
      }
    });
  }

  window.NexusNativeServices = {
    register(serviceId, adapter) {
      if (!knownServiceIds.has(serviceId)) throw new RangeError(`Unknown native service: ${serviceId}`);
      if (!adapter || typeof adapter !== "object") throw new TypeError("A native service adapter must be an object.");
      if (nativeServices.has(serviceId)) throw new Error(`Native service already registered: ${serviceId}`);
      nativeServices.set(serviceId, Object.freeze({ ...adapter }));
      notifyListeners(serviceId);
      return true;
    },
    unregister(serviceId) {
      if (!knownServiceIds.has(serviceId)) throw new RangeError(`Unknown native service: ${serviceId}`);
      nativeServices.delete(serviceId);
      notifyListeners(serviceId);
      return true;
    },
    status(serviceId) {
      if (!knownServiceIds.has(serviceId)) throw new RangeError(`Unknown native service: ${serviceId}`);
      return {
        serviceId,
        available: nativeServices.has(serviceId),
      };
    },
    call(serviceId, methodName, ...args) {
      const adapter = nativeServices.get(serviceId);
      if (!adapter) throw new NativeIntegrationUnavailableError(serviceId);
      const method = adapter[methodName];
      if (typeof method !== "function") throw new TypeError(`Native service ${serviceId} does not provide ${methodName}.`);
      return method(...args);
    },
    subscribe(listener) {
      if (typeof listener !== "function") return () => {};
      listeners.add(listener);
      return () => listeners.delete(listener);
    },
  };

  window.NativeIntegrationUnavailableError = NativeIntegrationUnavailableError;

  // Optional loopback bridge connector: only activates when a local desktop host injects window.__NEXUS_BRIDGE__ = { url, token }.
  if (typeof window !== "undefined" && window.__NEXUS_BRIDGE__?.url && window.__NEXUS_BRIDGE__?.token && typeof fetch === "function") {
    const { url, token } = window.__NEXUS_BRIDGE__;
    const req = async (path, method = "GET", body = null) => {
      const res = await fetch(`${url}${path}`, {
        method,
        headers: {
          "X-Nexus-Token": token,
          ...(body ? { "Content-Type": "application/json" } : {}),
        },
        ...(body ? { body: JSON.stringify(body) } : {}),
      });
      const data = await res.json().catch(() => ({}));
      if (!res.ok) throw new Error(data.error || data.message || `Bridge error (${res.status})`);
      return data;
    };

    const registerSafe = (id, adapter) => {
      try {
        if (!window.NexusNativeServices.status(id).available) {
          window.NexusNativeServices.register(id, adapter);
        }
      } catch (err) {
        console.warn(`NEXUS bridge registration skipped for ${id}:`, err);
      }
    };

    registerSafe("control-centre", {
      status: () => req("/api/control-centre"),
      action: (type, value) => req("/api/control-centre/action", "POST", { type, value }),
    });
    registerSafe("personalisation", {
      listWallpapers: () => req("/api/wallpapers"),
      applyWallpaper: opts => req("/api/wallpapers/apply", "POST", opts),
      applyTheme: opts => req("/api/personalisation/apply", "POST", opts),
    });
    registerSafe("packages", {
      sources: () => req("/api/store/sources"),
      installed: () => req("/api/store/installed"),
      info: (source, pkg) => req(`/api/store/info?source=${encodeURIComponent(source)}&pkg=${encodeURIComponent(pkg)}`),
      checkUpdates: async () => {
        const res = await req("/api/store/updates");
        const apt = (res.apt || []).map(u => ({ id: u.id, name: u.id, source: "apt", currentVersion: "installed", newVersion: u.detail || "latest" }));
        const fp = (res.flatpak || []).map(u => ({ id: u.id, name: u.id, source: "flatpak", currentVersion: "installed", newVersion: u.version || "latest" }));
        return [...apt, ...fp];
      },
      search: async query => {
        const res = await req(`/api/store/search?q=${encodeURIComponent(query)}`);
        return (res.results || []).map(r => ({
          id: r.id,
          name: r.name || r.id,
          description: r.summary || r.id,
          source: r.source || "apt",
          installed: Boolean(r.installed),
          protected: false,
        }));
      },
      install: (source, pkg) => req("/api/store/install", "POST", { source, pkg }),
      remove: (source, pkg) => req("/api/store/remove", "POST", { source, pkg }),
    });
    registerSafe("privacy-security", {
      overview: () => req("/api/security/status"),
      openControl: () => req("/api/tools/launch", "POST", { category: "privacy-security" }),
      setFirewall: enable => req("/api/security/firewall", "POST", { action: enable ? "enable" : "disable" }),
      permissions: appId => req(`/api/security/permissions?appId=${encodeURIComponent(appId)}`),
      revokePermission: (appId, flag) => req("/api/security/flatpak-revoke", "POST", { appId, flag }),
      resetPermissions: appId => req("/api/security/flatpak-reset", "POST", { appId }),
    });
    registerSafe("gaming", {
      status: () => req("/api/gaming/status"),
      setGamingMode: enable => req("/api/gaming/mode", "POST", { action: enable ? "enable" : "disable" }),
      launchSteam: () => req("/api/tools/launch", "POST", { category: "gaming" }),
      installSteam: () => req("/api/store/install", "POST", { source: "apt", pkg: "steam-installer" }),
    });
    registerSafe("installer", {
      preflight: () => req("/api/installer/preflight"),
      launch: () => req("/api/tools/launch", "POST", { category: "installer" }),
    });
    registerSafe("hardware", {
      inventory: () => req("/api/hardware/inventory"),
      diagnostics: () => req("/api/hardware/diagnostics"),
      recoveryDiagnose: () => req("/api/recovery/diagnose"),
    });
    registerSafe("telemetry", {
      snapshot: () => req("/api/telemetry"),
    });
    registerSafe("performance", {
      overview: () => req("/api/performance/overview"),
      setLowResource: enable => req("/api/performance/low-resource", "POST", { action: enable ? "enable" : "disable" }),
      setStartup: (id, enable) => req("/api/performance/startup", "POST", { id, action: enable ? "enable" : "disable" }),
      cleanup: target => req("/api/performance/cleanup", "POST", { target, confirm: true }),
    });
    registerSafe("files", {
      list: path => req(`/api/files/list?path=${encodeURIComponent(path || "")}`),
      preview: path => req(`/api/files/preview?path=${encodeURIComponent(path || "")}`),
      mkdir: (path, name) => req("/api/files/mkdir", "POST", { path, name }),
      touch: (path, name) => req("/api/files/touch", "POST", { path, name }),
      rename: (path, newName) => req("/api/files/rename", "POST", { path, newName }),
      remove: path => req("/api/files/delete", "POST", { path }),
      openControl: () => req("/api/tools/launch", "POST", { category: "files" }),
    });
    registerSafe("quantum", {
      loadNotes: () => req("/api/quantum/notes"),
      saveNotes: notes => req("/api/quantum/notes", "POST", { notes }),
    });
    registerSafe("compatibility", {
      status: () => req("/api/compat/status"),
      catalog: () => req("/api/compat/catalog"),
      inspect: filePath => req(`/api/compat/inspect?path=${encodeURIComponent(filePath)}`),
      createPrefix: name => req("/api/compat/prefix/create", "POST", { name }),
      installRuntime: (runtime, forceLowRam = false) => req("/api/compat/runtime/install", "POST", { runtime, confirm: true, forceLowRam: Boolean(forceLowRam) }),
      launchFile: filePath => req("/api/compat/launch", "POST", { path: filePath, confirm: true }),
    });
    registerSafe("terminal", {
      openSession: opts => req("/api/terminal/open", "POST", opts || {}),
      read: sessionId => req(`/api/terminal/read?sessionId=${encodeURIComponent(sessionId)}`),
      write: (sessionId, data) => req("/api/terminal/write", "POST", { sessionId, data }),
      resize: (sessionId, cols, rows) => req("/api/terminal/resize", "POST", { sessionId, cols, rows }),
      interrupt: sessionId => req("/api/terminal/interrupt", "POST", { sessionId }),
      closeSession: sessionId => req("/api/terminal/close", "POST", { sessionId }),
    });
    for (const cat of ["display", "sound", "network", "bluetooth", "power", "accounts"]) {
      registerSafe(cat, {
        openControl: () => req("/api/tools/launch", "POST", { category: cat }),
      });
    }
  }
})();
