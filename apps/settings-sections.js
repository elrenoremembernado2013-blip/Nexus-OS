(() => {
  const sections = [
    { id: "display", icon: "◫", name: "Display", title: "Display", description: "Resolution, refresh rate and connected displays require a native display service." },
    { id: "sound", icon: "◖", name: "Sound", title: "Sound", description: "Audio devices, output routing and system volume require a native audio service." },
    { id: "network", icon: "⌁", name: "Network", title: "Network", description: "Network discovery and connection management are not available in this browser prototype." },
    { id: "bluetooth", icon: "ᛒ", name: "Bluetooth", title: "Bluetooth", description: "Bluetooth adapters and pairing require a native system service." },
    { id: "power", icon: "ϟ", name: "Power", title: "Power", description: "Battery state, suspend and power actions require a native power service." },
    { id: "accounts", icon: "◎", name: "Accounts", title: "User accounts", description: "Account creation and session management belong to the Linux system, not browser storage." },
    { id: "privacy", icon: "◈", name: "Privacy & security", title: "Privacy and security", description: "This prototype has no system privileges and does not run security scans." },
    { id: "updates", icon: "↻", name: "Software & updates", title: "Software and updates", description: "Package sources, installation and system updates require a trusted native package service." }
  ];

  function makeSection(section) {
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
    status.textContent = "Not connected";
    const message = document.createElement("p");
    message.textContent = section.description;
    const note = document.createElement("p");
    note.className = "settings-hint";
    note.textContent = "No system setting has been changed. This capability is planned for the native Ubuntu desktop.";
    card.append(status, message, note);
    page.append(heading, summary, card);
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
