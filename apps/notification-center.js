(() => {
  const STORAGE_KEY = "nexus-notification-center-v1";
  const MAX_ITEMS = 50;
  const allowedCategories = new Set(["system","apps","security","updates","gaming"]);
  const listeners = new Set();

  function readItems() {
    try {
      const parsed = JSON.parse(window.localStorage.getItem(STORAGE_KEY) || "[]");
      if (!Array.isArray(parsed)) return [];
      return parsed.filter(item => item && typeof item.id === "string" &&
        typeof item.title === "string" && typeof item.body === "string" &&
        typeof item.timestamp === "number" && typeof item.read === "boolean" &&
        allowedCategories.has(item.category)).slice(0, MAX_ITEMS);
    } catch { return []; }
  }
  function save(items) {
    try { window.localStorage.setItem(STORAGE_KEY, JSON.stringify(items.slice(0, MAX_ITEMS))); return true; }
    catch { return false; }
  }
  function emit() {
    const snapshot = list();
    listeners.forEach(fn => { try { fn(snapshot); } catch (error) { console.error("NEXUS notification listener failed:", error); } });
  }
  function list() { return readItems(); }
  function add(input) {
    if (!input || typeof input !== "object") throw new TypeError("Notification details are required.");
    const title = typeof input.title === "string" ? input.title.trim() : "";
    const body = typeof input.body === "string" ? input.body.trim() : "";
    if (!title || title.length > 120 || body.length > 1000) throw new RangeError("Notification title/body is empty or too long.");
    const category = allowedCategories.has(input.category) ? input.category : "system";
    const item = { id: (typeof crypto !== "undefined" && crypto.randomUUID) ? crypto.randomUUID() : String(Date.now()) + "-" + Math.random().toString(36).slice(2), title, body, category, timestamp: Date.now(), read: false };
    const items = [item, ...readItems()].slice(0, MAX_ITEMS);
    if (!save(items)) throw new Error("Could not save notification. Storage may be unavailable or full.");
    emit(); return item;
  }
  function markRead(id) {
    if (typeof id !== "string") return false;
    const items = readItems(); const target = items.find(item => item.id === id);
    if (!target || target.read) return false;
    target.read = true; if (!save(items)) return false; emit(); return true;
  }
  function clear() { const ok = save([]); if (ok) emit(); return ok; }
  function unreadCount() { return list().filter(item => !item.read).length; }
  function subscribe(listener) { if (typeof listener !== "function") return () => {}; listeners.add(listener); return () => listeners.delete(listener); }
  window.NexusNotifications = Object.freeze({ list, add, markRead, clear, unreadCount, subscribe });
})();