(() => {
  const resources = [
    { name: "Processor", icon: "⌁", detail: "CPU usage and per-core activity" },
    { name: "Memory", icon: "▤", detail: "RAM usage and available memory" },
    { name: "Storage", icon: "▣", detail: "Mounted volumes and space usage" },
    { name: "Processes", icon: "≋", detail: "Running processes and resource use" },
    { name: "Network", icon: "⇄", detail: "Interface state and transfer activity" }
  ];

  function render() {
    return `
      <section class="system-monitor" aria-labelledby="monitorTitle">
        <header class="app-heading">
          <div>
            <p class="app-eyebrow">SYSTEM TOOLS</p>
            <h2 class="content-title" id="monitorTitle">System Monitor</h2>
            <p class="content-sub">Resource reporting requires a native Linux monitoring service.</p>
          </div>
          <span class="integration-status">No telemetry source</span>
        </header>
        <div class="monitor-grid" id="monitorGrid"></div>
        <div class="monitor-boundary">
          <strong>Native integration required</strong>
          <p>This browser prototype cannot read host CPU, memory, disks, processes or network counters. No sample values or synthetic graphs are shown.</p>
        </div>
      </section>`;
  }

  function mount(root) {
    const grid = root.querySelector("#monitorGrid");
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
      detail.textContent = resource.detail;
      const state = document.createElement("span");
      state.className = "monitor-unavailable";
      state.textContent = "Unavailable";
      card.append(icon, title, detail, state);
      grid.append(card);
    });
  }

  window.NexusAppRegistry.register({ id: "monitor", name: "System Monitor", render, mount });
})();
