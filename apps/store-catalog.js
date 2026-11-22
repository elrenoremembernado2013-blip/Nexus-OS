(() => {
  const stateKey = "nexus-store-state-v1";
  const categories = [
    "Productivity",
    "Games",
    "Utilities",
    "Development",
    "Education",
    "Multimedia",
    "Internet",
    "Graphics & Design",
    "System Tools",
    "Security",
    "Personalization",
  ];

  const applications = [
    {
      id: "files",
      slug: "nexus-files",
      name: "NEXUS File Manager",
      launcherName: "File Manager",
      description: "Browse a folder you explicitly grant, preview text and images, and manage its contents where your browser supports it.",
      developer: "NEXUS",
      category: "System Tools",
      type: "System application",
      icon: "▤",
      version: "0.2",
      size: "Included with the desktop",
      compatibility: "Browser-granted file access; support varies by browser.",
      rating: null,
      tags: ["files", "folders", "storage", "nexus original"],
      permissions: ["Access only to a folder you explicitly choose."],
      releaseNotes: "Folder access is permission-scoped. Host-wide storage and removable media are not available.",
      installMode: "system",
      installedByDefault: true,
      launchTarget: "files",
      collectionIds: ["desktop-essentials", "nexus-originals"],
      trust: "NEXUS Original · not independently security reviewed",
      capability: "functional",
    },
    {
      id: "settings",
      slug: "nexus-settings",
      name: "NEXUS Settings",
      launcherName: "Settings",
      description: "Personalize the desktop with local theme, wallpaper, accent and accessibility preferences.",
      developer: "NEXUS",
      category: "Personalization",
      type: "System application",
      icon: "⚙",
      version: "0.2",
      size: "Included with the desktop",
      compatibility: "Browser prototype; device settings require native Linux services.",
      rating: null,
      tags: ["settings", "appearance", "accessibility", "nexus original"],
      permissions: ["Stores appearance preferences in this browser."],
      releaseNotes: "Display, sound, network, accounts and system update controls are not connected.",
      installMode: "system",
      installedByDefault: true,
      launchTarget: "settings",
      collectionIds: ["desktop-essentials", "nexus-originals"],
      trust: "NEXUS Original · not independently security reviewed",
      capability: "functional",
    },
    {
      id: "software",
      slug: "nexus-store",
      name: "NEXUS Store",
      launcherName: "Software Centre",
      description: "Explore the NEXUS app catalogue, manage supported launcher apps, and review their capabilities.",
      developer: "NEXUS",
      category: "System Tools",
      type: "System application",
      icon: "◈",
      version: "0.3",
      size: "Included with the desktop",
      compatibility: "Browser prototype; native package management is not connected.",
      rating: null,
      tags: ["store", "marketplace", "catalogue", "nexus original"],
      permissions: ["Stores the wishlist and launcher registration in this browser."],
      releaseNotes: "Only the bundled NEXUS Calendar can currently be added or removed through the Store.",
      installMode: "system",
      installedByDefault: true,
      launchTarget: "software",
      collectionIds: ["desktop-essentials", "nexus-originals"],
      trust: "NEXUS Original · not independently security reviewed",
      capability: "functional",
    },
    {
      id: "monitor",
      slug: "nexus-system-monitor",
      name: "NEXUS System Monitor",
      launcherName: "System Monitor",
      description: "A clear home for system resources. This prototype does not read host telemetry.",
      developer: "NEXUS",
      category: "System Tools",
      type: "System application",
      icon: "▥",
      version: "0.2",
      size: "Included with the desktop",
      compatibility: "Native Linux telemetry service required for live measurements.",
      rating: null,
      tags: ["monitor", "cpu", "memory", "processes", "nexus original"],
      permissions: ["No host metrics are read by this prototype."],
      releaseNotes: "CPU, memory, storage, process and network data are intentionally unavailable.",
      installMode: "system",
      installedByDefault: true,
      launchTarget: "monitor",
      collectionIds: ["desktop-essentials", "nexus-originals"],
      trust: "NEXUS Original · not independently security reviewed",
      capability: "preview",
    },
    {
      id: "browser",
      slug: "nexus-browser",
      name: "NEXUS Browser",
      launcherName: "Browser",
      description: "Open validated HTTP and HTTPS links in your system browser from the NEXUS desktop.",
      developer: "NEXUS",
      category: "Internet",
      type: "Desktop utility",
      icon: "◉",
      version: "0.2",
      size: "Included with the desktop",
      compatibility: "Uses the browser configured by the host operating system.",
      rating: null,
      tags: ["web", "internet", "links", "nexus original"],
      permissions: ["Opens the address you submit in a new browser tab."],
      releaseNotes: "This is a safe link-opening interface, not a full web browser engine.",
      installMode: "system",
      installedByDefault: true,
      launchTarget: "browser",
      collectionIds: ["desktop-essentials", "nexus-originals"],
      trust: "NEXUS Original · not independently security reviewed",
      capability: "preview",
    },
    {
      id: "notes",
      slug: "nexus-notes",
      name: "NEXUS Notes",
      launcherName: "Notes",
      description: "Write a quick note with automatic saving to this browser's local storage.",
      developer: "NEXUS",
      category: "Productivity",
      type: "Desktop application",
      icon: "✎",
      version: "0.2",
      size: "Included with the desktop",
      compatibility: "Notes are local to this browser profile.",
      rating: null,
      tags: ["writing", "notes", "productivity", "nexus original"],
      permissions: ["Stores note text in this browser's local storage."],
      releaseNotes: "Notes are not uploaded or synchronized between devices.",
      installMode: "system",
      installedByDefault: true,
      launchTarget: "notes",
      collectionIds: ["desktop-essentials", "nexus-originals"],
      trust: "NEXUS Original · not independently security reviewed",
      capability: "functional",
    },
    {
      id: "calculator",
      slug: "nexus-calculator",
      name: "NEXUS Calculator",
      launcherName: "Calculator",
      description: "Evaluate basic arithmetic with a hand-written parser; user input is never executed as code.",
      developer: "NEXUS",
      category: "Utilities",
      type: "Desktop application",
      icon: "＋",
      version: "0.2",
      size: "Included with the desktop",
      compatibility: "Available in the NEXUS browser prototype.",
      rating: null,
      tags: ["math", "arithmetic", "calculator", "nexus original"],
      permissions: ["No special permissions."],
      releaseNotes: "Scientific functions and calculation history are not included yet.",
      installMode: "system",
      installedByDefault: true,
      launchTarget: "calculator",
      collectionIds: ["desktop-essentials", "nexus-originals"],
      trust: "NEXUS Original · not independently security reviewed",
      capability: "functional",
    },
    {
      id: "terminal",
      slug: "nexus-terminal",
      name: "NEXUS Terminal",
      launcherName: "Terminal",
      description: "Try a small set of safe demonstration commands. It cannot run commands on your computer.",
      developer: "NEXUS",
      category: "Development",
      type: "Desktop application",
      icon: "⌘",
      version: "0.2",
      size: "Included with the desktop",
      compatibility: "Native terminal integration is not connected.",
      rating: null,
      tags: ["terminal", "developer", "command line", "nexus original"],
      permissions: ["No shell access; only fixed demonstration responses are available."],
      releaseNotes: "This is not a system shell and does not execute arbitrary input.",
      installMode: "system",
      installedByDefault: true,
      launchTarget: "terminal",
      collectionIds: ["developer-tools", "nexus-originals"],
      trust: "NEXUS Original · not independently security reviewed",
      capability: "preview",
    },
    {
      id: "gaming",
      slug: "nexus-games-hub",
      name: "NEXUS Games Hub",
      launcherName: "Gaming Hub",
      description: "A preview of the planned gaming space. It cannot install or launch games yet.",
      developer: "NEXUS",
      category: "Games",
      type: "Desktop preview",
      icon: "🎮",
      version: "0.2",
      size: "Included with the desktop",
      compatibility: "Steam, Proton and game-controller services are not connected.",
      rating: null,
      tags: ["games", "gaming", "steam", "nexus original"],
      permissions: ["No game files or launch services are accessed."],
      releaseNotes: "Game discovery and native game launching are planned.",
      installMode: "system",
      installedByDefault: true,
      launchTarget: "gaming",
      collectionIds: ["games-and-play", "nexus-originals"],
      trust: "NEXUS Original · not independently security reviewed",
      capability: "preview",
    },
    {
      id: "calendar",
      slug: "nexus-calendar",
      name: "NEXUS Calendar",
      launcherName: "Calendar",
      description: "A lightweight month view for personal events, stored only in this browser.",
      developer: "NEXUS",
      category: "Productivity",
      type: "Bundled NEXUS application",
      icon: "▦",
      version: "0.1",
      size: "Bundled · no separate download",
      compatibility: "Runs in this browser prototype; reminders and account sync are unavailable.",
      rating: null,
      tags: ["calendar", "events", "planning", "nexus original"],
      permissions: ["Stores event titles and dates in this browser's local storage."],
      releaseNotes: "Month navigation, event creation and deletion work locally. No reminders are sent.",
      installMode: "internal",
      installedByDefault: false,
      launchTarget: "calendar",
      collectionIds: ["desktop-essentials", "nexus-originals"],
      trust: "NEXUS Original · not independently security reviewed",
      capability: "functional",
    },
    {
      id: "text-editor",
      slug: "nexus-text-editor",
      name: "NEXUS Text Editor",
      description: "A dedicated text and code editor is planned; NEXUS Notes is currently available for quick writing.",
      developer: "NEXUS",
      category: "Productivity",
      type: "Planned application",
      icon: "▤",
      version: null,
      size: "Not packaged",
      compatibility: "Not available in this prototype.",
      rating: null,
      tags: ["editor", "writing", "code", "nexus original"],
      permissions: ["Not available; no permissions are requested."],
      releaseNotes: "File open/save and syntax highlighting are future work.",
      installMode: "unavailable",
      installedByDefault: false,
      launchTarget: null,
      collectionIds: ["nexus-originals", "developer-tools"],
      trust: "Planned · not reviewed",
      capability: "planned",
    },
    {
      id: "media-player",
      slug: "nexus-media-player",
      name: "NEXUS Media Player",
      description: "Local audio and video playback with playlists is planned for a later milestone.",
      developer: "NEXUS",
      category: "Multimedia",
      type: "Planned application",
      icon: "▶",
      version: null,
      size: "Not packaged",
      compatibility: "Not available in this prototype.",
      rating: null,
      tags: ["media", "audio", "video", "nexus original"],
      permissions: ["Not available; no media is accessed."],
      releaseNotes: "Playback formats and playlist support are not implemented.",
      installMode: "unavailable",
      installedByDefault: false,
      launchTarget: null,
      collectionIds: ["nexus-originals"],
      trust: "Planned · not reviewed",
      capability: "planned",
    },
    {
      id: "screenshot",
      slug: "nexus-screenshot",
      name: "NEXUS Screenshot",
      description: "Screen and region capture requires a native desktop capture service.",
      developer: "NEXUS",
      category: "Utilities",
      type: "Planned application",
      icon: "▧",
      version: null,
      size: "Not packaged",
      compatibility: "Not available in this prototype.",
      rating: null,
      tags: ["screenshot", "capture", "nexus original"],
      permissions: ["Screen capture is not available."],
      releaseNotes: "No screenshots are captured by this listing.",
      installMode: "unavailable",
      installedByDefault: false,
      launchTarget: null,
      collectionIds: ["nexus-originals"],
      trust: "Planned · not reviewed",
      capability: "planned",
    },
    {
      id: "steam",
      slug: "steam",
      name: "Steam",
      description: "A third-party game platform. NEXUS cannot install or launch it from this browser prototype.",
      developer: "Valve",
      category: "Games",
      type: "External application",
      icon: "S",
      version: null,
      size: "Not available",
      compatibility: "Native Linux packaging and gaming support have not been tested for NEXUS.",
      rating: null,
      tags: ["games", "store", "valve", "proton"],
      permissions: ["Not available; no package or account access is requested."],
      releaseNotes: "A listing is not an endorsement, compatibility claim or security review.",
      installMode: "unavailable",
      installedByDefault: false,
      launchTarget: null,
      collectionIds: ["games-and-play"],
      trust: "External · not reviewed by NEXUS",
      capability: "unavailable",
    },
    {
      id: "developer-hub",
      slug: "nexus-developer-hub",
      name: "NEXUS Developer Hub",
      description: "App submissions, publisher accounts and release management need a hosted developer service.",
      developer: "NEXUS",
      category: "Development",
      type: "Planned service",
      icon: "{ }",
      version: null,
      size: "Not available",
      compatibility: "Submission and account services are not implemented.",
      rating: null,
      tags: ["developer", "publisher", "submission", "nexus original"],
      permissions: ["No account or submission data is collected."],
      releaseNotes: "The Store does not accept uploads or app submissions.",
      installMode: "unavailable",
      installedByDefault: false,
      launchTarget: null,
      collectionIds: ["developer-tools"],
      trust: "Planned · not reviewed",
      capability: "planned",
    },
  ];

  const collections = [
    { id: "desktop-essentials", name: "Desktop essentials", description: "Tools included with this NEXUS desktop prototype." },
    { id: "nexus-originals", name: "NEXUS Originals", description: "First-party concepts and apps. Original does not mean independently security reviewed." },
    { id: "developer-tools", name: "Developer tools", description: "Current safe previews and planned tools for builders." },
    { id: "games-and-play", name: "Games & play", description: "Gaming concepts and external platforms, with compatibility stated plainly." },
  ];

  function clone(value) {
    return JSON.parse(JSON.stringify(value));
  }

  function makeStorageError(message) {
    const error = new Error(message);
    error.name = "StoreStateError";
    return error;
  }

  function readPersistedState() {
    try {
      const raw = window.localStorage.getItem(stateKey);
      if (!raw) return { version: 1, installed: [], wishlist: [], operations: [] };
      const state = JSON.parse(raw);
      if (state?.version !== 1 || !Array.isArray(state.installed) || !Array.isArray(state.wishlist) || !Array.isArray(state.operations)) {
        throw new Error("Saved Store data has an unsupported format.");
      }
      return state;
    } catch (error) {
      return { error: makeStorageError(`Could not read saved Store data: ${error.message}`), version: 1, installed: [], wishlist: [], operations: [] };
    }
  }

  let state = readPersistedState();
  const listeners = new Set();
  const byId = new Map(applications.map(application => [application.id, application]));
  const byTarget = new Map(applications.filter(application => application.launchTarget).map(application => [application.launchTarget, application]));

  function emit() {
    listeners.forEach(listener => listener());
  }

  function persist(nextState) {
    if (state.error) throw state.error;
    try {
      window.localStorage.setItem(stateKey, JSON.stringify(nextState));
    } catch (error) {
      throw makeStorageError(`Could not save Store changes: ${error.message}`);
    }
    state = nextState;
    emit();
  }

  function isInstalled(applicationOrId) {
    const application = typeof applicationOrId === "string" ? byId.get(applicationOrId) : applicationOrId;
    return Boolean(application && (
      application.installedByDefault ||
      (application.installMode === "internal" && state.installed.includes(application.id))
    ));
  }

  function getAll() {
    return clone(applications);
  }

  function getInstalled() {
    return applications.filter(isInstalled).map(clone);
  }

  function getLauncherApps() {
    return applications.filter(application => application.launchTarget && isInstalled(application)).map(clone);
  }

  function isTargetInstalled(target) {
    return isInstalled(byTarget.get(target));
  }

  function install(id) {
    const application = byId.get(id);
    if (!application) throw new RangeError(`Unknown application: ${id}`);
    if (application.installMode !== "internal" || !application.launchTarget) {
      throw new Error(`${application.name} cannot be installed by this prototype.`);
    }
    if (isInstalled(application)) throw new Error(`${application.name} is already in your launcher.`);
    const nextState = {
      ...state,
      installed: [...state.installed, id],
      operations: [{
        id: `${Date.now()}-${id}`,
        applicationId: id,
        kind: "add",
        status: "complete",
        detail: "Registered the bundled app in the NEXUS launcher.",
        completedAt: new Date().toISOString(),
      }, ...state.operations].slice(0, 30),
    };
    persist(nextState);
    return clone(application);
  }

  function remove(id) {
    const application = byId.get(id);
    if (!application) throw new RangeError(`Unknown application: ${id}`);
    if (application.installMode !== "internal") throw new Error(`${application.name} is part of the desktop and cannot be removed here.`);
    if (!isInstalled(application)) throw new Error(`${application.name} is not in your launcher.`);
    const nextState = {
      ...state,
      installed: state.installed.filter(installedId => installedId !== id),
      operations: [{
        id: `${Date.now()}-${id}`,
        applicationId: id,
        kind: "remove",
        status: "complete",
        detail: "Removed the app from the NEXUS launcher. Its local event data is retained.",
        completedAt: new Date().toISOString(),
      }, ...state.operations].slice(0, 30),
    };
    persist(nextState);
    return clone(application);
  }

  function isWishlisted(id) {
    return state.wishlist.includes(id);
  }

  function toggleWishlist(id) {
    if (!byId.has(id)) throw new RangeError(`Unknown application: ${id}`);
    const wishlisted = isWishlisted(id);
    const nextState = {
      ...state,
      wishlist: wishlisted ? state.wishlist.filter(itemId => itemId !== id) : [...state.wishlist, id],
    };
    persist(nextState);
    return !wishlisted;
  }

  function getOperations() {
    return clone(state.operations);
  }

  function getStorageError() {
    return state.error ? state.error.message : "";
  }

  window.NexusApplicationCatalog = Object.freeze({
    categories: Object.freeze([...categories]),
    collections: Object.freeze(clone(collections)),
    getAll,
    getInstalled,
    getLauncherApps,
    getById: id => clone(byId.get(id) || null),
    getByTarget: target => clone(byTarget.get(target) || null),
    isInstalled,
    isTargetInstalled,
    canInstall: id => byId.get(id)?.installMode === "internal" && !isInstalled(id),
    canRemove: id => byId.get(id)?.installMode === "internal" && isInstalled(id),
    install,
    remove,
    isWishlisted,
    toggleWishlist,
    getOperations,
    getStorageError,
    subscribe(listener) {
      if (typeof listener !== "function") throw new TypeError("Store subscriber must be a function.");
      listeners.add(listener);
      return () => listeners.delete(listener);
    },
  });

  window.addEventListener("storage", event => {
    if (event.key !== stateKey) return;
    state = readPersistedState();
    emit();
  });
})();
