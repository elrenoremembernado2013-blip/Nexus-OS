(() => {
  function gamingAvailable() {
    try {
      return Boolean(window.NexusNativeServices?.status("gaming")?.available);
    } catch {
      return false;
    }
  }

  function readGamingStatus() {
    if (!gamingAvailable()) return { available: false, data: null, error: null, pending: null };
    try {
      const res = window.NexusNativeServices.call("gaming", "status");
      if (res && typeof res.then === "function") {
        return { available: true, data: null, error: null, pending: res };
      }
      return { available: true, data: res && typeof res === "object" ? res : {}, error: null, pending: null };
    } catch (err) {
      return { available: false, data: null, error: err?.message || "Gaming service unavailable.", pending: null };
    }
  }

  function node(tag, className, text) {
    const el = document.createElement(tag);
    if (className) el.className = className;
    if (text !== undefined) el.textContent = String(text);
    return el;
  }

  function render() {
    const available = gamingAvailable();
    return `
      <section class="gaming-hub" aria-labelledby="gamingTitle">
        <header class="app-heading">
          <div>
            <p class="app-eyebrow">NEXUS GAMING</p>
            <h2 class="content-title" id="gamingTitle">Gaming Hub</h2>
            <p class="content-sub">${available ? "Connected to Linux Mint Steam, graphics, controller, and Gaming Mode telemetry." : "Browser preview · native Steam, Vulkan, and controller services are disconnected."}</p>
          </div>
          <span class="integration-status" id="gamingBadge">${available ? "Linux Gaming Connected" : "Preview Only"}</span>
        </header>
        <div class="quantum-tabs" role="tablist" aria-label="Gaming Hub sections">
          <button type="button" class="quantum-tab active" data-gaming-tab="overview">Steam & Library</button>
          <button type="button" class="quantum-tab" data-gaming-tab="proton">Proton & Compatibility</button>
          <button type="button" class="quantum-tab" data-gaming-tab="hardware">Graphics & Hardware</button>
          <button type="button" class="quantum-tab" data-gaming-tab="controllers">Controllers & Mode</button>
        </div>
        <div id="gamingPanel" style="margin-top:14px"></div>
        <p class="integration-note" id="gamingStatus" role="status"></p>
      </section>`;
  }

  function mount(root, context = {}) {
    const panel = root.querySelector("#gamingPanel");
    const statusEl = root.querySelector("#gamingStatus");
    const tabs = [...root.querySelectorAll("[data-gaming-tab]")];
    let activeTab = "overview";

    const setStatus = (msg, isError = false) => {
      if (!statusEl) return;
      statusEl.textContent = msg;
      statusEl.classList.toggle("error", isError);
    };

    const drawOverview = (state) => {
      const grid = node("div", "card-grid");
      const steamCard = node("article", "content-card");
      const installed = Boolean(state.data?.steam?.installed);
      steamCard.append(
        node("h3", "", "Steam Client"),
        node("p", "", state.available
          ? (installed ? "Steam is installed on this Linux Mint host." : "Steam is not installed yet (available via steam-installer APT package).")
          : "Steam installation and launching require the Linux Mint host. No fake library or playtime data is shown.")
      );
      if (state.available) {
        const btn = node("button", "action-button primary", installed ? "Launch Steam" : "Install Steam (APT)");
        btn.type = "button";
        btn.dataset.gamingAction = installed ? "launch-steam" : "install-steam";
        steamCard.append(btn);
      } else if (typeof context.launchApp === "function") {
        const storeBtn = node("button", "action-button secondary-button", "View in NEXUS Store");
        storeBtn.type = "button";
        storeBtn.dataset.gamingAction = "open-store";
        steamCard.append(storeBtn);
      }

      const libCard = node("article", "content-card");
      libCard.append(node("h3", "", "Installed Steam Games"));
      const games = state.data?.steam?.installed_games || [];
      if (!state.available) {
        libCard.append(node("p", "", "Unavailable in browser preview."));
      } else if (!games.length) {
        libCard.append(node("p", "", "No Steam app manifests found in ~/.local/share/Steam/steamapps."));
      } else {
        const list = node("ul", "store-requirements");
        games.forEach(g => list.append(node("li", "", `${g.name} (AppID ${g.appid})`)));
        libCard.append(list);
      }
      const launchersCard = node("article", "content-card");
      launchersCard.append(node("h3", "", "Launchers, Tools & Package Managers"));
      if (!state.available) {
        launchersCard.append(node("p", "", "Capability detection requires Linux host. On Linux Mint / Ubuntu, install optionally via APT/Flatpak: gamemode, mangohud, net.lutris.Lutris, com.heroicgameslauncher.hgl."));
      } else {
        const gmOk = Boolean(state.data?.performance?.gamemode_installed);
        const mhOk = Boolean(state.data?.performance?.mangohud_installed);
        const lutrisOk = Boolean(state.data?.launchers?.lutris?.installed);
        const heroicOk = Boolean(state.data?.launchers?.heroic?.installed);
        const aptOk = Boolean(state.data?.capabilities?.apt_available);
        const flatpakOk = Boolean(state.data?.capabilities?.flatpak_available);
        const list = node("ul", "store-requirements");
        list.append(
          node("li", "", gmOk ? "GameMode: installed (use gamemoderun %command%)" : "GameMode: not installed — run: sudo apt install gamemode"),
          node("li", "", mhOk ? "MangoHud: installed (use mangohud %command%)" : "MangoHud: not installed — run: sudo apt install mangohud"),
          node("li", "", lutrisOk ? "Lutris: installed" : "Lutris: not installed — run: flatpak install flathub net.lutris.Lutris"),
          node("li", "", heroicOk ? "Heroic Games Launcher: installed" : "Heroic: not installed — run: flatpak install flathub com.heroicgameslauncher.hgl"),
          node("li", "", `Package managers: APT ${aptOk ? "available" : "unavailable"} · Flatpak ${flatpakOk ? "available" : "unavailable"}`)
        );
        launchersCard.append(list);
      }

      grid.append(steamCard, libCard, launchersCard);
      panel.append(grid);
    };

    const drawProton = (state) => {
      const card = node("article", "content-card");
      card.append(
        node("h3", "", "Steam Play & Proton Compatibility"),
        node("p", "", "Native Linux games run directly on Linux Mint libraries. Windows games run through Valve's Proton translation layer (Vulkan/DXVK). Not every Windows title works—kernel-level anti-cheat and specific DRM remain incompatible unless supported by the developer.")
      );
      const versions = state.data?.steam?.proton_versions || [];
      const wineOk = Boolean(state.data?.steam?.wine_installed);
      if (!state.available) {
        card.append(node("p", "settings-hint", "Detected Proton / Wine installations: Unavailable in browser preview."));
      } else {
        card.append(node("p", "settings-hint", `Wine runtime: ${wineOk ? "installed" : "not detected"}`));
        if (!versions.length) {
          card.append(node("p", "settings-hint", "No Proton versions detected yet. Enable Steam Play for all titles inside Steam Settings -> Compatibility."));
        } else {
          const list = node("ul", "store-requirements");
          versions.forEach(v => list.append(node("li", "", v)));
          card.append(list);
        }
        if (state.data?.steam?.compatibility_caveat) {
          card.append(node("p", "settings-hint", state.data.steam.compatibility_caveat));
        }
      }
      panel.append(card);
    };

    const drawHardware = (state) => {
      const card = node("article", "content-card");
      card.append(node("h3", "", "Graphics, Vulkan & System Compatibility"));
      const hw = state.data?.hardware;
      const gfx = state.data?.graphics;
      const dl = node("dl", "store-detail-metadata");
      const gpuSummary = gfx?.gpus?.length
        ? gfx.gpus.map(g => `${g.vendor_name || g.vendor}:${g.device} (${g.driver})`).join(", ")
        : (state.available ? "None detected" : "Unavailable");
      [
        ["CPU", hw?.cpu || "Unavailable"],
        ["RAM", hw?.ram_total_mib ? `${hw.ram_available_mib} / ${hw.ram_total_mib} MiB available` : "Unavailable"],
        ["Free storage", hw?.storage_available_gib != null ? `${hw.storage_available_gib} GiB free on /` : "Unavailable"],
        ["GPU / Kernel driver", gpuSummary],
        ["Vulkan", gfx?.vulkan_devices?.length ? `${gfx.vulkan} (${gfx.vulkan_devices.join(", ")})` : (gfx?.vulkan || "Unavailable")],
        ["OpenGL renderer", gfx?.opengl_renderer || "Unavailable"]
      ].forEach(([k, v]) => {
        dl.append(node("dt", "", k), node("dd", "", v));
      });
      card.append(dl);
      if (gfx?.software_rendering) {
        card.append(node("p", "settings-hint", "Software OpenGL renderer (llvmpipe) detected: 3D gaming requires native hardware GPU drivers."));
      }
      (gfx?.gpus || []).forEach(g => {
        if (g.compatibility_note) card.append(node("p", "settings-hint", g.compatibility_note));
      });
      card.append(
        node("p", "settings-hint", "AMD and Intel GPUs use Linux Mint Mesa drivers; NVIDIA GPUs should be configured via Linux Mint Driver Manager. No synthetic FPS benchmarks are shown.")
      );
      panel.append(card);
    };

    const drawControllers = (state) => {
      const grid = node("div", "card-grid");
      const ctrlCard = node("article", "content-card");
      ctrlCard.append(node("h3", "", "Connected Controllers"));
      const controllers = state.data?.controllers || [];
      if (!state.available) {
        ctrlCard.append(node("p", "", "Unavailable in browser preview."));
      } else if (!controllers.length) {
        ctrlCard.append(node("p", "", "No /dev/input/js* controllers detected. Connect via USB or Bluetooth, and install steam-devices if udev permissions are needed."));
      } else {
        const list = node("ul", "store-requirements");
        controllers.forEach(c => list.append(node("li", "", `${c.name} (${c.device})`)));
        ctrlCard.append(list);
      }

      const modeCard = node("article", "content-card");
      const modeState = state.data?.performance?.gaming_mode || "unavailable";
      modeCard.append(
        node("h3", "", "NEXUS Gaming Mode"),
        node("p", "", "Reduces compositor/animation overhead, sets the performance power profile when supported, and pairs with GameMode (gamemoderun %command%). Never overclocks hardware.")
      );
      if (state.available) {
        const isEnabled = modeState === "enabled";
        const toggleBtn = node("button", "action-button primary", isEnabled ? "Disable Gaming Mode" : "Enable Gaming Mode");
        toggleBtn.type = "button";
        toggleBtn.dataset.gamingAction = isEnabled ? "mode-disable" : "mode-enable";
        modeCard.append(
          node("p", "settings-hint", `Status: ${modeState} · GameMode: ${state.data?.performance?.gamemode_installed ? "installed" : "not installed"}`),
          toggleBtn
        );
      } else {
        modeCard.append(node("p", "settings-hint", "Gaming Mode controls require the Linux Mint host."));
      }
      grid.append(ctrlCard, modeCard);
      panel.append(grid);
    };

    let cachedState = null;

    const renderState = (state) => {
      panel.replaceChildren();
      tabs.forEach(tab => {
        const selected = tab.dataset.gamingTab === activeTab;
        tab.classList.toggle("active", selected);
        if (typeof tab.setAttribute === "function") {
          tab.setAttribute("role", "tab");
          tab.setAttribute("aria-selected", String(selected));
        }
      });
      if (state.error) setStatus(state.error, true);

      if (activeTab === "overview") drawOverview(state);
      else if (activeTab === "proton") drawProton(state);
      else if (activeTab === "hardware") drawHardware(state);
      else drawControllers(state);
    };

    const draw = (forceRefresh = false) => {
      if (cachedState && !forceRefresh) {
        renderState(cachedState);
        return;
      }
      const state = readGamingStatus();
      if (state.pending) {
        setStatus("Querying Linux Mint gaming capabilities…");
        renderState({ available: true, data: cachedState?.data || {}, error: null });
        state.pending
          .then(data => {
            cachedState = { available: true, data: data && typeof data === "object" ? data : {}, error: null };
            setStatus("");
            renderState(cachedState);
          })
          .catch(err => {
            setStatus(err?.message || "Gaming telemetry unavailable.", true);
          });
        return;
      }
      cachedState = state;
      renderState(state);
    };

    const onClick = event => {
      const tabBtn = event.target.closest("[data-gaming-tab]");
      if (tabBtn) {
        activeTab = tabBtn.dataset.gamingTab;
        draw(false);
        return;
      }
      const actionBtn = event.target.closest("[data-gaming-action]");
      if (!actionBtn) return;
      const action = actionBtn.dataset.gamingAction;
      if (action === "open-store") {
        context.launchApp?.("software");
        return;
      }
      const handleAsync = (promiseOrVal, fallbackMsg, refreshAfter = false) => {
        if (promiseOrVal && typeof promiseOrVal.then === "function") {
          promiseOrVal
            .then(res => {
              setStatus(res?.message || fallbackMsg, res?.ok === false);
              if (refreshAfter) draw(true);
            })
            .catch(err => setStatus(err?.message || "Gaming action failed.", true));
        } else {
          setStatus(promiseOrVal?.message || fallbackMsg, promiseOrVal?.ok === false);
          if (refreshAfter) draw(true);
        }
      };
      try {
        if (action === "launch-steam") {
          handleAsync(window.NexusNativeServices.call("gaming", "launchSteam"), "Launched Steam.");
        } else if (action === "install-steam") {
          handleAsync(window.NexusNativeServices.call("gaming", "installSteam"), "Steam installation requested.", true);
        } else if (action === "mode-enable" || action === "mode-disable") {
          handleAsync(
            window.NexusNativeServices.call("gaming", "setGamingMode", action === "mode-enable"),
            "Updated Gaming Mode.",
            true
          );
        }
      } catch (err) {
        setStatus(err?.message || "Gaming action failed.", true);
      }
    };

    root.addEventListener("click", onClick);
    draw(true);
    return () => root.removeEventListener("click", onClick);
  }

  window.NexusAppRegistry.register({ id: "gaming", name: "Gaming Hub", render, mount });
})();
