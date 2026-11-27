(() => {
  const apps = new Map();
  const mountedRoots = new Map();
  const settingsEnhancements = [];

  function reportAppError(message, id, error) {
    if (typeof console !== "undefined" && typeof console.error === "function") {
      console.error(message, id, error);
    }
  }

  function cleanupRoot(root) {
    const instance = mountedRoots.get(root);
    if (!instance) return false;
    mountedRoots.delete(root);
    if (typeof instance.cleanup === "function") {
      try {
        instance.cleanup();
      } catch (error) {
        // A broken app cleanup must not prevent other windows from closing.
        reportAppError("NEXUS app cleanup failed:", instance.id, error);
      }
    }
    return true;
  }

  window.NexusAppRegistry = {
    register(app) {
      if (!app || typeof app.id !== "string" || !/^[a-z][a-z0-9-]*$/.test(app.id) ||
          typeof app.name !== "string" || !app.name.trim() ||
          typeof app.render !== "function" || typeof app.mount !== "function") {
        throw new TypeError("A NEXUS app requires an id, name, render and mount function.");
      }
      if (apps.has(app.id)) throw new Error("NEXUS app already registered: " + app.id);
      apps.set(app.id, app);
    },
    get(id) {
      return apps.get(id);
    },
    list() {
      return [...apps.values()];
    },
    mountApp(id, root, context) {
      const app = apps.get(id);
      if (!app || !root) return false;
      cleanupRoot(root);
      const cleanup = app.mount(root, context);
      mountedRoots.set(root, { id, cleanup: typeof cleanup === "function" ? cleanup : null });
      return true;
    },
    unmountRoot(root) {
      return cleanupRoot(root);
    },
    unmountApp(id) {
      for (const [root, instance] of mountedRoots) {
        if (instance.id === id) cleanupRoot(root);
      }
    },
    registerSettingsEnhancement(enhancement) {
      if (typeof enhancement !== "function") throw new TypeError("Settings enhancement must be a function.");
      settingsEnhancements.push(enhancement);
    },
    enhanceSettings(root) {
      settingsEnhancements.forEach((enhancement, index) => {
        try {
          enhancement(root);
        } catch (error) {
          // A broken settings extension must not block the remaining settings UI.
          reportAppError("NEXUS settings enhancement failed:", index, error);
        }
      });
    }
  };
})();