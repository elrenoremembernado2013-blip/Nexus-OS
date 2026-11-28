(() => {
  const MAX_HISTORY = 24;

  const resources = [
    { key: "processor", name: "Processor", icon: "⌁", detail: "CPU usage and per-core activity" },
    { key: "memory", name: "Memory", icon: "▤", detail: "RAM usage and available memory" },
    { key: "storage", name: "Storage", icon: "▣", detail: "Mounted volumes and space usage" },
    { key: "processes", name: "Processes", icon: "≋", detail: "Running processes and resource use" },
    { key: "network", name: "Network", icon: "⇄", detail: "Interface state and transfer activity" },
    { key: "battery", name: "Battery", icon: "ϟ", detail: "Charge level and AC power state" },
    { key: "temperature", name: "Temperature", icon: "◌", detail: "Thermal zone sensor reading" }
  ];

  function telemetryAvailable() {
    try {
      return Boolean(window.NexusNativeServices?.status("telemetry")?.available);
    } catch {
      return false;
    }
  }

  function performanceAvailable() {
    try {
      return Boolean(window.NexusNativeServices?.status("performance")?.available);
    } catch {
      return false;
    }
  }

  function readTelemetrySnapshot() {
    if (!telemetryAvailable()) return { available: false, snapshot: null, error: null, pending: null };
    try {
      const res = window.NexusNativeServices.call("telemetry", "snapshot");
      if (res && typeof res.then === "function") {
        return { available: true, snapshot: null, error: null, pending: res };
      }
      return {
        available: true,
        snapshot: res && typeof res === "object" ? res : {},
        error: null,
        pending: null
      };
    } catch (error) {
      return {
        available: false,
        snapshot: null,
        error: error?.message || "Telemetry service unavailable.",
        pending: null
      };
    }
  }

  function readPerformanceOverview() {
    if (!performanceAvailable()) return { available: false, data: null, pending: null };
    try {
      const res = window.NexusNativeServices.call("performance", "overview");
      if (res && typeof res.then === "function") {
        return { available: true, data: null, pending: res };
      }
      return { available: true, data: res && typeof res === "object" ? res : {}, pending: null };
    } catch {
      return { available: false, data: null, pending: null };
    }
  }

  function el(tag, className, text) {
    const node = document.createElement(tag);
    if (className) node.className = className;
    if (text !== undefined) node.textContent = String(text);
    return node;
  }

  function formatUptime(seconds) {
    if (!Number.isFinite(seconds) || seconds < 0) return "Unavailable";
    const mins = Math.floor(seconds / 60);
    const hrs = Math.floor(mins / 60);
    const days = Math.floor(hrs / 24);
    if (days > 0) return `${days}d ${hrs % 24}h ${mins % 60}m`;
    if (hrs > 0) return `${hrs}h ${mins % 60}m`;
    return `${mins}m ${Math.floor(seconds % 60)}s`;
  }

  function parsePercent(entry) {
    if (!entry) return null;
    if (typeof entry.percent === "number" && Number.isFinite(entry.percent)) return entry.percent;
    const match = String(entry.summary || "").match(/([\d.]+)\s*%/);
    return match ? Number(match[1]) : null;
  }

  function buildSparklineSvg(values, color) {
    const svgNS = "http://www.w3.org/2000/svg";
    const mk = tag => (typeof document.createElementNS === "function" ? document.createElementNS(svgNS, tag) : document.createElement(tag));
    const svg = mk("svg");
    svg.setAttribute("viewBox", "0 0 180 40");
    svg.setAttribute("class", "perf-sparkline");
    svg.setAttribute("aria-hidden", "true");
    if (!values.length) return svg;

    const pts = values.map((val, idx) => {
      const x = values.length === 1 ? 90 : Math.round((idx / (values.length - 1)) * 176) + 2;
      const clamped = Math.max(0, Math.min(100, val));
      const y = Math.round(36 - (clamped / 100) * 32);
      return `${x},${y}`;
    });
    const line = mk("polyline");
    line.setAttribute("fill", "none");
    line.setAttribute("stroke", color);
    line.setAttribute("stroke-width", "2.2");
    line.setAttribute("stroke-linecap", "round");
    line.setAttribute("stroke-linejoin", "round");
    line.setAttribute("points", pts.join(" "));
    svg.append(line);
    return svg;
  }

  function render() {
    const available = telemetryAvailable();
    return `
      <section class="system-monitor" aria-labelledby="monitorTitle">
        <header class="app-heading">
          <div>
            <p class="app-eyebrow">SYSTEM TOOLS · PERFORMANCE CENTRE</p>
            <h2 class="content-title" id="monitorTitle">System Monitor</h2>
            <p class="content-sub">${available ? "Live system resource telemetry, startup health, and safe optimisation controls." : "Resource reporting requires a native Linux monitoring service."}</p>
          </div>
          <div style="display:flex;align-items:center;gap:8px;flex-wrap:wrap">
            <span class="integration-status" id="monitorStatusBadge">${available ? "Telemetry connected" : "No telemetry source"}</span>
            ${available ? '<button class="action-button secondary-button" id="monitorAutoBtn" type="button" aria-pressed="false">Auto-refresh: Off</button>' : ""}
            ${available ? '<button class="action-button secondary-button" id="monitorRefresh" type="button">Refresh</button>' : ""}
          </div>
        </header>
        <div class="monitor-grid" id="monitorGrid"></div>
        <div class="monitor-boundary" id="monitorBoundary">
          <strong>${available ? "Native telemetry active" : "Native integration required"}</strong>
          <p>${available ? "Metrics are supplied directly by the connected Linux host telemetry adapter." : "This browser prototype cannot read host CPU, memory, disks, processes or network counters. No sample values or synthetic graphs are shown."}</p>
        </div>

        <div class="perf-centre" id="perfCentre" aria-label="NEXUS Performance Centre">
          <article class="content-card perf-lowres-card" id="perfLowResourcePanel">
            <div class="perf-row-header">
              <div>
                <h3>Low-Resource Mode</h3>
                <p class="settings-hint">Reversible without reboot. Reduces glass blur, UI animations, compositor overhead, and background refresh rate while keeping UFW firewall, Polkit, and security updates active.</p>
              </div>
              <button type="button" class="action-button primary" id="perfLowResToggle" aria-pressed="false">Enable Low-Resource Mode</button>
            </div>
            <ul class="store-requirements perf-changes-list" id="perfLowResChanges">
              <li>UI effects: disables heavy backdrop blur &amp; desktop animations (<code>desktop.lightweight</code>)</li>
              <li>Monitor refresh cadence: throttles auto-polling from 5s to 15s</li>
              <li>Security &amp; accessibility: firewall, Polkit authentication, keyboard focus rings, and updates remain intact</li>
            </ul>
            <p class="integration-note" id="perfLowResStatus" role="status"></p>
          </article>

          <div class="quantum-tabs" role="tablist" aria-label="Performance Centre tools" style="margin-top:12px">
            <button type="button" class="quantum-tab active" data-perf-tab="graphs">Live Graphs &amp; Processes</button>
            <button type="button" class="quantum-tab" data-perf-tab="startup">Boot &amp; Startup Apps</button>
            <button type="button" class="quantum-tab" data-perf-tab="cleanup">Storage &amp; Safe Cleanup</button>
            <button type="button" class="quantum-tab" data-perf-tab="editions">Edition Recommendations</button>
          </div>
          <div id="perfTabPanel" style="margin-top:12px"></div>
          <p class="integration-note" id="perfActionStatus" role="status"></p>
        </div>
      </section>`;
  }

  function mount(root, context = {}) {
    const grid = root.querySelector("#monitorGrid");
    const badge = root.querySelector("#monitorStatusBadge");
    const boundary = root.querySelector("#monitorBoundary");
    const refreshBtn = root.querySelector("#monitorRefresh");
    const autoBtn = root.querySelector("#monitorAutoBtn");
    const lowResBtn = root.querySelector("#perfLowResToggle");
    const lowResStatus = root.querySelector("#perfLowResStatus");
    const tabPanel = root.querySelector("#perfTabPanel");
    const actionStatus = root.querySelector("#perfActionStatus");
    const tabs = typeof root.querySelectorAll === "function" ? [...root.querySelectorAll("[data-perf-tab]")] : [];

    const history = {
      cpu: [],
      ram: [],
      swap: []
    };
    let activeTab = "graphs";
    let lastSnapshot = null;
    let lastPerfOverview = null;
    let autoRefreshTimer = null;
    let autoRefreshEnabled = false;
    let pendingCleanupTarget = null;

    const pushHistory = (arr, val) => {
      if (typeof val !== "number" || !Number.isFinite(val)) return;
      arr.push(val);
      if (arr.length > MAX_HISTORY) arr.shift();
    };

    const isLowRes = () => Boolean(
      context.desktopShell?.isLowResourceMode?.() ??
      context.desktopShell?.getControlState?.()?.power
    );

    const syncLowResButton = () => {
      if (!lowResBtn) return;
      const enabled = isLowRes();
      lowResBtn.setAttribute("aria-pressed", String(enabled));
      lowResBtn.textContent = enabled ? "Disable Low-Resource Mode" : "Enable Low-Resource Mode";
      lowResBtn.classList.toggle("secondary-button", enabled);
      lowResBtn.classList.toggle("primary", !enabled);
      if (lowResStatus) {
        lowResStatus.textContent = enabled
          ? "Low-Resource Mode is active (animations/blur off, reduced polling, security intact)."
          : "Low-Resource Mode is off (standard liquid-glass effects).";
      }
    };

    const setActionStatus = (msg, isError = false) => {
      if (!actionStatus) return;
      actionStatus.textContent = msg;
      actionStatus.classList.toggle("error", isError);
    };

    const renderTabContent = () => {
      if (!tabPanel) return;
      tabPanel.replaceChildren();
      tabs.forEach(tab => {
        const selected = tab.dataset.perfTab === activeTab;
        tab.classList.toggle("active", selected);
        if (typeof tab.setAttribute === "function") {
          tab.setAttribute("role", "tab");
          tab.setAttribute("aria-selected", String(selected));
        }
      });

      if (activeTab === "graphs") {
        const available = telemetryAvailable();
        if (!available || !lastSnapshot) {
          const card = el("article", "content-card");
          card.append(
            el("h3", "", "Live Graphs & Top Processes"),
            el("p", "", "No synthetic graphs are shown in browser preview. Connect the Linux host bridge to display real bounded-memory CPU, RAM, swap, GPU, and top-process metrics.")
          );
          tabPanel.append(card);
          return;
        }
        const gridCards = el("div", "card-grid");
        const cpuCard = el("article", "content-card");
        const curCpu = history.cpu.length ? `${history.cpu[history.cpu.length - 1]}%` : (lastSnapshot.processor?.summary || "Unavailable");
        cpuCard.append(el("h3", "", `CPU History (${curCpu})`), buildSparklineSvg(history.cpu, "#ffad7a"), el("p", "settings-hint", `Bounded buffer: ${history.cpu.length}/${MAX_HISTORY} samples`));

        const ramCard = el("article", "content-card");
        const curRam = history.ram.length ? `${history.ram[history.ram.length - 1]}%` : (lastSnapshot.memory?.summary || "Unavailable");
        ramCard.append(el("h3", "", `RAM History (${curRam})`), buildSparklineSvg(history.ram, "#60d394"));
        const swapText = lastSnapshot.memory?.swap_total_mib != null
          ? `Swap: ${lastSnapshot.memory.swap_used_mib} / ${lastSnapshot.memory.swap_total_mib} MiB`
          : "Swap telemetry unavailable";
        ramCard.append(el("p", "settings-hint", swapText));

        const sysCard = el("article", "content-card");
        sysCard.append(el("h3", "", "GPU, Uptime & Sensors"));
        const dl = el("dl", "store-detail-metadata");
        const gpuLabel = lastSnapshot.gpu
          ? `${lastSnapshot.gpu.driver}${lastSnapshot.gpu.busy_percent != null ? ` (${lastSnapshot.gpu.busy_percent}% busy)` : ""}`
          : "Unavailable";
        [
          ["Uptime", formatUptime(lastSnapshot.uptime_seconds)],
          ["GPU driver", gpuLabel],
          ["Temperature", lastSnapshot.temperature?.summary || "Unavailable"]
        ].forEach(([k, v]) => dl.append(el("dt", "", k), el("dd", "", v)));
        sysCard.append(dl);

        gridCards.append(cpuCard, ramCard, sysCard);
        tabPanel.append(gridCards);

        const procs = lastSnapshot.processes?.items || [];
        if (procs.length) {
          const procCard = el("article", "content-card");
          procCard.style.marginTop = "12px";
          procCard.append(el("h3", "", "Top Running Processes (by RSS)"));
          const list = el("ul", "store-requirements");
          procs.forEach(p => list.append(el("li", "", `${p.name} (PID ${p.pid}, ${p.user}) — ${p.rss_mib} MiB`)));
          procCard.append(list);
          tabPanel.append(procCard);
        }
      } else if (activeTab === "startup") {
        const perf = lastPerfOverview;
        const card = el("article", "content-card");
        card.append(el("h3", "", "Boot Duration & Startup Applications"));
        if (!perf) {
          card.append(el("p", "", "Boot timing and XDG autostart management require the connected Linux host bridge."));
          tabPanel.append(card);
          return;
        }
        const boot = perf.boot || {};
        card.append(el("p", "settings-hint", boot.summary || "Boot timing unavailable"));
        if (Array.isArray(boot.top_slow_units) && boot.top_slow_units.length) {
          const slowList = el("ul", "store-requirements");
          boot.top_slow_units.forEach(u => slowList.append(el("li", "", `${u.time} — ${u.unit}`)));
          card.append(slowList);
        }

        const apps = perf.startup_apps || [];
        if (!apps.length) {
          card.append(el("p", "settings-hint", "No XDG autostart entries detected."));
        } else {
          const listEl = el("div", "perf-startup-list");
          apps.forEach(app => {
            const row = el("div", "perf-cleanup-row");
            const meta = el("div");
            meta.append(
              el("strong", "", `${app.name} (${app.id})`),
              el("p", "settings-hint", `${app.scope} · ${app.enabled ? "Enabled" : "Disabled"}${app.essential ? " · Essential security/auth unit" : ""}`)
            );
            const btn = el("button", "action-button secondary-button", app.enabled ? "Disable" : "Enable");
            btn.type = "button";
            btn.disabled = Boolean(app.essential && app.enabled);
            btn.dataset.startupId = app.id;
            btn.dataset.startupNext = app.enabled ? "disable" : "enable";
            row.append(meta, btn);
            listEl.append(row);
          });
          card.append(listEl);
        }
        tabPanel.append(card);
      } else if (activeTab === "cleanup") {
        const perf = lastPerfOverview;
        const card = el("article", "content-card");
        card.append(
          el("h3", "", "Safe Cache & Storage Cleanup"),
          el("p", "", "Preview regenerable cache sizes before cleaning. Personal documents, downloads, home configs, and security tools are never touched.")
        );
        if (!perf) {
          card.append(el("p", "settings-hint", "Cache inspection requires the connected Linux host bridge."));
          tabPanel.append(card);
          return;
        }
        const storageDevs = perf.storage_devices || [];
        if (storageDevs.length) {
          card.append(el("p", "settings-hint", `Detected disks: ${storageDevs.map(d => `${d.device} (${d.kind})`).join(", ")}`));
        }
        const items = perf.cleanup_preview || [];
        items.forEach(item => {
          const row = el("div", "perf-cleanup-row");
          const meta = el("div");
          meta.append(
            el("strong", "", `${item.label} — ${item.mib} MiB (${item.files} files)`),
            el("p", "settings-hint", `${item.path}${item.requires_admin ? " · Requires admin password (pkexec)" : ""}`)
          );
          const actions = el("div", "perf-row-actions");
          if (pendingCleanupTarget === item.target) {
            const confirmBtn = el("button", "action-button primary", "Confirm Clean");
            confirmBtn.type = "button";
            confirmBtn.dataset.cleanupConfirm = item.target;
            const cancelBtn = el("button", "action-button secondary-button", "Cancel");
            cancelBtn.type = "button";
            cancelBtn.dataset.cleanupCancel = "1";
            actions.append(confirmBtn, cancelBtn);
          } else {
            const previewBtn = el("button", "action-button secondary-button", "Preview & Clean");
            previewBtn.type = "button";
            previewBtn.disabled = Number(item.files) === 0;
            previewBtn.dataset.cleanupPreview = item.target;
            actions.append(previewBtn);
          }
          row.append(meta, actions);
          card.append(row);
        });
        tabPanel.append(card);
      } else {
        const card = el("article", "content-card");
        const ed = lastPerfOverview?.edition || "all editions";
        card.append(el("h3", "", `Edition Recommendations (${ed})`));
        const recs = lastPerfOverview?.edition_recommendations || [
          "Cinnamon: Disable unused desklets/applets and enable fullscreen unredirection for lower game latency.",
          "Xfce: Toggle Low-Resource Mode or `nexus-apply-xfce --lightweight` to disable compositor shadows on older GPUs.",
          "Lite LXQt: Keep ZRAM enabled (`configure-zram.sh enable`) for 1 GiB RAM systems.",
          "Lite Openbox: Minimal compositor-free session; ideal for 512 MiB–1 GiB hardware and older HDDs."
        ];
        const list = el("ul", "store-requirements");
        recs.forEach(r => list.append(el("li", "", r)));
        card.append(list);
        tabPanel.append(card);
      }
    };

    const renderSnapshot = (available, snapshot, error) => {
      grid.replaceChildren();
      if (badge) {
        badge.textContent = available ? "Telemetry connected" : "No telemetry source";
      }
      if (boundary) {
        boundary.replaceChildren();
        const strong = el("strong");
        const msg = el("p");
        if (error) {
          strong.textContent = "Native telemetry error";
          msg.textContent = error;
        } else if (available) {
          strong.textContent = "Native telemetry active";
          msg.textContent = "Metrics are supplied directly by the connected Linux host telemetry adapter.";
        } else {
          strong.textContent = "Native integration required";
          msg.textContent = "This browser prototype cannot read host CPU, memory, disks, processes or network counters. No sample values or synthetic graphs are shown.";
        }
        boundary.append(strong, msg);
      }

      if (available && snapshot) {
        lastSnapshot = snapshot;
        pushHistory(history.cpu, parsePercent(snapshot.processor));
        pushHistory(history.ram, parsePercent(snapshot.memory));
        pushHistory(history.swap, snapshot.memory?.swap_percent);
      } else if (!available) {
        lastSnapshot = null;
      }

      resources.forEach(resource => {
        const card = el("article", "monitor-card");
        const icon = el("span", "monitor-icon", resource.icon);
        icon.setAttribute("aria-hidden", "true");
        const title = el("h3", "", resource.name);
        const detail = el("p");
        const entry = available && snapshot ? snapshot[resource.key] : null;
        detail.textContent = entry && entry.detail ? String(entry.detail) : resource.detail;
        const state = el("span", "monitor-unavailable");
        state.textContent = available
          ? (entry && entry.summary ? String(entry.summary) : "Ready")
          : "Unavailable";
        card.append(icon, title, detail, state);
        grid.append(card);
      });

      renderTabContent();
    };

    const loadPerfOverview = () => {
      const ov = readPerformanceOverview();
      if (ov.pending) {
        ov.pending
          .then(data => {
            lastPerfOverview = data;
            renderTabContent();
          })
          .catch(() => {});
      } else if (ov.available) {
        lastPerfOverview = ov.data;
        renderTabContent();
      }
    };

    const draw = () => {
      const { available, snapshot, error, pending } = readTelemetrySnapshot();
      if (pending) {
        renderSnapshot(true, lastSnapshot || {}, null);
        pending
          .then(snap => renderSnapshot(true, snap && typeof snap === "object" ? snap : {}, null))
          .catch(err => renderSnapshot(false, null, err?.message || "Telemetry service unavailable."));
      } else {
        renderSnapshot(available, snapshot, error);
      }
      if (performanceAvailable() && !lastPerfOverview) {
        loadPerfOverview();
      }
    };

    const restartPollingIfNeeded = () => {
      if (autoRefreshTimer) {
        window.clearInterval(autoRefreshTimer);
        autoRefreshTimer = null;
      }
      if (autoRefreshEnabled && telemetryAvailable()) {
        const intervalMs = isLowRes() ? 15000 : 5000;
        autoRefreshTimer = window.setInterval(draw, intervalMs);
      }
      if (autoBtn) {
        autoBtn.setAttribute("aria-pressed", String(autoRefreshEnabled));
        autoBtn.textContent = autoRefreshEnabled
          ? `Auto-refresh: ${isLowRes() ? "15s" : "5s"}`
          : "Auto-refresh: Off";
      }
    };

    const onClick = event => {
      const tabBtn = event.target.closest("[data-perf-tab]");
      if (tabBtn) {
        activeTab = tabBtn.dataset.perfTab;
        if ((activeTab === "startup" || activeTab === "cleanup") && performanceAvailable()) {
          loadPerfOverview();
        }
        renderTabContent();
        return;
      }
      const previewBtn = event.target.closest("[data-cleanup-preview]");
      if (previewBtn) {
        pendingCleanupTarget = previewBtn.dataset.cleanupPreview;
        renderTabContent();
        return;
      }
      if (event.target.closest("[data-cleanup-cancel]")) {
        pendingCleanupTarget = null;
        renderTabContent();
        return;
      }
      const confirmBtn = event.target.closest("[data-cleanup-confirm]");
      if (confirmBtn) {
        const target = confirmBtn.dataset.cleanupConfirm;
        pendingCleanupTarget = null;
        setActionStatus(`Cleaning ${target} cache…`);
        Promise.resolve(window.NexusNativeServices.call("performance", "cleanup", target))
          .then(res => {
            setActionStatus(res?.message || `Cleaned ${target} cache.`, res?.ok === false);
            loadPerfOverview();
          })
          .catch(err => setActionStatus(err?.message || "Cleanup failed.", true));
        return;
      }
      const startupBtn = event.target.closest("[data-startup-id]");
      if (startupBtn) {
        const id = startupBtn.dataset.startupId;
        const enable = startupBtn.dataset.startupNext === "enable";
        Promise.resolve(window.NexusNativeServices.call("performance", "setStartup", id, enable))
          .then(res => {
            setActionStatus(res?.message || `Updated startup entry ${id}.`, res?.ok === false);
            loadPerfOverview();
          })
          .catch(err => setActionStatus(err?.message || "Startup update failed.", true));
      }
    };

    const onLowResClick = () => {
      const next = !isLowRes();
      context.desktopShell?.setLowResourceMode?.(next, true);
      syncLowResButton();
      restartPollingIfNeeded();
    };

    const onAutoClick = () => {
      autoRefreshEnabled = !autoRefreshEnabled;
      restartPollingIfNeeded();
    };

    const unsubscribeControl = context.desktopShell?.onControlChange?.(() => {
      syncLowResButton();
      restartPollingIfNeeded();
    });

    syncLowResButton();
    draw();
    if (typeof root.addEventListener === "function") root.addEventListener("click", onClick);
    if (refreshBtn) refreshBtn.addEventListener("click", draw);
    if (autoBtn) autoBtn.addEventListener("click", onAutoClick);
    if (lowResBtn) lowResBtn.addEventListener("click", onLowResClick);

    return () => {
      if (autoRefreshTimer) window.clearInterval(autoRefreshTimer);
      if (typeof unsubscribeControl === "function") unsubscribeControl();
      if (typeof root.removeEventListener === "function") root.removeEventListener("click", onClick);
      if (refreshBtn) refreshBtn.removeEventListener("click", draw);
      if (autoBtn) autoBtn.removeEventListener("click", onAutoClick);
      if (lowResBtn) lowResBtn.removeEventListener("click", onLowResClick);
    };
  }

  window.NexusAppRegistry.register({ id: "monitor", name: "System Monitor", render, mount });
})();
