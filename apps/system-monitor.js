(() => {
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

  function readTelemetrySnapshot() {
    if (!telemetryAvailable()) return { available: false, snapshot: null, error: null };
    try {
      const snapshot = window.NexusNativeServices.call("telemetry", "snapshot");
      return {
        available: true,
        snapshot: snapshot && typeof snapshot === "object" ? snapshot : {},
        error: null
      };
    } catch (error) {
      return {
        available: false,
        snapshot: null,
        error: error?.message || "Telemetry service unavailable."
      };
    }
  }

  function render() {
    const available = telemetryAvailable();
    return `
      <section class="system-monitor" aria-labelledby="monitorTitle">
        <header class="app-heading">
          <div>
            <p class="app-eyebrow">SYSTEM TOOLS</p>
            <h2 class="content-title" id="monitorTitle">System Monitor</h2>
            <p class="content-sub">${available ? "Live system resource telemetry from the native Linux service." : "Resource reporting requires a native Linux monitoring service."}</p>
          </div>
          <div style="display:flex;align-items:center;gap:8px">
            <span class="integration-status" id="monitorStatusBadge">${available ? "Telemetry connected" : "No telemetry source"}</span>
            ${available ? '<button class="action-button secondary-button" id="monitorRefresh" type="button">Refresh</button>' : ""}
          </div>
        </header>
        <div class="monitor-grid" id="monitorGrid"></div>
        <div class="monitor-boundary" id="monitorBoundary">
          <strong>${available ? "Native telemetry active" : "Native integration required"}</strong>
          <p>${available ? "Metrics are supplied directly by the connected Linux host telemetry adapter." : "This browser prototype cannot read host CPU, memory, disks, processes or network counters. No sample values or synthetic graphs are shown."}</p>
        </div>
      </section>`;
  }

  function mount(root) {
    const grid = root.querySelector("#monitorGrid");
    const badge = root.querySelector("#monitorStatusBadge");
    const boundary = root.querySelector("#monitorBoundary");
    const refreshBtn = root.querySelector("#monitorRefresh");

    const draw = () => {
      const { available, snapshot, error } = readTelemetrySnapshot();
      grid.replaceChildren();
      if (badge) {
        badge.textContent = available ? "Telemetry connected" : "No telemetry source";
      }
      if (boundary && error) {
        boundary.replaceChildren();
        const strong = document.createElement("strong");
        strong.textContent = "Native telemetry error";
        const msg = document.createElement("p");
        msg.textContent = error;
        boundary.append(strong, msg);
      }

      resources.forEach(resource => {
        const card = document.createElement("article");
        card.className = "monitor-card";
        const icon = document.createElement("span");
        icon.className = "monitor-icon";
        icon.setAttribute("aria-hidden", "true");
        icon.textContent = resource.icon;
        const title = document.createElement("h3");
        title.textContent = resource.name;
        const detail = document.createElement("p");
        const entry = available && snapshot ? snapshot[resource.key] : null;
        detail.textContent = entry && entry.detail ? String(entry.detail) : resource.detail;
        const state = document.createElement("span");
        state.className = "monitor-unavailable";
        state.textContent = available
          ? (entry && entry.summary ? String(entry.summary) : "Ready")
          : "Unavailable";
        card.append(icon, title, detail, state);
        grid.append(card);
      });
    };

    draw();
    if (refreshBtn) {
      refreshBtn.addEventListener("click", draw);
      return () => refreshBtn.removeEventListener("click", draw);
    }
    return () => {};
  }

  window.NexusAppRegistry.register({ id: "monitor", name: "System Monitor", render, mount });
})();
