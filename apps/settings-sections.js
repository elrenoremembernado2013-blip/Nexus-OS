(() => {
  const sections = [
    { id: "display", serviceId: "display", icon: "◫", name: "Display", title: "Display", description: "Resolution, refresh rate and connected displays require a native display service." },
    { id: "sound", serviceId: "sound", icon: "◖", name: "Sound", title: "Sound", description: "Audio devices, output routing and system volume require a native audio service." },
    { id: "network", serviceId: "network", icon: "⌁", name: "Network", title: "Network", description: "Network discovery and connection management are not available in this browser prototype." },
    { id: "bluetooth", serviceId: "bluetooth", icon: "ᛒ", name: "Bluetooth", title: "Bluetooth", description: "Bluetooth adapters and pairing require a native system service." },
    { id: "power", serviceId: "power", icon: "ϟ", name: "Power", title: "Power", description: "Battery state, suspend and power actions require a native power service." },
    { id: "accounts", serviceId: "accounts", icon: "◎", name: "Accounts", title: "User accounts", description: "Account creation and session management belong to the Linux system, not browser storage." },
    { id: "privacy", serviceId: "privacy-security", icon: "◈", name: "Privacy & security", title: "Privacy and security", description: "Firewall, security updates, encryption, Secure Boot, Flatpak permissions, and startup apps." },
    { id: "updates", serviceId: "packages", icon: "↻", name: "Software & updates", title: "Software and updates", description: "Package sources, installation and system updates require a trusted native package service." }
  ];

  function isServiceAvailable(serviceId) {
    try {
      return Boolean(window.NexusNativeServices?.status(serviceId)?.available);
    } catch {
      return false;
    }
  }

  function formatStatusLabel(value) {
    switch (value) {
      case "enabled": return "Enabled";
      case "disabled": return "Disabled";
      case "attention_required": return "Attention required";
      default: return "Unavailable";
    }
  }

  function appendPrivacyOverview(page, available) {
    const overviewCard = document.createElement("div");
    overviewCard.className = "settings-card integration-card";
    const heading = document.createElement("h3");
    heading.textContent = "Security & privacy overview";
    overviewCard.append(heading);

    let snapshot = null;
    let pendingSnapshot = null;
    let errorMsg = null;
    if (available) {
      try {
        const res = window.NexusNativeServices.call("privacy-security", "overview");
        if (res && typeof res.then === "function") {
          pendingSnapshot = res;
        } else {
          snapshot = res;
        }
      } catch (err) {
        errorMsg = err?.message || "Could not read native security overview.";
      }
    }

    const list = document.createElement("dl");
    list.className = "store-detail-metadata";
    const ddByLabel = new Map();
    const rowLabels = [
      "Firewall (UFW)",
      "Security updates",
      "Disk encryption",
      "UEFI Secure Boot",
      "App permissions",
      "Camera / Mic / Location",
      "Startup apps"
    ];
    rowLabels.forEach(label => {
      const dt = document.createElement("dt");
      dt.textContent = label;
      const dd = document.createElement("dd");
      dd.textContent = pendingSnapshot ? "Checking…" : "Unavailable";
      ddByLabel.set(label, dd);
      list.append(dt, dd);
    });
    overviewCard.append(list);

    if (errorMsg) {
      const errEl = document.createElement("p");
      errEl.className = "settings-hint";
      errEl.textContent = errorMsg;
      overviewCard.append(errEl);
    }

    const boundaryNote = document.createElement("p");
    boundaryNote.className = "settings-hint";
    boundaryNote.textContent = "No synthetic security score is shown. Traditional APT packages run unsandboxed as your user; Flatpak apps expose portal permissions.";
    overviewCard.append(boundaryNote);
    page.append(overviewCard);

    let actionsMsg = null;
    let fwBtn = null;
    let fwEnabled = false;
    let startupMount = null;

    const applySnapshot = data => {
      snapshot = data;
      const rawByLabel = new Map([
        ["Firewall (UFW)", formatStatusLabel(data?.firewall?.status)],
        ["Security updates", formatStatusLabel(data?.security_updates?.status)],
        ["Disk encryption", formatStatusLabel(data?.disk_encryption?.status)],
        ["UEFI Secure Boot", formatStatusLabel(data?.secure_boot?.status)],
        ["App permissions", data ? "Flatpak portals · APT unsandboxed" : "Unavailable"],
        ["Camera / Mic / Location", formatStatusLabel(data?.devices?.status)],
        ["Startup apps", data?.startup_apps ? `${data.startup_apps.length} entries` : "Unavailable"]
      ]);
      rawByLabel.forEach((val, key) => {
        const dd = ddByLabel.get(key);
        if (dd) dd.textContent = val;
      });
      if (data?.warnings?.length) {
        const warnTitle = document.createElement("strong");
        warnTitle.textContent = "Security notices";
        overviewCard.append(warnTitle);
        data.warnings.forEach(w => {
          const p = document.createElement("p");
          p.className = "settings-hint";
          p.textContent = String(w);
          overviewCard.append(p);
        });
      }
      if (actionsMsg && data?.services) {
        actionsMsg.textContent = `Services — Bridge: ${data.services["nexus-system-bridge"] || "unknown"} · UFW: ${data.services.ufw || "unknown"} · Ports: ${data.listening_ports?.loopback ?? 0} loopback, ${data.listening_ports?.external ?? 0} external`;
      }
      fwEnabled = data?.firewall?.status === "enabled";
      if (fwBtn) {
        fwBtn.textContent = fwEnabled ? "Disable UFW firewall" : "Enable UFW firewall";
      }
      if (startupMount && data?.startup_apps?.length) {
        if (typeof startupMount.replaceChildren === "function") {
          startupMount.replaceChildren();
        } else if (Array.isArray(startupMount.children)) {
          startupMount.children.length = 0;
        }
        const stTitle = document.createElement("strong");
        if (stTitle.style) {
          stTitle.style.display = "block";
          stTitle.style.marginTop = "12px";
        }
        stTitle.textContent = "Detected autostart entries";
        const ul = document.createElement("ul");
        ul.className = "settings-hint";
        data.startup_apps.slice(0, 8).forEach(entry => {
          const li = document.createElement("li");
          li.textContent = `${entry.name} (${entry.scope} · ${entry.enabled ? "enabled" : "disabled"})`;
          ul.append(li);
        });
        startupMount.append(stTitle, ul);
      }
    };

    if (available) {
      const actionsCard = document.createElement("div");
      actionsCard.className = "settings-card integration-card";
      const actionsTitle = document.createElement("h3");
      actionsTitle.textContent = "Firewall, Flatpak permissions & live checks";
      actionsMsg = document.createElement("p");
      actionsMsg.className = "settings-hint";
      actionsMsg.textContent = "Firewall changes invoke PolicyKit (pkexec) authentication.";

      const row = document.createElement("div");
      row.className = "settings-actions-row";
      if (row.style) {
        row.style.display = "flex";
        row.style.gap = "8px";
        row.style.flexWrap = "wrap";
      }

      fwBtn = document.createElement("button");
      fwBtn.type = "button";
      fwBtn.className = "action-button";
      fwBtn.textContent = "Enable UFW firewall";
      fwBtn.addEventListener("click", async () => {
        try {
          const res = await window.NexusNativeServices.call("privacy-security", "setFirewall", !fwEnabled);
          actionsMsg.textContent = res?.message || "Updated firewall state.";
          fwEnabled = res?.status === "enabled" ? true : (res?.status === "disabled" ? false : !fwEnabled);
          fwBtn.textContent = fwEnabled ? "Disable UFW firewall" : "Enable UFW firewall";
        } catch (err) {
          actionsMsg.textContent = err?.message || "Firewall action unavailable.";
        }
      });
      row.append(fwBtn);

      const fpRow = document.createElement("div");
      if (fpRow.style) {
        fpRow.style.display = "flex";
        fpRow.style.gap = "8px";
        fpRow.style.flexWrap = "wrap";
        fpRow.style.marginTop = "10px";
      }
      const fpInput = document.createElement("input");
      fpInput.type = "text";
      fpInput.placeholder = "Flatpak App ID (e.g. com.discordapp.Discord)";
      fpInput.setAttribute("aria-label", "Flatpak App ID");
      if (fpInput.style) {
        fpInput.style.flex = "1 1 210px";
        fpInput.style.minWidth = "160px";
        fpInput.style.padding = "7px 9px";
        fpInput.style.borderRadius = "9px";
      }
      const fpInspectBtn = document.createElement("button");
      fpInspectBtn.type = "button";
      fpInspectBtn.className = "action-button";
      fpInspectBtn.textContent = "Inspect Flatpak";
      const fpRevokeNetBtn = document.createElement("button");
      fpRevokeNetBtn.type = "button";
      fpRevokeNetBtn.className = "action-button";
      fpRevokeNetBtn.textContent = "Revoke network";
      const fpResetBtn = document.createElement("button");
      fpResetBtn.type = "button";
      fpResetBtn.className = "action-button";
      fpResetBtn.textContent = "Reset overrides";
      const fpOut = document.createElement("p");
      fpOut.className = "settings-hint";

      fpInspectBtn.addEventListener("click", async () => {
        const appId = (fpInput.value || "").trim();
        if (!appId) {
          fpOut.textContent = "Enter a reverse-DNS Flatpak App ID to inspect permissions.";
          return;
        }
        try {
          const res = await window.NexusNativeServices.call("privacy-security", "permissions", appId);
          fpOut.textContent = res?.permissions || res?.message || "No Flatpak permissions reported.";
        } catch (err) {
          fpOut.textContent = err?.message || "Flatpak permission inspection unavailable.";
        }
      });
      fpRevokeNetBtn.addEventListener("click", async () => {
        const appId = (fpInput.value || "").trim();
        if (!appId) {
          fpOut.textContent = "Enter a Flatpak App ID first.";
          return;
        }
        try {
          const res = await window.NexusNativeServices.call("privacy-security", "revokePermission", appId, "--unshare=network");
          fpOut.textContent = res?.message || `Applied --unshare=network override to ${appId}.`;
        } catch (err) {
          fpOut.textContent = err?.message || "Could not update Flatpak permission.";
        }
      });
      fpResetBtn.addEventListener("click", async () => {
        const appId = (fpInput.value || "").trim();
        if (!appId) {
          fpOut.textContent = "Enter a Flatpak App ID first.";
          return;
        }
        try {
          const res = await window.NexusNativeServices.call("privacy-security", "resetPermissions", appId);
          fpOut.textContent = res?.message || `Reset Flatpak permission overrides for ${appId}.`;
        } catch (err) {
          fpOut.textContent = err?.message || "Could not reset Flatpak overrides.";
        }
      });
      fpRow.append(fpInput, fpInspectBtn, fpRevokeNetBtn, fpResetBtn);

      startupMount = document.createElement("div");
      actionsCard.append(actionsTitle, actionsMsg, row, fpRow, fpOut, startupMount);
      page.append(actionsCard);
    }

    if (snapshot) {
      applySnapshot(snapshot);
    } else if (pendingSnapshot) {
      pendingSnapshot
        .then(applySnapshot)
        .catch(err => {
          const errEl = document.createElement("p");
          errEl.className = "settings-hint";
          errEl.textContent = err?.message || "Could not read native security overview.";
          overviewCard.append(errEl);
        });
    }
  }

  function appendUpdatesOverview(page, available) {
    const card = document.createElement("div");
    card.className = "settings-card integration-card";
    const h3 = document.createElement("h3");
    h3.textContent = "System & application updates";
    const summary = document.createElement("p");
    summary.className = "settings-hint";
    summary.textContent = available
      ? "Check real APT and Flatpak updates without leaving Settings."
      : "Connect to the native Linux Mint package service to query real APT & Flatpak updates.";
    card.append(h3, summary);
    if (available) {
      const btn = document.createElement("button");
      btn.type = "button";
      btn.className = "action-button";
      btn.textContent = "Check APT & Flatpak updates";
      btn.addEventListener("click", async () => {
        try {
          const res = await window.NexusNativeServices.call("packages", "checkUpdates");
          const count = Array.isArray(res) ? res.length : (res?.total ?? 0);
          summary.textContent = count > 0
            ? `${count} update(s) available. Open NEXUS Store or Update Manager to install.`
            : "Your APT and Flatpak packages are up to date.";
        } catch (err) {
          summary.textContent = err?.message || "Update check failed.";
        }
      });
      card.append(btn);
    }
    page.append(card);
  }

  function makeSection(section) {
    const available = isServiceAvailable(section.serviceId);
    const nav = document.createElement("button");
    nav.className = "settings-nav";
    nav.type = "button";
    nav.dataset.settingsSection = section.id;
    nav.setAttribute("aria-controls", "settings-page-" + section.id);

    const icon = document.createElement("span");
    icon.textContent = section.icon;
    nav.append(icon, document.createTextNode(section.name));

    const page = document.createElement("section");
    page.className = "settings-page hidden";
    page.dataset.settingsPage = section.id;
    page.id = "settings-page-" + section.id;
    page.setAttribute("aria-labelledby", "settings-title-" + section.id);

    const heading = document.createElement("h2");
    heading.className = "content-title";
    heading.id = "settings-title-" + section.id;
    heading.textContent = section.title;

    const summary = document.createElement("p");
    summary.className = "content-sub";
    summary.textContent = "System integration";

    const card = document.createElement("div");
    card.className = "settings-card integration-card";
    const status = document.createElement("span");
    status.className = "integration-status";
    status.textContent = available ? "Connected" : "Not connected";
    const message = document.createElement("p");
    message.textContent = section.description;
    const note = document.createElement("p");
    note.className = "settings-hint";
    note.textContent = available
      ? "Native Linux Mint service connected."
      : "No system setting has been changed. This capability is planned for the native Linux Mint desktop.";
    card.append(status, message, note);
    if (available) {
      const openBtn = document.createElement("button");
      openBtn.type = "button";
      openBtn.className = "action-button";
      openBtn.textContent = "Open Linux Mint settings";
      openBtn.addEventListener("click", () => {
        try {
          const res = window.NexusNativeServices.call(section.serviceId, "openControl", section.id);
          if (res && res.ok === false) {
            note.textContent = res.message || "No supported native settings tool is available.";
          } else {
            note.textContent = res?.message || "Opened native Linux Mint settings panel.";
          }
        } catch (err) {
          note.textContent = err?.message || "Could not open native settings panel.";
        }
      });
      card.append(openBtn);
    }
    page.append(heading, summary, card);
    if (section.id === "privacy") {
      appendPrivacyOverview(page, available);
    } else if (section.id === "updates") {
      appendUpdatesOverview(page, available);
    }
    return { nav, page };
  }

  window.NexusAppRegistry.registerSettingsEnhancement(root => {
    const sidebar = root.querySelector(".settings-sidebar");
    const main = root.querySelector(".settings-main");
    if (!sidebar || !main) throw new Error("Settings layout is missing its navigation or page container.");

    sections.forEach(section => {
      const { nav, page } = makeSection(section);
      sidebar.append(nav);
      main.append(page);
    });
  });
})();
