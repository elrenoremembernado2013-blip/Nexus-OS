(() => {
  const customWallpaperKey = "custom";
  const allowedImageTypes = ["image/jpeg", "image/png", "image/webp"];

  const presetWallpapers = window.NexusPersonalisationCatalog?.WALLPAPERS || [
    {
      id: "mountain-night",
      category: "cinematic",
      categoryLabel: "Cinematic",
      label: "Mountain Night Sky",
      aria: "Apply mountain night wallpaper",
      thumb: "https://images.unsplash.com/photo-1519681393784-d120267933ba?auto=format&fit=crop&w=520&q=75",
      alt: "Starry sky above a snow-covered mountain peak",
      photographer: "Benjamin Voros",
      sourceName: "Unsplash",
      sourceUrl: "https://unsplash.com/photos/snow-mountain-under-stars-phIFdC6lA4E",
      license: "Unsplash License",
      recommendedTheme: "midnight"
    },
    {
      id: "alpine",
      category: "nature",
      categoryLabel: "Nature",
      label: "Alpine Horizon",
      aria: "Apply alpine landscape wallpaper",
      thumb: "https://images.unsplash.com/photo-1508402476522-c77c2fa4479d?auto=format&fit=crop&w=520&q=75",
      alt: "Mountain peak silhouette under twilight stars",
      photographer: "Phil Botha",
      sourceName: "Unsplash",
      sourceUrl: "https://unsplash.com/photos/silhouette-of-mountain-peak-at-nighttime-a0TJ3hy-UD8",
      license: "Unsplash License",
      recommendedTheme: "arctic"
    }
  ];

  const wallpaperCategories = window.NexusPersonalisationCatalog?.WALLPAPER_CATEGORIES || [
    { id: "cinematic", label: "Cinematic" },
    { id: "nature", label: "Nature" },
    { id: "architecture", label: "Architecture" },
    { id: "abstract", label: "Abstract" },
    { id: "sci-fi", label: "Space & Astronomy" },
    { id: "minimal", label: "Minimal" },
    { id: "gaming", label: "Gaming" }
  ];

  function openWallpaperDatabase() {
    return new Promise((resolve, reject) => {
      if (!("indexedDB" in window)) {
        reject(new Error("Local image storage is not supported in this browser."));
        return;
      }
      const request = window.indexedDB.open("nexus-wallpaper-store", 1);
      request.onupgradeneeded = () => {
        const db = request.result;
        if (!db.objectStoreNames.contains("wallpapers")) db.createObjectStore("wallpapers");
      };
      request.onsuccess = () => resolve(request.result);
      request.onerror = () => reject(new Error("Could not open local wallpaper storage."));
    });
  }

  async function readCustomWallpaper() {
    const db = await openWallpaperDatabase();
    return new Promise((resolve, reject) => {
      const tx = db.transaction("wallpapers", "readonly");
      const request = tx.objectStore("wallpapers").get(customWallpaperKey);
      request.onsuccess = () => {
        resolve(request.result || null);
        db.close();
      };
      request.onerror = () => {
        db.close();
        reject(new Error("Could not read the saved custom wallpaper."));
      };
    });
  }

  async function saveCustomWallpaper(blob) {
    const db = await openWallpaperDatabase();
    return new Promise((resolve, reject) => {
      const tx = db.transaction("wallpapers", "readwrite");
      tx.objectStore("wallpapers").put(blob, customWallpaperKey);
      tx.oncomplete = () => {
        db.close();
        resolve();
      };
      tx.onerror = () => {
        db.close();
        reject(new Error("Could not save the custom wallpaper."));
      };
      tx.onabort = () => {
        db.close();
        reject(new Error("Saving the custom wallpaper was cancelled."));
      };
    });
  }

  async function deleteCustomWallpaper() {
    const db = await openWallpaperDatabase();
    return new Promise((resolve, reject) => {
      const tx = db.transaction("wallpapers", "readwrite");
      tx.objectStore("wallpapers").delete(customWallpaperKey);
      tx.oncomplete = () => {
        db.close();
        resolve();
      };
      tx.onerror = () => {
        db.close();
        reject(new Error("Could not remove the saved custom wallpaper."));
      };
      tx.onabort = () => {
        db.close();
        reject(new Error("Removing the custom wallpaper was cancelled."));
      };
    });
  }

  function rgbToHsl(r, g, b) {
    r /= 255;
    g /= 255;
    b /= 255;
    const max = Math.max(r, g, b);
    const min = Math.min(r, g, b);
    const delta = max - min;
    let h = 0;
    let sat = 0;
    const l = (max + min) / 2;
    if (delta) {
      sat = delta / (1 - Math.abs(2 * l - 1));
      switch (max) {
        case r:
          h = ((g - b) / delta) % 6;
          break;
        case g:
          h = (b - r) / delta + 2;
          break;
        default:
          h = (r - g) / delta + 4;
      }
      h *= 60;
      if (h < 0) h += 360;
    }
    return { h, s: sat, l };
  }

  function hslToHex(h, sat, l) {
    const chroma = (1 - Math.abs(2 * l - 1)) * sat;
    const x = chroma * (1 - Math.abs(((h / 60) % 2) - 1));
    const m = l - chroma / 2;
    let rgb;
    if (h < 60) rgb = [chroma, x, 0];
    else if (h < 120) rgb = [x, chroma, 0];
    else if (h < 180) rgb = [0, chroma, x];
    else if (h < 240) rgb = [0, x, chroma];
    else if (h < 300) rgb = [x, 0, chroma];
    else rgb = [chroma, 0, x];
    return "#" + rgb.map(value => Math.round((value + m) * 255).toString(16).padStart(2, "0")).join("");
  }

  function sampleWallpaperHue(image) {
    const canvas = document.createElement("canvas");
    canvas.width = 48;
    canvas.height = 48;
    const context = canvas.getContext("2d", { willReadFrequently: true });
    if (!context) throw new Error("Colour sampling is unavailable.");
    context.drawImage(image, 0, 0, 48, 48);
    const pixels = context.getImageData(0, 0, 48, 48).data;
    const bins = new Array(24).fill(0);
    for (let i = 0; i < pixels.length; i += 16) {
      if (pixels[i + 3] < 180) continue;
      const { h, s, l } = rgbToHsl(pixels[i], pixels[i + 1], pixels[i + 2]);
      if (s < 0.2 || l < 0.12 || l > 0.88) continue;
      bins[Math.floor(h / 15) % 24] += s * (0.5 + Math.min(l, 1 - l));
    }
    const strongest = bins.indexOf(Math.max(...bins));
    if (strongest < 0 || bins[strongest] === 0) throw new Error("No clear accent colour was found.");
    return strongest * 15 + 7.5;
  }

  function render() {
    const heading = (title, sub) => `<h2 class="content-title">${title}</h2><p class="content-sub">${sub}</p>`;
    const themes = Object.values(window.NexusPersonalisationCatalog?.THEME_PRESETS || {});
    const profiles = Object.values(window.NexusPersonalisationCatalog?.PROFILES || {});
    const themePresetButtons = themes.map(t => `
      <button class="theme-preset-btn" type="button" data-theme-preset="${t.id}">
        <span class="theme-preset-swatch" style="background:linear-gradient(90deg,${t.bg},${t.accent})"></span>
        <strong>${t.label}</strong>
        <small>${t.description}</small>
      </button>
    `).join("");
    const profileCards = profiles.map(p => `
      <button class="profile-card-btn" type="button" data-personalisation-profile="${p.id}">
        <strong>${p.name}</strong>
        <small>${p.summary}</small>
      </button>
    `).join("");
    const wallpaperFilterButtons = wallpaperCategories.map(cat => `
      <button class="wallpaper-filter" data-wallpaper-filter="${cat.id}" type="button">${cat.label}</button>
    `).join("");
    const wallpaperButtons = presetWallpapers.map(wp => `
      <button class="wallpaper-option" type="button" data-wallpaper="${wp.id}" data-category="${wp.category}" data-title="${wp.label.toLowerCase()}" aria-label="${wp.aria}">
        <span class="wallpaper-fav-btn" data-wallpaper-fav="${wp.id}" role="button" tabindex="0" aria-label="Favourite ${wp.label}">☆</span>
        <img loading="lazy" crossorigin="anonymous" src="${wp.thumb}" alt="${wp.alt}">
        <span>${wp.label}</span>
      </button>
    `).join("");

    return `
      <div class="settings-layout">
        <aside class="settings-sidebar" aria-label="Settings categories">
          <p class="settings-kicker">PREFERENCES</p>
          <button class="settings-nav active" type="button" data-settings-section="appearance"><span>◐</span> Appearance</button>
          <button class="settings-nav" type="button" data-settings-section="personalisation"><span>⊞</span> Dock & Workspaces</button>
          <button class="settings-nav" type="button" data-settings-section="performance"><span>ϟ</span> Performance</button>
          <button class="settings-nav" type="button" data-settings-section="notifications"><span>◉</span> Notifications</button>
          <button class="settings-nav" type="button" data-settings-section="accessibility"><span>◎</span> Accessibility</button>
          <button class="settings-nav" type="button" data-settings-section="system"><span>⌘</span> System</button>
        </aside>
        <div class="settings-main">
          <section class="settings-page" data-settings-page="appearance">
            ${heading("Appearance", "Make NEXUS feel like your own.")}
            <div class="settings-card">
              <div class="settings-card-heading">
                <h3>NEXUS Theme Engine & mode</h3>
                <p>Built-in themes match NEXUS Cinnamon & GTK3 packages on Linux Mint.</p>
              </div>
              <div class="theme-preset-grid">${themePresetButtons}</div>
              <div class="theme-options">
                <button class="theme-choice" data-theme-choice="dark" type="button">Dark</button>
                <button class="theme-choice" data-theme-choice="light" type="button">Light</button>
                <button class="theme-choice" data-theme-choice="system" type="button">System</button>
              </div>
              <p class="settings-hint" id="themeStatus">Dark theme selected.</p>
            </div>
            <div class="settings-card">
              <div class="settings-card-heading">
                <h3>Accent colour</h3>
                <p>Choose a preset highlight, pick any custom colour, or sample from your wallpaper.</p>
              </div>
              <div class="accent-options">
                <button class="accent-swatch" type="button" data-accent="#ffad7a" aria-label="Copper accent" title="Copper"></button>
                <button class="accent-swatch" type="button" data-accent="#8b7cff" aria-label="Violet accent" title="Violet"></button>
                <button class="accent-swatch" type="button" data-accent="#44c9e8" aria-label="Cyan accent" title="Cyan"></button>
                <button class="accent-swatch" type="button" data-accent="#5ed3a3" aria-label="Emerald accent" title="Emerald"></button>
                <button class="accent-swatch" type="button" data-accent="#ee82b6" aria-label="Rose accent" title="Rose"></button>
                <input id="customAccentPicker" type="color" value="#ffad7a" aria-label="Custom accent colour picker" title="Custom accent colour">
              </div>
              <p class="settings-hint" id="accentStatus">Copper is the default NEXUS accent.</p>
              <div class="wallpaper-accent-suggestions">
                <div class="wallpaper-accent-heading">
                  <strong>Wallpaper colour suggestions</strong>
                  <span>Automatically sampled from your wallpaper</span>
                </div>
                <div class="suggested-accent-options" id="suggestedAccentOptions" aria-label="Suggested accent colours">
                  <span class="suggested-accent-empty">Choose a wallpaper to generate matching colours.</span>
                </div>
                <p class="settings-hint" id="suggestedAccentStatus" role="status">Suggestions will appear when you preview a wallpaper.</p>
              </div>
            </div>
            <div class="settings-card wallpaper-card">
              <div class="settings-card-heading">
                <h3>Desktop wallpaper</h3>
                <p>Genuine photographs with verified photographer attribution and source links (no AI-generated images).</p>
              </div>
              <div class="wallpaper-toolbar">
                <input id="wallpaperSearch" class="wallpaper-search" type="search" placeholder="Search wallpapers…" aria-label="Search wallpapers">
                <select id="wallpaperFitSelect" aria-label="Wallpaper fit mode">
                  <option value="cover">Fill (Cover)</option>
                  <option value="contain">Fit (Contain)</option>
                  <option value="fill">Stretch</option>
                  <option value="center">Centre</option>
                </select>
                <select id="wallpaperResolutionSelect" aria-label="Wallpaper resolution">
                  <option value="uhd">2400px UHD</option>
                  <option value="hd">1280px HD</option>
                </select>
                <select id="wallpaperRotationSelect" aria-label="Automatic wallpaper rotation">
                  <option value="off">Rotation: Off</option>
                  <option value="30">Rotate every 30s</option>
                  <option value="300">Rotate every 5m</option>
                </select>
              </div>
              <p class="settings-hint wallpaper-authenticity-note">Real photography and genuine space imagery only — no AI-generated art, CGI, or synthetic wallpapers.</p>
              <div class="wallpaper-filters" role="group" aria-label="Wallpaper categories">
                <button class="wallpaper-filter active" data-wallpaper-filter="all" type="button">All</button>
                <button class="wallpaper-filter" data-wallpaper-filter="favorites" type="button">Favourites</button>
                ${wallpaperFilterButtons}
              </div>
              <div class="wallpaper-grid" id="wallpaperGrid">
                ${wallpaperButtons}
                <div class="custom-wallpaper-import">
                  <div class="custom-wallpaper-copy">
                    <strong>Use your own image</strong>
                    <small>Choose a JPEG, PNG or WebP image up to 8 MB. Your image stays on this device.</small>
                  </div>
                  <input id="customWallpaperFile" class="custom-wallpaper-input" type="file" accept="image/jpeg,image/png,image/webp" aria-label="Choose a custom wallpaper image">
                  <button class="action-button custom-wallpaper-button" id="chooseCustomWallpaper" type="button">Import image</button>
                  <button class="action-button custom-wallpaper-remove" id="removeCustomWallpaper" type="button" hidden>Remove custom image</button>
                  <p class="settings-hint custom-wallpaper-status" id="customWallpaperStatus" role="status">No custom wallpaper imported.</p>
                </div>
              </div>
              <div class="wallpaper-footer">
                <p class="settings-hint" id="wallpaperStatus">Choose a wallpaper to see attribution and preview before applying it.</p>
                <a id="wallpaperAttributionLink" href="https://unsplash.com/license" target="_blank" rel="noopener noreferrer">Unsplash & Public Domain attribution</a>
              </div>
              <dialog class="wallpaper-preview-dialog" id="wallpaperPreviewDialog" aria-labelledby="wallpaperPreviewTitle">
                <div class="wallpaper-preview-shell">
                  <div class="wallpaper-preview-heading">
                    <div>
                      <p class="settings-kicker">DESKTOP PREVIEW</p>
                      <h3 id="wallpaperPreviewTitle">Wallpaper preview</h3>
                    </div>
                    <button class="preview-close" type="button" data-preview-close aria-label="Close preview">×</button>
                  </div>
                  <img id="wallpaperPreviewImage" class="wallpaper-preview-image" alt="Large preview of the selected wallpaper">
                  <p class="wallpaper-preview-caption" id="wallpaperPreviewCaption">This will become your desktop background.</p>
                  <p class="settings-hint" id="wallpaperPreviewAttribution"></p>
                  <div class="wallpaper-preview-actions">
                    <button class="action-button preview-cancel" type="button" data-preview-close>Cancel</button>
                    <button class="action-button preview-apply" id="applyWallpaperPreview" type="button">Apply wallpaper</button>
                  </div>
                </div>
              </dialog>
            </div>
            <div class="settings-card">
              <div class="settings-card-heading">
                <h3>Glass effects & animations</h3>
                <p>Select an effect level or fine-tune backdrop blur for your hardware.</p>
              </div>
              <div class="theme-options" role="group" aria-label="Effect levels">
                <button class="theme-choice" data-effect-level="off" type="button">Off</button>
                <button class="theme-choice" data-effect-level="subtle" type="button">Subtle</button>
                <button class="theme-choice" data-effect-level="balanced" type="button">Balanced</button>
                <button class="theme-choice" data-effect-level="enhanced" type="button">Enhanced</button>
              </div>
              <div class="setting-row">
                <div>
                  <strong>Glass blur</strong>
                  <small>Lower values use fewer visual effects.</small>
                </div>
                <div class="settings-range">
                  <input id="blurSelect" type="range" min="0" max="28" value="18">
                  <output id="blurValue">18 px</output>
                </div>
              </div>
            </div>
          </section>
          <section class="settings-page hidden" data-settings-page="personalisation">
            ${heading("Dock, Panel & Workspaces", "Customise layout, desktop elements, workspaces, and personalisation profiles.")}
            <div class="settings-card">
              <div class="settings-card-heading">
                <h3>Personalisation profiles</h3>
                <p>Apply a coherent preset across theme, effects, dock, and workspaces. Undo anytime.</p>
              </div>
              <div class="profile-grid">${profileCards}</div>
              <div style="display:flex;gap:8px;align-items:center;margin-top:8px">
                <button class="action-button" id="undoProfileBtn" type="button" disabled>Undo last profile</button>
                <span class="settings-hint" id="profileStatus">Customising desktop preferences.</span>
              </div>
            </div>
            <div class="settings-card">
              <div class="settings-card-heading">
                <h3>Dock & panel appearance</h3>
                <p>Controls update the NEXUS dock immediately and map to Cinnamon panel settings on Linux Mint.</p>
              </div>
              <div class="setting-row">
                <div><strong>Dock position</strong><small>Choose bottom, left, or right screen edge.</small></div>
                <select id="dockPositionSelect" aria-label="Dock position">
                  <option value="bottom">Bottom</option>
                  <option value="left">Left</option>
                  <option value="right">Right</option>
                </select>
              </div>
              <div class="setting-row">
                <div><strong>Dock icon size</strong><small>Adjust icon footprint and padding.</small></div>
                <select id="dockSizeSelect" aria-label="Dock icon size">
                  <option value="36">Compact (36 px)</option>
                  <option value="43">Standard (43 px)</option>
                  <option value="52">Large (52 px)</option>
                </select>
              </div>
              <div class="setting-row">
                <div><strong>Dock spacing</strong><small>Gap between pinned and running icons.</small></div>
                <select id="dockGapSelect" aria-label="Dock icon spacing">
                  <option value="5">Tight (5 px)</option>
                  <option value="8">Balanced (8 px)</option>
                  <option value="12">Wide (12 px)</option>
                </select>
              </div>
              <div class="setting-row">
                <div><strong>Dock style</strong><small>Backdrop material for the dock surface.</small></div>
                <select id="dockStyleSelect" aria-label="Dock background style">
                  <option value="glass">Frosted Glass</option>
                  <option value="solid">Solid Dark</option>
                  <option value="minimal">Minimal Translucent</option>
                </select>
              </div>
              <div class="setting-row">
                <div><strong>Auto-hide dock</strong><small>Fade dock until hovered or focused.</small></div>
                <button class="switch-button" id="dockAutoHideToggle" type="button" role="switch" aria-checked="false">Off</button>
              </div>
              <div class="setting-row">
                <div><strong>Running indicators</strong><small>Show dots beneath open or minimised apps.</small></div>
                <button class="switch-button" id="dockIndicatorsToggle" type="button" role="switch" aria-checked="true">On</button>
              </div>
            </div>
            <div class="settings-card">
              <div class="settings-card-heading">
                <h3>Desktop, clock & workspaces</h3>
                <p>Configure desktop shortcuts, clock format, and Cinnamon workspace counts.</p>
              </div>
              <div class="setting-row">
                <div><strong>Desktop shortcuts</strong><small>Show quick-launch icons on the desktop canvas.</small></div>
                <button class="switch-button" id="desktopShortcutsToggle" type="button" role="switch" aria-checked="true">On</button>
              </div>
              <div class="setting-row">
                <div><strong>24-hour clock</strong><small>Use 24-hour format in the top bar.</small></div>
                <button class="switch-button" id="clock24hToggle" type="button" role="switch" aria-checked="false">Off</button>
              </div>
              <div class="setting-row">
                <div><strong>Virtual workspaces (Cinnamon)</strong><small>Switch with Ctrl+Alt+Left / Right on Linux Mint.</small></div>
                <input id="workspaceCountInput" type="number" min="1" max="8" value="4" aria-label="Virtual workspaces count">
              </div>
              <div class="setting-row">
                <div><strong>Workspace names</strong><small>Comma-separated labels stored for your workspace setup.</small></div>
                <input id="workspaceNamesInput" type="text" value="Main, Research, Gaming, Media" aria-label="Workspace names">
              </div>
            </div>
          </section>
          <section class="settings-page hidden" data-settings-page="performance">
            ${heading("Performance", "Choose how much visual effect the desktop uses.")}
            <div class="settings-card">
              <div class="setting-row">
                <div>
                  <strong>Lightweight mode</strong>
                  <small>Reduce blur and shadows throughout the desktop.</small>
                </div>
                <button class="switch-button" id="lightToggle" type="button" role="switch" aria-checked="false">Off</button>
              </div>
              <div class="settings-row-note">This changes prototype visuals only. Real CPU and memory optimisation requires the native NEXUS services.</div>
            </div>
          </section>
          <section class="settings-page hidden" data-settings-page="notifications">
            ${heading("Notifications", "Control how alerts are presented.")}
            <div class="settings-card">
              <div class="setting-row">
                <div>
                  <strong>Do Not Disturb</strong>
                  <small>Quiet notification alerts while enabled.</small>
                </div>
                <button class="switch-button" id="dndToggle" type="button" role="switch" aria-checked="false">Off</button>
              </div>
              <div class="settings-row-note">Notification delivery is a prototype feature. System-wide notification control is planned.</div>
            </div>
          </section>
          <section class="settings-page hidden" data-settings-page="accessibility">
            ${heading("Accessibility", "Make the interface more comfortable to use.")}
            <div class="settings-card">
              <div class="setting-row">
                <div>
                  <strong>Reduce motion</strong>
                  <small>Limit animated transitions and movement.</small>
                </div>
                <button class="switch-button" id="motionToggle" type="button" role="switch" aria-checked="false">Off</button>
              </div>
              <div class="settings-row-note">The system also respects your browser’s reduced-motion preference.</div>
            </div>
          </section>
          <section class="settings-page hidden" data-settings-page="system">
            ${heading("System", "NEXUS OS prototype information and preferences.")}
            <div class="settings-card system-info">
              <div><span>Product</span><strong>NEXUS OS</strong></div>
              <div><span>Version</span><strong>Desktop Prototype 0.3</strong></div>
              <div><span>Platform</span><strong>Browser preview (Linux Mint 22.3 Xfce target)</strong></div>
            </div>
            <div class="settings-card">
              <div class="settings-card-heading">
                <h3>Reset preferences</h3>
                <p>Restore the appearance and quick-setting preferences to their defaults.</p>
              </div>
              <button class="action-button" id="resetPreferences" type="button">Reset all preferences</button>
              <p class="settings-hint">Your Notes content will not be deleted.</p>
            </div>
            <div class="settings-card">
              <div class="settings-card-heading">
                <h3>Privacy and security</h3>
                <p>Preferences are stored locally in this browser. This prototype does not have operating-system privileges or access to hardware controls.</p>
              </div>
            </div>
          </section>
        </div>
      </div>`;
  }

  function mount(root, context = {}) {
    window.NexusAppRegistry.enhanceSettings(root);

    const $ = selector => root.querySelector(selector);
    const $$ = selector => [...root.querySelectorAll(selector)];
    const shell = context.desktopShell || window.NexusDesktopShell;
    const desktop = document.getElementById("desktop");
    let unmounted = false;

    let pendingWallpaper = null;
    let pendingCustomWallpaper = null;
    let pendingCustomUrl = null;
    let pendingAccent = null;
    let accentSuggestionToken = 0;

    const previewDialog = $("#wallpaperPreviewDialog");
    const customInput = $("#customWallpaperFile");

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

    function removeStorage(key) {
      try {
        window.localStorage.removeItem(key);
      } catch {
        // Ignore storage restrictions during preference reset.
      }
    }

    function revokePendingCustomUrl() {
      if (pendingCustomUrl) {
        URL.revokeObjectURL(pendingCustomUrl);
        pendingCustomUrl = null;
      }
    }

    function syncNativePersonalisation(opts) {
      if (!window.NexusNativeServices?.status("personalisation")?.available) return Promise.resolve(false);
      try {
        return Promise.resolve(window.NexusNativeServices.call("personalisation", "applyTheme", opts))
          .then(result => result?.ok === true)
          .catch(() => false);
      } catch {
        // Native integration is optional in the browser preview.
        return Promise.resolve(false);
      }
    }

    function applyWallpaper(id, persist = true) {
      if (!shell?.setDesktopWallpaper(id, persist)) return;
      $$("[data-wallpaper]").forEach(item => {
        const selected = item.dataset.wallpaper === id;
        item.classList.toggle("selected", selected);
        item.setAttribute("aria-pressed", String(selected));
      });
      const wpMeta = presetWallpapers.find(w => w.id === id);
      const label = $(`#wallpaperGrid [data-wallpaper="${id}"] span`)?.textContent || id;
      $("#wallpaperStatus").textContent = wpMeta
        ? `Applied: ${label} · Photo by ${wpMeta.photographer} (${wpMeta.sourceName})`
        : "Applied: " + label;
      const attrLink = $("#wallpaperAttributionLink");
      if (attrLink && wpMeta?.sourceUrl) {
        attrLink.href = wpMeta.sourceUrl;
        attrLink.textContent = `${wpMeta.photographer} · ${wpMeta.sourceName} (${wpMeta.license})`;
      }
      if (persist && window.NexusNativeServices?.status("personalisation")?.available) {
        const fitMap = { cover: "zoom", contain: "scaled", fill: "stretched", center: "centered" };
        const fit = fitMap[readStorage("nexus-wallpaper-fit") || "cover"] || "zoom";
        Promise.resolve(window.NexusNativeServices.call("personalisation", "applyWallpaper", { id, fit })).catch(() => {});
      }
    }

    async function syncCustomWallpaperToNative(file) {
      if (!window.NexusNativeServices?.status("personalisation")?.available) return "browser-only";
      if (!file || !allowedImageTypes.includes(file.type) || file.size > 8 * 1024 * 1024) {
        return "browser-only";
      }
      const bytes = new Uint8Array(await file.arrayBuffer());
      let binary = "";
      const chunkSize = 0x8000;
      for (let offset = 0; offset < bytes.length; offset += chunkSize) {
        binary += String.fromCharCode(...bytes.subarray(offset, offset + chunkSize));
      }
      const fitMap = { cover: "zoom", contain: "scaled", fill: "stretched", center: "centered" };
      const fit = fitMap[readStorage("nexus-wallpaper-fit") || "cover"] || "zoom";
      const result = await window.NexusNativeServices.call("personalisation", "importWallpaper", {
        mime: file.type,
        data: btoa(binary),
        fit
      });
      return result?.ok === true ? "native" : "browser-only";
    }

    function setCustomWallpaper(url) {
      shell?.setCustomDesktopWallpaper(url, true);
      $$("[data-wallpaper]").forEach(item => {
        item.classList.remove("selected");
        item.setAttribute("aria-pressed", "false");
      });
      $("#wallpaperStatus").textContent = "Applied: Custom wallpaper";
      $("#customWallpaperStatus").textContent = "Your custom wallpaper is saved on this device.";
      $("#removeCustomWallpaper").hidden = false;
    }

    async function restoreCustomWallpaper() {
      try {
        const blob = await readCustomWallpaper();
        if (unmounted) return;
        const validBlob = Boolean(
          blob &&
          (typeof Blob === "undefined" || blob instanceof Blob) &&
          allowedImageTypes.includes(blob.type)
        );
        if (!validBlob) {
          if (readStorage("nexus-wallpaper") === "custom") {
            applyWallpaper("alpine", true);
          }
          return;
        }
        const activeCustomUrl = shell?.getCustomDesktopWallpaperUrl?.();
        if (readStorage("nexus-wallpaper") === "custom") {
          if (!activeCustomUrl) {
            shell?.setCustomDesktopWallpaper(URL.createObjectURL(blob), false);
          }
          $("#wallpaperStatus").textContent = "Applied: Custom wallpaper";
        }
        $("#customWallpaperStatus").textContent = "A custom wallpaper is saved on this device.";
        $("#removeCustomWallpaper").hidden = false;
      } catch (error) {
        if (!unmounted) {
          if (readStorage("nexus-wallpaper") === "custom") {
            applyWallpaper("alpine", true);
          }
          $("#customWallpaperStatus").textContent = error.message;
        }
      }
    }

    function renderWallpaperAccentSuggestions(hue) {
      const options = [
        { shift: 0, label: "Main match" },
        { shift: 28, label: "Warm harmony" },
        { shift: -28, label: "Cool harmony" }
      ];
      const container = $("#suggestedAccentOptions");
      container.replaceChildren();
      options.forEach(option => {
        const color = hslToHex((hue + option.shift + 360) % 360, 0.68, 0.62);
        const button = document.createElement("button");
        button.type = "button";
        button.className = "suggested-accent-swatch";
        button.dataset.suggestedAccent = color;
        button.style.setProperty("--suggested-color", color);
        button.title = `${option.label} ${color}`;
        button.setAttribute("aria-label", `${option.label} accent ${color}`);
        button.setAttribute("aria-pressed", String(pendingAccent === color));
        if (pendingAccent === color) button.classList.add("selected");
        button.addEventListener("click", () => {
          pendingAccent = color;
          container.querySelectorAll("[data-suggested-accent]").forEach(btn => {
            const selected = btn.dataset.suggestedAccent === color;
            btn.classList.toggle("selected", selected);
            btn.setAttribute("aria-pressed", String(selected));
          });
          $("#suggestedAccentStatus").textContent =
            "Accent selected for this preview. Apply wallpaper to save it, or Cancel to discard it.";
        });
        const label = document.createElement("span");
        label.textContent = option.label;
        button.append(label);
        container.append(button);
      });
      $("#suggestedAccentStatus").textContent =
        "Choose a colour to preview it. It will only be saved if you apply the wallpaper.";
    }

    function resetSuggestedAccents() {
      const container = $("#suggestedAccentOptions");
      container.innerHTML = '<span class="suggested-accent-empty">Choose a wallpaper to generate matching colours.</span>';
      $("#suggestedAccentStatus").textContent = "Suggestions will appear when you preview a wallpaper.";
    }

    function suggestWallpaperAccents(source) {
      const token = ++accentSuggestionToken;
      $("#suggestedAccentOptions").innerHTML =
        '<span class="suggested-accent-empty">Analysing wallpaper colours…</span>';
      $("#suggestedAccentStatus").textContent = "Sampling the image locally in your browser.";
      const image = new Image();
      if (!source.startsWith("blob:") && !source.startsWith("data:")) image.crossOrigin = "anonymous";
      image.onload = () => {
        if (unmounted || token !== accentSuggestionToken) return;
        try {
          renderWallpaperAccentSuggestions(sampleWallpaperHue(image));
        } catch (error) {
          console.warn("NEXUS wallpaper colour sampling failed:", error);
          const blocked = error && error.name === "SecurityError";
          $("#suggestedAccentOptions").innerHTML =
            '<span class="suggested-accent-empty">Could not sample this image. Try a custom image or another wallpaper.</span>';
          $("#suggestedAccentStatus").textContent = blocked
            ? "Browser security blocked pixel access (SecurityError/CORS). Try importing the image locally."
            : "Colour sampling failed; your wallpaper and current accent are unaffected.";
        }
      };
      image.onerror = () => {
        if (unmounted || token !== accentSuggestionToken) return;
        $("#suggestedAccentOptions").innerHTML =
          '<span class="suggested-accent-empty">Colour suggestions are unavailable for this image.</span>';
        $("#suggestedAccentStatus").textContent = "Your wallpaper preview still works normally.";
      };
      image.src = source;
    }

    function closeWallpaperPreview() {
      if (previewDialog.open) previewDialog.close();
      pendingWallpaper = null;
      pendingCustomWallpaper = null;
      pendingAccent = null;
      accentSuggestionToken++;
      revokePendingCustomUrl();
    }

    function openWallpaperPreview(id) {
      const item = $(`[data-wallpaper="${id}"]`);
      const imageUrl = shell?.getWallpaperUrl?.(id);
      if (!item || !imageUrl) return;
      const wpMeta = presetWallpapers.find(w => w.id === id);
      pendingWallpaper = id;
      pendingCustomWallpaper = null;
      pendingAccent = null;
      $("#applyWallpaperPreview").textContent = "Apply wallpaper";
      $("#wallpaperPreviewTitle").textContent = wpMeta?.label || item.querySelector("span").textContent;
      const previewImg = $("#wallpaperPreviewImage");
      previewImg.crossOrigin = "anonymous";
      previewImg.src = imageUrl;
      suggestWallpaperAccents(imageUrl);
      previewImg.alt = item.querySelector("img").alt;
      $("#wallpaperPreviewCaption").textContent =
        id === readStorage("nexus-wallpaper")
          ? "This is your currently applied wallpaper."
          : "Preview only — your desktop will not change until you apply it.";
      const attrEl = $("#wallpaperPreviewAttribution");
      if (attrEl && wpMeta) {
        attrEl.textContent = `Photo by ${wpMeta.photographer} · ${wpMeta.sourceName} (${wpMeta.license}) · Recommended theme: ${wpMeta.recommendedTheme || "midnight"}`;
      }
      if (!previewDialog.open) previewDialog.showModal();
      $("#applyWallpaperPreview").focus();
    }

    $("#chooseCustomWallpaper").addEventListener("click", () => customInput.click());
    customInput.addEventListener("change", () => {
      const file = customInput.files && customInput.files[0];
      customInput.value = "";
      if (!file) return;
      if (!allowedImageTypes.includes(file.type)) {
        $("#customWallpaperStatus").textContent = "Unsupported image. Please choose JPEG, PNG or WebP.";
        return;
      }
      if (file.size > 8 * 1024 * 1024) {
        $("#customWallpaperStatus").textContent = "That image is larger than 8 MB. Choose a smaller file.";
        return;
      }
      const candidateUrl = URL.createObjectURL(file);
      const image = new Image();
      image.onload = () => {
        if (unmounted) {
          URL.revokeObjectURL(candidateUrl);
          return;
        }
        if (!image.naturalWidth || !image.naturalHeight || image.naturalWidth > 12000 || image.naturalHeight > 12000) {
          URL.revokeObjectURL(candidateUrl);
          $("#customWallpaperStatus").textContent = "This image has invalid or unusually large dimensions.";
          return;
        }
        revokePendingCustomUrl();
        pendingCustomUrl = candidateUrl;
        pendingCustomWallpaper = file;
        pendingWallpaper = null;
        pendingAccent = null;
        $("#wallpaperPreviewTitle").textContent = file.name;
        const previewImg = $("#wallpaperPreviewImage");
        previewImg.removeAttribute("crossorigin");
        previewImg.src = candidateUrl;
        suggestWallpaperAccents(candidateUrl);
        previewImg.alt = "Preview of your imported image";
        $("#wallpaperPreviewCaption").textContent =
          "Preview only — your current wallpaper will remain until you apply this image.";
        $("#applyWallpaperPreview").textContent = "Save and apply";
        $("#customWallpaperStatus").textContent = "Image ready to preview: " + file.name;
        if (!previewDialog.open) previewDialog.showModal();
        $("#applyWallpaperPreview").focus();
      };
      image.onerror = () => {
        URL.revokeObjectURL(candidateUrl);
        if (!unmounted) {
          $("#customWallpaperStatus").textContent = "The selected file could not be read as a valid image.";
        }
      };
      image.src = candidateUrl;
    });

    $("#removeCustomWallpaper").addEventListener("click", async () => {
      try {
        await deleteCustomWallpaper();
        const wasApplied = readStorage("nexus-wallpaper") === "custom";
        shell?.clearCustomDesktopWallpaper?.();
        if (wasApplied) {
          applyWallpaper("alpine", true);
        }
        $("#removeCustomWallpaper").hidden = true;
        $("#customWallpaperStatus").textContent = "Custom wallpaper removed from this device.";
        $("#wallpaperStatus").textContent = wasApplied ? "Applied: Alpine" : "Your current wallpaper is unchanged.";
      } catch (error) {
        $("#customWallpaperStatus").textContent = error.message;
      }
    });

    let favSet = new Set();
    try {
      const rawFav = readStorage("nexus-wallpaper-favourites");
      if (rawFav) {
        const parsedFav = JSON.parse(rawFav);
        if (Array.isArray(parsedFav)) {
          favSet = new Set(parsedFav.filter(id => typeof id === "string"));
        }
      }
    } catch {
      favSet = new Set();
    }
    const syncFavouriteButtons = () => {
      $$("[data-wallpaper-fav]").forEach(btn => {
        const isFav = favSet.has(btn.dataset.wallpaperFav);
        btn.textContent = isFav ? "★" : "☆";
        btn.setAttribute("aria-pressed", String(isFav));
      });
    };
    const filterWallpapers = () => {
      const activeCat = $(".wallpaper-filter.active")?.dataset.wallpaperFilter || "all";
      const term = ($("#wallpaperSearch")?.value || "").trim().toLowerCase();
      $$("[data-wallpaper]").forEach(item => {
        const catMatch =
          activeCat === "all" ||
          (activeCat === "favorites" ? favSet.has(item.dataset.wallpaper) : item.dataset.category === activeCat);
        const searchMatch = !term || (item.dataset.title || "").includes(term) || item.dataset.category.includes(term);
        item.hidden = !(catMatch && searchMatch);
      });
    };

    const toggleWallpaperFavourite = favBtn => {
      const wid = favBtn.dataset.wallpaperFav;
      if (favSet.has(wid)) favSet.delete(wid);
      else favSet.add(wid);
      writeStorage("nexus-wallpaper-favourites", JSON.stringify([...favSet]));
      syncFavouriteButtons();
      filterWallpapers();
    };

    $$("[data-wallpaper]").forEach(item => {
      item.addEventListener("click", event => {
        const favBtn = event.target.closest("[data-wallpaper-fav]");
        if (favBtn) {
          event.stopPropagation();
          toggleWallpaperFavourite(favBtn);
          return;
        }
        openWallpaperPreview(item.dataset.wallpaper);
      });
    });
    $$("[data-wallpaper-fav]").forEach(favBtn => {
      favBtn.addEventListener("keydown", event => {
        if (event.key === "Enter" || event.key === " ") {
          event.preventDefault();
          event.stopPropagation();
          toggleWallpaperFavourite(favBtn);
        }
      });
    });
    syncFavouriteButtons();
    $("#wallpaperSearch")?.addEventListener("input", filterWallpapers);

    const fitSelect = $("#wallpaperFitSelect");
    if (fitSelect) {
      fitSelect.value = readStorage("nexus-wallpaper-fit") || "cover";
      fitSelect.addEventListener("change", () => shell?.setWallpaperFit?.(fitSelect.value, true));
    }
    const resSelect = $("#wallpaperResolutionSelect");
    if (resSelect) {
      resSelect.value = readStorage("nexus-wallpaper-resolution") || "uhd";
      resSelect.addEventListener("change", () => {
        writeStorage("nexus-wallpaper-resolution", resSelect.value);
        const cur = readStorage("nexus-wallpaper");
        if (cur && cur !== "custom") applyWallpaper(cur, false);
      });
    }
    let rotationTimer = null;
    const rotSelect = $("#wallpaperRotationSelect");
    const setupRotation = secondsStr => {
      window.clearInterval(rotationTimer);
      rotationTimer = null;
      const sec = Number(secondsStr);
      if (!Number.isFinite(sec) || sec <= 0) return;
      rotationTimer = window.setInterval(() => {
        if (unmounted || !presetWallpapers.length) return;
        const curId = readStorage("nexus-wallpaper") || "alpine";
        const idx = presetWallpapers.findIndex(w => w.id === curId);
        const next = presetWallpapers[(idx + 1) % presetWallpapers.length];
        if (next) applyWallpaper(next.id, true);
      }, sec * 1000);
    };
    if (rotSelect) {
      rotSelect.value = readStorage("nexus-wallpaper-rotation") || "off";
      setupRotation(rotSelect.value);
      rotSelect.addEventListener("change", () => {
        writeStorage("nexus-wallpaper-rotation", rotSelect.value);
        setupRotation(rotSelect.value);
      });
    }
    $$("[data-preview-close]").forEach(button => button.addEventListener("click", closeWallpaperPreview));
    previewDialog.addEventListener("click", event => {
      if (event.target === previewDialog) closeWallpaperPreview();
    });
    previewDialog.addEventListener("close", () => {
      pendingWallpaper = null;
      pendingCustomWallpaper = null;
      pendingAccent = null;
      revokePendingCustomUrl();
      $("#applyWallpaperPreview").textContent = "Apply wallpaper";
    });

    $("#applyWallpaperPreview").addEventListener("click", async () => {
      const chosen = pendingWallpaper;
      const customFile = pendingCustomWallpaper;
      const customUrl = pendingCustomUrl;
      if (customFile && customUrl) {
        try {
          await saveCustomWallpaper(customFile);
          pendingCustomUrl = null;
          setCustomWallpaper(customUrl);
          try {
            const nativeResult = await syncCustomWallpaperToNative(customFile);
            $("#customWallpaperStatus").textContent = nativeResult === "native"
              ? "Saved on this device and applied to the native desktop."
              : "Saved on this device. Native desktop integration is unavailable in this preview.";
          } catch (error) {
            console.warn("NEXUS native custom wallpaper sync failed:", error);
            $("#customWallpaperStatus").textContent = "Saved in NEXUS. Native desktop could not be updated: " + (error?.message || "service unavailable");
          }
          $("#applyWallpaperPreview").textContent = "Apply wallpaper";
        } catch (error) {
          $("#customWallpaperStatus").textContent = error.message;
          return;
        }
      } else if (chosen) {
        applyWallpaper(chosen, true);
        $("#applyWallpaperPreview").textContent = "Apply wallpaper";
      }
      if (pendingAccent) setAccent(pendingAccent);
      closeWallpaperPreview();
    });

    $$("[data-wallpaper-filter]").forEach(filter => {
      filter.addEventListener("click", () => {
        $$("[data-wallpaper-filter]").forEach(item => item.classList.toggle("active", item === filter));
        filterWallpapers();
      });
    });

    function setAccent(value, syncNative = true) {
      document.documentElement.style.setProperty("--accent", value);
      writeStorage("nexus-accent", value);
      const picker = $("#customAccentPicker");
      if (picker && /^#[0-9a-f]{6}$/i.test(value)) picker.value = value;
      $$("[data-accent]").forEach(swatch => {
        const selected = swatch.dataset.accent === value;
        swatch.classList.toggle("selected", selected);
        swatch.setAttribute("aria-pressed", String(selected));
      });
      $$("[data-suggested-accent]").forEach(button => {
        const selected = button.dataset.suggestedAccent === value;
        button.classList.toggle("selected", selected);
        button.setAttribute("aria-pressed", String(selected));
      });
      $("#accentStatus").textContent = "Accent colour updated (" + value + ").";
      if (syncNative) syncNativePersonalisation({ accent: value });
    }

    $("#customAccentPicker")?.addEventListener("input", event => setAccent(event.target.value));
    $$("[data-accent]").forEach(swatch => {
      swatch.addEventListener("click", () => setAccent(swatch.dataset.accent));
    });
    setAccent(readStorage("nexus-accent") || "#ffad7a", false);

    function applyThemePreset(presetId, syncAccent = true) {
      const preset = window.NexusPersonalisationCatalog?.THEME_PRESETS?.[presetId];
      if (!preset) return;
      shell?.setThemePreset?.(presetId, true);
      $$("[data-theme-preset]").forEach(btn => {
        const selected = btn.dataset.themePreset === presetId;
        btn.classList.toggle("selected", selected);
        btn.setAttribute("aria-pressed", String(selected));
      });
      applyTheme(preset.mode, false);
      if (syncAccent) setAccent(preset.accent, false);
      syncNativePersonalisation({
        theme: presetId,
        appearance: preset.mode === "light" ? "light" : "dark",
        accent: syncAccent ? preset.accent : readStorage("nexus-accent") || preset.accent,
        effectLevel: readStorage("nexus-effect-level") || "balanced",
        dockPosition: readStorage("nexus-dock-position") || "bottom",
        panelSize: readStorage("nexus-panel-size") || "medium",
        panelAutohide: readStorage("nexus-dock-autohide") === "true" ? "true" : "false",
        workspaces: Number(readStorage("nexus-workspace-count") || "4")
      });
    }
    $$("[data-theme-preset]").forEach(btn => {
      btn.addEventListener("click", () => applyThemePreset(btn.dataset.themePreset, true));
    });
    const savedPreset = readStorage("nexus-theme-preset");
    if (savedPreset) {
      $$("[data-theme-preset]").forEach(btn => {
        const selected = btn.dataset.themePreset === savedPreset;
        btn.classList.toggle("selected", selected);
        btn.setAttribute("aria-pressed", String(selected));
      });
    }

    function applyEffectLevel(level) {
      shell?.setEffectLevel?.(level, true);
      $$("[data-effect-level]").forEach(btn => {
        const selected = btn.dataset.effectLevel === level;
        btn.classList.toggle("selected", selected);
        btn.setAttribute("aria-pressed", String(selected));
      });
      const blurMap = { off: "0", subtle: "8", balanced: "18", enhanced: "24" };
      if (blurMap[level] !== undefined) {
        blur.value = blurMap[level];
        setBlur();
      }
      syncNativePersonalisation({ effectLevel: level });
    }
    $$("[data-effect-level]").forEach(btn => {
      btn.addEventListener("click", () => applyEffectLevel(btn.dataset.effectLevel));
    });
    const savedEffect = readStorage("nexus-effect-level") || "balanced";
    $$("[data-effect-level]").forEach(btn => {
      const selected = btn.dataset.effectLevel === savedEffect;
      btn.classList.toggle("selected", selected);
      btn.setAttribute("aria-pressed", String(selected));
    });

    function applyTheme(mode, syncNative = false) {
      const useLight =
        mode === "light" ||
        (mode === "system" && window.matchMedia && window.matchMedia("(prefers-color-scheme: light)").matches);
      desktop?.classList.toggle("theme-light", useLight);
      writeStorage("nexus-theme", mode);
      $$("[data-theme-choice]").forEach(button => {
        const selected = button.dataset.themeChoice === mode;
        button.classList.toggle("selected", selected);
        button.setAttribute("aria-pressed", String(selected));
      });
      $("#themeStatus").textContent =
        (mode === "system" ? "Following system appearance" : mode.charAt(0).toUpperCase() + mode.slice(1) + " theme") +
        " selected.";
      if (syncNative) {
        const presetId = readStorage("nexus-theme-preset");
        const nativeTheme = presetId || (useLight ? "arctic" : "midnight");
        syncNativePersonalisation({
          theme: nativeTheme,
          appearance: useLight ? "light" : "dark",
          accent: readStorage("nexus-accent") || "#ffad7a"
        });
      }
    }

    $$("[data-theme-choice]").forEach(button => {
      button.addEventListener("click", () => applyTheme(button.dataset.themeChoice, true));
    });
    applyTheme(readStorage("nexus-theme") || "dark", false);

    const themeMedia = window.matchMedia?.("(prefers-color-scheme: light)");
    const onThemeMediaChange = () => {
      if (readStorage("nexus-theme") === "system") applyTheme("system");
    };
    if (themeMedia) {
      if (themeMedia.addEventListener) themeMedia.addEventListener("change", onThemeMediaChange);
      else themeMedia.addListener?.(onThemeMediaChange);
    }

    const blur = $("#blurSelect");
    const blurValue = $("#blurValue");
    blur.value = readStorage("nexus-blur") || "18";
    function setBlur() {
      document.documentElement.style.setProperty("--blur", blur.value + "px");
      blurValue.value = blur.value + " px";
      blurValue.textContent = blur.value + " px";
      writeStorage("nexus-blur", blur.value);
    }
    blur.addEventListener("input", setBlur);
    setBlur();

    function bindSwitch(button, initialEnabled, onChange) {
      const renderSwitch = enabled => {
        button.setAttribute("aria-checked", String(enabled));
        button.classList.toggle("enabled", enabled);
        button.textContent = enabled ? "On" : "Off";
      };
      renderSwitch(initialEnabled);
      button.addEventListener("click", () => {
        const next = button.getAttribute("aria-checked") !== "true";
        renderSwitch(next);
        onChange(next);
      });
    }

    function updateSwitchState(button, enabled) {
      button.setAttribute("aria-checked", String(enabled));
      button.classList.toggle("enabled", enabled);
      button.textContent = enabled ? "On" : "Off";
    }

    const controlState = shell?.getControlState?.() || { dnd: false, power: false };
    bindSwitch($("#lightToggle"), controlState.power, enabled => shell?.setControlPreference?.("power", enabled));
    bindSwitch($("#dndToggle"), controlState.dnd, enabled => shell?.setControlPreference?.("dnd", enabled));
    const unsubscribeControls = shell?.onControlChange?.(state => {
      if (unmounted) return;
      updateSwitchState($("#lightToggle"), Boolean(state.power));
      updateSwitchState($("#dndToggle"), Boolean(state.dnd));
    });

    const motionPreference = readStorage("nexus-reduced-motion");
    const motionMedia = window.matchMedia?.("(prefers-reduced-motion: reduce)");
    let motionEnabled = motionPreference === null ? Boolean(motionMedia?.matches) : motionPreference === "true";
    function setMotion(enabled, save = true) {
      motionEnabled = enabled;
      document.body.classList.toggle("reduced-motion", enabled);
      if (save) writeStorage("nexus-reduced-motion", String(enabled));
      updateSwitchState($("#motionToggle"), enabled);
    }
    bindSwitch($("#motionToggle"), motionEnabled, enabled => setMotion(enabled, true));
    setMotion(motionEnabled, false);

    const onMotionMediaChange = event => {
      if (readStorage("nexus-reduced-motion") === null) setMotion(event.matches, false);
    };
    if (motionMedia) {
      if (motionMedia.addEventListener) motionMedia.addEventListener("change", onMotionMediaChange);
      else motionMedia.addListener?.(onMotionMediaChange);
    }

    $$("[data-settings-section]").forEach(button => {
      button.addEventListener("click", () => {
        const section = button.dataset.settingsSection;
        $$("[data-settings-section]").forEach(item => {
          const selected = item === button;
          item.classList.toggle("active", selected);
          if (selected) item.setAttribute("aria-current", "page");
          else item.removeAttribute("aria-current");
        });
        $$("[data-settings-page]").forEach(page => {
          const selected = page.dataset.settingsPage === section;
          page.classList.toggle("hidden", !selected);
          if (selected) {
            page.classList.remove("settings-enter");
            void page.offsetWidth;
            page.classList.add("settings-enter");
          }
        });
      });
    });

    const dockPos = $("#dockPositionSelect");
    const dockSize = $("#dockSizeSelect");
    const dockGap = $("#dockGapSelect");
    const dockStyle = $("#dockStyleSelect");
    if (dockPos) {
      dockPos.value = readStorage("nexus-dock-position") || "bottom";
      dockPos.addEventListener("change", () => {
        shell?.setDockPreferences?.({ position: dockPos.value }, true);
        syncNativePersonalisation({ dockPosition: dockPos.value });
      });
    }
    if (dockSize) {
      dockSize.value = readStorage("nexus-dock-size") || "43";
      dockSize.addEventListener("change", () => shell?.setDockPreferences?.({ size: dockSize.value }, true));
    }
    if (dockGap) {
      dockGap.value = readStorage("nexus-dock-gap") || "8";
      dockGap.addEventListener("change", () => shell?.setDockPreferences?.({ gap: dockGap.value }, true));
    }
    if (dockStyle) {
      dockStyle.value = readStorage("nexus-dock-style") || "glass";
      dockStyle.addEventListener("change", () => shell?.setDockPreferences?.({ style: dockStyle.value }, true));
    }
    if ($("#dockAutoHideToggle")) {
      bindSwitch($("#dockAutoHideToggle"), readStorage("nexus-dock-autohide") === "true", en => {
        shell?.setDockPreferences?.({ autoHide: en }, true);
        syncNativePersonalisation({ panelAutohide: en ? "true" : "false" });
      });
    }
    if ($("#dockIndicatorsToggle")) {
      bindSwitch($("#dockIndicatorsToggle"), readStorage("nexus-dock-indicators") !== "false", en =>
        shell?.setDockPreferences?.({ showIndicators: en }, true)
      );
    }
    if ($("#desktopShortcutsToggle")) {
      bindSwitch($("#desktopShortcutsToggle"), readStorage("nexus-desktop-shortcuts") !== "false", en =>
        shell?.setDesktopPreferences?.({ showShortcuts: en }, true)
      );
    }
    if ($("#clock24hToggle")) {
      bindSwitch($("#clock24hToggle"), readStorage("nexus-clock-24h") === "true", en =>
        shell?.setDesktopPreferences?.({ clock24h: en }, true)
      );
    }
    const wsCountInput = $("#workspaceCountInput");
    if (wsCountInput) {
      wsCountInput.value = readStorage("nexus-workspace-count") || "4";
      wsCountInput.addEventListener("change", () => {
        const clamped = Math.min(8, Math.max(1, Number(wsCountInput.value) || 4));
        wsCountInput.value = String(clamped);
        writeStorage("nexus-workspace-count", String(clamped));
        syncNativePersonalisation({ workspaces: clamped });
      });
    }
    const wsNamesInput = $("#workspaceNamesInput");
    if (wsNamesInput) {
      wsNamesInput.value = readStorage("nexus-workspace-names") || "Main, Research, Gaming, Media";
      wsNamesInput.addEventListener("change", () => writeStorage("nexus-workspace-names", wsNamesInput.value));
    }

    let previousProfileSnapshot = null;
    const captureSnapshot = () => ({
      themePreset: readStorage("nexus-theme-preset") || "solar",
      effectLevel: readStorage("nexus-effect-level") || "balanced",
      blur: Number(readStorage("nexus-blur") || "18"),
      reducedMotion: readStorage("nexus-reduced-motion") === "true",
      dockPosition: readStorage("nexus-dock-position") || "bottom",
      dockSize: readStorage("nexus-dock-size") || "43",
      dockAutoHide: readStorage("nexus-dock-autohide") === "true",
      workspaces: Number(readStorage("nexus-workspace-count") || "4")
    });
    const applyProfileObject = profile => {
      applyThemePreset(profile.themePreset, true);
      applyEffectLevel(profile.effectLevel);
      blur.value = String(profile.blur);
      setBlur();
      setMotion(Boolean(profile.reducedMotion), true);
      shell?.setDockPreferences?.({
        position: profile.dockPosition,
        size: profile.dockSize,
        autoHide: Boolean(profile.dockAutoHide)
      }, true);
      syncNativePersonalisation({
        theme: profile.themePreset,
        accent: window.NexusPersonalisationCatalog?.THEME_PRESETS?.[profile.themePreset]?.accent || readStorage("nexus-accent") || "#ffad7a",
        appearance: window.NexusPersonalisationCatalog?.THEME_PRESETS?.[profile.themePreset]?.mode === "light" ? "light" : "dark",
        effectLevel: profile.effectLevel,
        dockPosition: profile.dockPosition,
        panelAutohide: profile.dockAutoHide ? "true" : "false",
        workspaces: profile.workspaces
      });
      if (dockPos) dockPos.value = profile.dockPosition;
      if (dockSize) dockSize.value = String(profile.dockSize);
      if ($("#dockAutoHideToggle")) updateSwitchState($("#dockAutoHideToggle"), Boolean(profile.dockAutoHide));
      if (wsCountInput) {
        wsCountInput.value = String(profile.workspaces);
        writeStorage("nexus-workspace-count", String(profile.workspaces));
      }
    };
    $$("[data-personalisation-profile]").forEach(btn => {
      btn.addEventListener("click", () => {
        const profile = window.NexusPersonalisationCatalog?.PROFILES?.[btn.dataset.personalisationProfile];
        if (!profile) return;
        previousProfileSnapshot = captureSnapshot();
        applyProfileObject(profile);
        $$("[data-personalisation-profile]").forEach(c => c.classList.toggle("selected", c === btn));
        if ($("#undoProfileBtn")) $("#undoProfileBtn").disabled = false;
        if ($("#profileStatus")) $("#profileStatus").textContent = `Applied profile: ${profile.name}`;
      });
    });
    $("#undoProfileBtn")?.addEventListener("click", () => {
      if (!previousProfileSnapshot) return;
      applyProfileObject(previousProfileSnapshot);
      previousProfileSnapshot = null;
      $("#undoProfileBtn").disabled = true;
      $$("[data-personalisation-profile]").forEach(c => c.classList.remove("selected"));
      if ($("#profileStatus")) $("#profileStatus").textContent = "Restored previous personalisation settings.";
    });

    $("#resetPreferences").addEventListener("click", async () => {
      if (!window.confirm("Reset NEXUS appearance and quick-setting preferences? Your Notes will be kept.")) return;
      [
        "nexus-accent",
        "nexus-blur",
        "nexus-theme",
        "nexus-theme-preset",
        "nexus-wallpaper",
        "nexus-wallpaper-fit",
        "nexus-wallpaper-resolution",
        "nexus-wallpaper-rotation",
        "nexus-wallpaper-favourites",
        "nexus-effect-level",
        "nexus-dock-position",
        "nexus-dock-size",
        "nexus-dock-gap",
        "nexus-dock-autohide",
        "nexus-dock-style",
        "nexus-dock-indicators",
        "nexus-desktop-shortcuts",
        "nexus-clock-24h",
        "nexus-workspace-count",
        "nexus-workspace-names",
        "nexus-reduced-motion",
        "nexus-brightness",
        "nexus-volume",
        "nexus-control-wifi",
        "nexus-control-bluetooth",
        "nexus-control-dnd",
        "nexus-control-power"
      ].forEach(removeStorage);

      try {
        await deleteCustomWallpaper();
      } catch {
        /* IndexedDB may be unavailable in restricted contexts; continue reset. */
      }
      shell?.clearCustomDesktopWallpaper?.();
      $("#removeCustomWallpaper").hidden = true;
      $("#customWallpaperStatus").textContent = "No custom wallpaper imported.";
      pendingAccent = null;
      resetSuggestedAccents();

      setupRotation("off");
      if (rotSelect) rotSelect.value = "off";
      if (fitSelect) fitSelect.value = "cover";
      if (resSelect) resSelect.value = "uhd";
      shell?.setWallpaperFit?.("cover", false);
      favSet.clear();
      syncFavouriteButtons();
      if ($("#wallpaperSearch")) $("#wallpaperSearch").value = "";
      $$("[data-wallpaper-filter]").forEach(filter => {
        filter.classList.toggle("active", filter.dataset.wallpaperFilter === "all");
      });
      filterWallpapers();

      applyWallpaper("alpine", true);
      applyTheme("dark");
      applyEffectLevel("balanced");
      $$("[data-theme-preset]").forEach(btn => {
        btn.classList.remove("selected");
        btn.setAttribute("aria-pressed", "false");
      });
      if (desktop?.dataset) {
        delete desktop.dataset.nexusTheme;
        delete desktop.dataset.themePreset;
      }
      removeStorage("nexus-theme-preset");

      shell?.setDockPreferences?.({
        position: "bottom",
        size: "43",
        gap: "8",
        autoHide: false,
        style: "glass",
        showIndicators: true
      }, false);
      if (dockPos) dockPos.value = "bottom";
      if (dockSize) dockSize.value = "43";
      if (dockGap) dockGap.value = "8";
      if (dockStyle) dockStyle.value = "glass";
      if ($("#dockAutoHideToggle")) updateSwitchState($("#dockAutoHideToggle"), false);
      if ($("#dockIndicatorsToggle")) updateSwitchState($("#dockIndicatorsToggle"), true);

      shell?.setDesktopPreferences?.({ showShortcuts: true, clock24h: false }, false);
      if ($("#desktopShortcutsToggle")) updateSwitchState($("#desktopShortcutsToggle"), true);
      if ($("#clock24hToggle")) updateSwitchState($("#clock24hToggle"), false);

      if (wsCountInput) wsCountInput.value = "4";
      if (wsNamesInput) wsNamesInput.value = "Main, Research, Gaming, Media";
      previousProfileSnapshot = null;
      if ($("#undoProfileBtn")) $("#undoProfileBtn").disabled = true;
      $$("[data-personalisation-profile]").forEach(c => c.classList.remove("selected"));
      if ($("#profileStatus")) $("#profileStatus").textContent = "Preferences reset to defaults.";

      shell?.resetBrightness?.();
      shell?.resetControls?.();
      setAccent("#ffad7a");
      blur.value = "18";
      setBlur();
      setMotion(Boolean(motionMedia?.matches), false);
      updateSwitchState($("#lightToggle"), false);
      updateSwitchState($("#dndToggle"), false);
      context.notify?.("NEXUS preferences restored");
    });

    const savedWallpaper = readStorage("nexus-wallpaper") || "alpine";
    if (savedWallpaper !== "custom") applyWallpaper(savedWallpaper, false);
    restoreCustomWallpaper();

    // Reconcile browser-saved preferences with the native desktop on each Settings
    // mount. Native helpers write user-local desktop configuration so it survives
    // logout/restart; unsupported options are safely ignored by each edition.
    const savedMode = readStorage("nexus-theme") || "dark";
    const savedPreset = readStorage("nexus-theme-preset");
    const savedPresetMeta = window.NexusPersonalisationCatalog?.THEME_PRESETS?.[savedPreset];
    const nativeAppearance = savedPresetMeta?.mode || (savedMode === "light" ? "light" : "dark");
    syncNativePersonalisation({
      theme: savedPreset || (nativeAppearance === "light" ? "arctic" : "midnight"),
      appearance: nativeAppearance,
      accent: readStorage("nexus-accent") || "#ffad7a",
      effectLevel: readStorage("nexus-effect-level") || "balanced",
      dockPosition: readStorage("nexus-dock-position") || "bottom",
      panelSize: readStorage("nexus-panel-size") || "medium",
      panelAutohide: readStorage("nexus-dock-autohide") === "true" ? "true" : "false",
      workspaces: Number(readStorage("nexus-workspace-count") || "4")
    });

    return () => {
      unmounted = true;
      accentSuggestionToken++;
      window.clearInterval(rotationTimer);
      unsubscribeControls?.();
      closeWallpaperPreview();
      if (themeMedia) {
        if (themeMedia.removeEventListener) themeMedia.removeEventListener("change", onThemeMediaChange);
        else themeMedia.removeListener?.(onThemeMediaChange);
      }
      if (motionMedia) {
        if (motionMedia.removeEventListener) motionMedia.removeEventListener("change", onMotionMediaChange);
        else motionMedia.removeListener?.(onMotionMediaChange);
      }
    };
  }

  window.NexusAppRegistry.register({ id: "settings", name: "Settings", render, mount });
})();
