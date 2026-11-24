(() => {
  const customWallpaperKey = "custom";
  const allowedImageTypes = ["image/jpeg", "image/png", "image/webp"];

  const presetWallpapers = [
    {
      id: "mountain-night",
      category: "nature",
      label: "Mountain Night",
      aria: "Apply mountain night wallpaper",
      thumb: "https://images.unsplash.com/photo-1725663656850-7bc515816fcd?auto=format&fit=crop&w=520&q=75",
      alt: "Starry sky above a mountain range"
    },
    {
      id: "alpine",
      category: "nature",
      label: "Alpine",
      aria: "Apply alpine landscape wallpaper",
      thumb: "https://images.unsplash.com/photo-1464822759023-fed622ff2c3b?auto=format&fit=crop&w=520&q=75",
      alt: "Dramatic alpine mountain peaks"
    },
    {
      id: "forest",
      category: "nature",
      label: "Forest",
      aria: "Apply forest wallpaper",
      thumb: "https://images.unsplash.com/photo-1441974231531-c6227db76b6e?auto=format&fit=crop&w=520&q=75",
      alt: "Sunlight through a green forest"
    },
    {
      id: "cosmos",
      category: "space",
      label: "Cosmos",
      aria: "Apply cosmos wallpaper",
      thumb: "https://images.unsplash.com/photo-1462331940025-496dfbfc7564?auto=format&fit=crop&w=520&q=75",
      alt: "Colourful deep space nebula"
    },
    {
      id: "city",
      category: "architecture",
      label: "City Lights",
      aria: "Apply city wallpaper",
      thumb: "https://images.unsplash.com/photo-1519608487953-e999c86e7455?auto=format&fit=crop&w=520&q=75",
      alt: "City skyline at dusk"
    },
    {
      id: "modern",
      category: "architecture",
      label: "Architecture",
      aria: "Apply architecture wallpaper",
      thumb: "https://images.unsplash.com/photo-1518005020951-eccb494ad742?auto=format&fit=crop&w=520&q=75",
      alt: "Modern architectural structure"
    }
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
    const wallpaperButtons = presetWallpapers.map(wp => `
      <button class="wallpaper-option" type="button" data-wallpaper="${wp.id}" data-category="${wp.category}" aria-label="${wp.aria}">
        <img loading="lazy" crossorigin="anonymous" src="${wp.thumb}" alt="${wp.alt}">
        <span>${wp.label}</span>
      </button>
    `).join("");

    return `
      <div class="settings-layout">
        <aside class="settings-sidebar" aria-label="Settings categories">
          <p class="settings-kicker">PREFERENCES</p>
          <button class="settings-nav active" type="button" data-settings-section="appearance"><span>◐</span> Appearance</button>
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
                <h3>Desktop theme</h3>
                <p>Choose the overall look of your workspace.</p>
              </div>
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
                <p>Choose the highlight used across the interface.</p>
              </div>
              <div class="accent-options">
                <button class="accent-swatch" type="button" data-accent="#ffad7a" aria-label="Copper accent" title="Copper"></button>
                <button class="accent-swatch" type="button" data-accent="#8b7cff" aria-label="Violet accent" title="Violet"></button>
                <button class="accent-swatch" type="button" data-accent="#44c9e8" aria-label="Cyan accent" title="Cyan"></button>
                <button class="accent-swatch" type="button" data-accent="#5ed3a3" aria-label="Emerald accent" title="Emerald"></button>
                <button class="accent-swatch" type="button" data-accent="#ee82b6" aria-label="Rose accent" title="Rose"></button>
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
                <p>Choose a photographic background for your workspace. Images are served by Unsplash.</p>
              </div>
              <div class="wallpaper-filters" role="group" aria-label="Wallpaper categories">
                <button class="wallpaper-filter active" data-wallpaper-filter="all" type="button">All</button>
                <button class="wallpaper-filter" data-wallpaper-filter="nature" type="button">Nature</button>
                <button class="wallpaper-filter" data-wallpaper-filter="space" type="button">Space</button>
                <button class="wallpaper-filter" data-wallpaper-filter="architecture" type="button">Architecture</button>
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
                <p class="settings-hint" id="wallpaperStatus">Choose a wallpaper to see a larger preview before applying it.</p>
                <a href="https://unsplash.com/license" target="_blank" rel="noopener noreferrer">Unsplash licence</a>
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
                  <div class="wallpaper-preview-actions">
                    <button class="action-button preview-cancel" type="button" data-preview-close>Cancel</button>
                    <button class="action-button preview-apply" id="applyWallpaperPreview" type="button">Apply wallpaper</button>
                  </div>
                </div>
              </dialog>
            </div>
            <div class="settings-card">
              <div class="settings-card-heading">
                <h3>Glass effects</h3>
                <p>Adjust the transparency and blur of panels.</p>
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

    function revokePendingCustomUrl() {
      if (pendingCustomUrl) {
        URL.revokeObjectURL(pendingCustomUrl);
        pendingCustomUrl = null;
      }
    }

    function applyWallpaper(id, persist = true) {
      if (!shell?.setDesktopWallpaper(id, persist)) return;
      $$("[data-wallpaper]").forEach(item => {
        const selected = item.dataset.wallpaper === id;
        item.classList.toggle("selected", selected);
        item.setAttribute("aria-pressed", String(selected));
      });
      const label = $(`#wallpaperGrid [data-wallpaper="${id}"] span`)?.textContent || id;
      $("#wallpaperStatus").textContent = "Applied: " + label;
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
        if (unmounted || !blob || !allowedImageTypes.includes(blob.type)) return;
        const activeCustomUrl = shell?.getCustomDesktopWallpaperUrl?.();
        if (window.localStorage.getItem("nexus-wallpaper") === "custom") {
          if (!activeCustomUrl) {
            shell?.setCustomDesktopWallpaper(URL.createObjectURL(blob), false);
          }
          $("#wallpaperStatus").textContent = "Applied: Custom wallpaper";
        }
        $("#customWallpaperStatus").textContent = "A custom wallpaper is saved on this device.";
        $("#removeCustomWallpaper").hidden = false;
      } catch (error) {
        if (!unmounted) $("#customWallpaperStatus").textContent = error.message;
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
      pendingWallpaper = id;
      pendingCustomWallpaper = null;
      pendingAccent = null;
      $("#applyWallpaperPreview").textContent = "Apply wallpaper";
      $("#wallpaperPreviewTitle").textContent = item.querySelector("span").textContent;
      $("#wallpaperPreviewImage").src = imageUrl;
      suggestWallpaperAccents(imageUrl);
      $("#wallpaperPreviewImage").alt = item.querySelector("img").alt;
      $("#wallpaperPreviewCaption").textContent =
        id === window.localStorage.getItem("nexus-wallpaper")
          ? "This is your currently applied wallpaper."
          : "Preview only — your desktop will not change until you apply it.";
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
        $("#wallpaperPreviewImage").src = candidateUrl;
        suggestWallpaperAccents(candidateUrl);
        $("#wallpaperPreviewImage").alt = "Preview of your imported image";
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
        const wasApplied = window.localStorage.getItem("nexus-wallpaper") === "custom";
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

    $$("[data-wallpaper]").forEach(item => {
      item.addEventListener("click", () => openWallpaperPreview(item.dataset.wallpaper));
    });
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
        const category = filter.dataset.wallpaperFilter;
        $$("[data-wallpaper-filter]").forEach(item => item.classList.toggle("active", item === filter));
        $$("[data-wallpaper]").forEach(item => {
          item.hidden = category !== "all" && item.dataset.category !== category;
        });
      });
    });

    function setAccent(value) {
      document.documentElement.style.setProperty("--accent", value);
      window.localStorage.setItem("nexus-accent", value);
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
      $("#accentStatus").textContent = "Accent colour updated.";
    }

    $$("[data-accent]").forEach(swatch => {
      swatch.addEventListener("click", () => setAccent(swatch.dataset.accent));
    });
    setAccent(window.localStorage.getItem("nexus-accent") || "#ffad7a");

    function applyTheme(mode) {
      const useLight =
        mode === "light" ||
        (mode === "system" && window.matchMedia && window.matchMedia("(prefers-color-scheme: light)").matches);
      desktop?.classList.toggle("theme-light", useLight);
      window.localStorage.setItem("nexus-theme", mode);
      $$("[data-theme-choice]").forEach(button => {
        const selected = button.dataset.themeChoice === mode;
        button.classList.toggle("selected", selected);
        button.setAttribute("aria-pressed", String(selected));
      });
      $("#themeStatus").textContent =
        (mode === "system" ? "Following system appearance" : mode.charAt(0).toUpperCase() + mode.slice(1) + " theme") +
        " selected.";
    }

    $$("[data-theme-choice]").forEach(button => {
      button.addEventListener("click", () => applyTheme(button.dataset.themeChoice));
    });
    applyTheme(window.localStorage.getItem("nexus-theme") || "dark");

    const themeMedia = window.matchMedia?.("(prefers-color-scheme: light)");
    const onThemeMediaChange = () => {
      if (window.localStorage.getItem("nexus-theme") === "system") applyTheme("system");
    };
    if (themeMedia) {
      if (themeMedia.addEventListener) themeMedia.addEventListener("change", onThemeMediaChange);
      else themeMedia.addListener?.(onThemeMediaChange);
    }

    const blur = $("#blurSelect");
    const blurValue = $("#blurValue");
    blur.value = window.localStorage.getItem("nexus-blur") || "18";
    function setBlur() {
      document.documentElement.style.setProperty("--blur", blur.value + "px");
      blurValue.value = blur.value + " px";
      blurValue.textContent = blur.value + " px";
      window.localStorage.setItem("nexus-blur", blur.value);
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

    const motionPreference = window.localStorage.getItem("nexus-reduced-motion");
    const motionMedia = window.matchMedia?.("(prefers-reduced-motion: reduce)");
    let motionEnabled = motionPreference === null ? Boolean(motionMedia?.matches) : motionPreference === "true";
    function setMotion(enabled, save = true) {
      motionEnabled = enabled;
      document.body.classList.toggle("reduced-motion", enabled);
      if (save) window.localStorage.setItem("nexus-reduced-motion", String(enabled));
      updateSwitchState($("#motionToggle"), enabled);
    }
    bindSwitch($("#motionToggle"), motionEnabled, enabled => setMotion(enabled, true));
    setMotion(motionEnabled, false);

    const onMotionMediaChange = event => {
      if (window.localStorage.getItem("nexus-reduced-motion") === null) setMotion(event.matches, false);
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

    $("#resetPreferences").addEventListener("click", async () => {
      if (!window.confirm("Reset NEXUS appearance and quick-setting preferences? Your Notes will be kept.")) return;
      [
        "nexus-accent",
        "nexus-blur",
        "nexus-theme",
        "nexus-wallpaper",
        "nexus-reduced-motion",
        "nexus-brightness",
        "nexus-volume",
        "nexus-control-wifi",
        "nexus-control-bluetooth",
        "nexus-control-dnd",
        "nexus-control-power"
      ].forEach(key => window.localStorage.removeItem(key));

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

      applyWallpaper("alpine", true);
      applyTheme("dark");
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

    const savedWallpaper = window.localStorage.getItem("nexus-wallpaper") || "alpine";
    if (savedWallpaper !== "custom") applyWallpaper(savedWallpaper, false);
    restoreCustomWallpaper();

    return () => {
      unmounted = true;
      accentSuggestionToken++;
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
