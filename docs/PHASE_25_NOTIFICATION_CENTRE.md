# Phase 25 — Persistent Notification Centre

## Scope

Phase 25 adds a shared notification API and a notification history rendered inside the desktop Control Centre. It is a browser-preview implementation backed by `localStorage`, not a replacement for the Linux desktop notification daemon.

## API

The page loads `apps/notification-center.js` before `app.js`. It exposes `window.NexusNotifications`:

- `add({ title, body, category })` creates a notification and returns the stored item.
- `list()` returns the newest notifications first.
- `markRead(id)` marks an item as read.
- `clear()` clears the history.
- `unreadCount()` returns the unread count.
- `subscribe(callback)` subscribes to changes and returns an unsubscribe function.

Supported categories are `system`, `apps`, `security`, `updates` and `gaming`. Unknown categories safely fall back to `system`. Titles are limited to 120 characters, bodies to 1,000 characters, and the history to 50 entries.

Example:

```js
window.NexusNotifications?.add({
  title: "Update available",
  body: "A new application update is ready to review.",
  category: "updates"
});
```

## Privacy and limitations

- Notification history is stored locally in the browser profile. It is not sent to a remote server.
- Clearing history removes the stored notification records.
- The module validates data and renders notification text as text, not HTML.
- Storage can be unavailable or full; callers should handle errors from `add()`.
- This phase does not yet ingest arbitrary Linux D-Bus notifications or guarantee delivery while the desktop preview is closed. Native OS notification-daemon integration is a later task.

## Validation

`scripts/check-notification-center.js` tests persistence, validation, categories, read state, subscriptions and clearing. It is included in `scripts/check-prototype.sh`.