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
    let errorMsg = null;
    if (available) {
      try {
        snapshot = window.NexusNativeServices.call("privacy-security", "overview");
      } catch (err) {
        errorMsg = err?.message || "Could not read native security overview.";
      }
    }

    if (errorMsg) {
      const errEl = document.createElement("p");
      errEl.className = "settings-hint";
      errEl.textContent = errorMsg;
      overviewCard.append(errEl);
    }

    const rows = [
      ["Firewall (UFW)", snapshot?.firewall?.status],
      ["Security updates", snapshot?.security_updates?.status],
      ["Disk encryption", snapshot?.disk_encryption?.status],
      ["UEFI Secure Boot", snapshot?.secure_boot?.status],
      ["App permissions", snapshot ? "Flatpak portals · APT unsandboxed" : null],
      ["Camera / Mic / Location", snapshot?.devices?.status],
      ["Startup apps", snapshot?.startup_apps ? `${snapshot.startup_apps.length} entries` : null]
    ];

    const list = document.createElement("dl");
    list.className = "store-detail-metadata";
    rows.forEach(([label, rawStatus]) => {
      const dt = document.createElement("dt");
      dt.textContent = label;
      const dd = document.createElement("dd");
      dd.textContent = label === "App permissions" || label === "Startup apps"
        ? (rawStatus || "Unavailable")
        : formatStatusLabel(rawStatus);
      list.append(dt, dd);
    });
    overviewCard.append(list);

    if (snapshot?.warnings?.length) {
      const warnTitle = document.createElement("strong");
      warnTitle.textContent = "Security notices";
      overviewCard.append(warnTitle);
      snapshot.warnings.forEach(w => {
        const p = document.createElement("p");
        p.className = "settings-hint";
        p.textContent = String(w);
        overviewCard.append(p);
      });
    }

    const boundaryNote = document.createElement("p");
    boundaryNote.className = "settings-hint";
    boundaryNote.textContent = "No synthetic security score is shown. Traditional APT packages run unsandboxed as your user; Flatpak apps expose portal permissions.";
    overviewCard.append(boundaryNote);
    page.append(overviewCard);
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
