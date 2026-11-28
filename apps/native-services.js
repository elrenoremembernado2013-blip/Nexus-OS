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
      if (!res.ok) throw new Error(data.error || `Bridge error (${res.status})`);
      return data;
    };

    try {
      window.NexusNativeServices.register("control-centre", {
        status: () => req("/api/control-centre"),
        action: (type, value) => req("/api/control-centre/action", "POST", { type, value }),
      });
      window.NexusNativeServices.register("personalisation", {
        listWallpapers: () => req("/api/wallpapers"),
        applyWallpaper: (opts) => req("/api/wallpapers/apply", "POST", opts),
        applyTheme: (opts) => req("/api/personalisation/apply", "POST", opts),
      });
    } catch (err) {
      console.warn("NEXUS bridge registration skipped:", err);
    }
  }
})();
