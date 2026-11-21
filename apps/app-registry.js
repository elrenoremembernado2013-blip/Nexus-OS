(() => {
  const apps = new Map();
  const settingsEnhancements = [];

  window.NexusAppRegistry = {
    register(app) {
      if (!app || !/^[a-z][a-z0-9-]*$/.test(app.id) || !app.name || !app.render || !app.mount) {
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
      if (!app) return false;
      if (typeof app.cleanup === "function") app.cleanup();
      const cleanup = app.mount(root, context);
      app.cleanup = typeof cleanup === "function" ? cleanup : null;
      return true;
    },
    unmountApp(id) {
      const app = apps.get(id);
      if (app && typeof app.cleanup === "function") {
        app.cleanup();
        app.cleanup = null;
      }
    },
    registerSettingsEnhancement(enhancement) {
      if (typeof enhancement !== "function") throw new TypeError("Settings enhancement must be a function.");
      settingsEnhancements.push(enhancement);
    },
    enhanceSettings(root) {
      settingsEnhancements.forEach(enhancement => enhancement(root));
    }
  };
})();
