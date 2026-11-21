(() => {
  const catalogue = [
    { name: "NEXUS Text Editor", category: "Productivity", icon: "✎", description: "A focused editor for notes and code, with syntax highlighting planned for a later release." },
    { name: "NEXUS Calendar", category: "Productivity", icon: "▦", description: "Keep events organised with month, week and day views. Native reminders are planned." },
    { name: "NEXUS Media Player", category: "Media", icon: "▶", description: "A home for local audio and video playback with playlists and format support planned." },
    { name: "NEXUS Browser", category: "Internet", icon: "◉", description: "A private-by-design browsing experience. The current desktop includes a safe external-link preview." },
    { name: "NEXUS Calculator", category: "Utilities", icon: "＋", description: "Fast everyday arithmetic with a hand-written parser; scientific mode is planned." },
    { name: "NEXUS Screenshot", category: "Utilities", icon: "▧", description: "Capture and save screen or region images when a native desktop capture service is available." },
    { name: "NEXUS Terminal", category: "Development", icon: "⌘", description: "A command-line interface with a safe demo in this browser. Native terminal integration is planned." },
    { name: "NEXUS System Monitor", category: "System", icon: "▥", description: "System resource monitoring will be provided by a native Linux service; no demo readings are shown." }
  ];

  function render() {
    return `
      <section class="software-centre" aria-labelledby="softwareTitle">
        <header class="app-heading">
          <div>
            <p class="app-eyebrow">NEXUS APPLICATIONS</p>
            <h2 class="content-title" id="softwareTitle">Software Centre</h2>
            <p class="content-sub">Browse the planned NEXUS application collection.</p>
          </div>
          <span class="integration-status">Package service unavailable</span>
        </header>
        <div class="software-toolbar">
          <label class="software-search">
            <span aria-hidden="true">⌕</span>
            <input id="softwareSearch" type="search" placeholder="Search applications" aria-label="Search applications">
          </label>
          <div class="software-categories" role="group" aria-label="Application categories">
            <button type="button" class="software-category selected" data-software-category="All" aria-pressed="true">All</button>
            ${[...new Set(catalogue.map(item => item.category))].map(category => `<button type="button" class="software-category" data-software-category="${category}" aria-pressed="false">${category}</button>`).join("")}
          </div>
        </div>
        <p class="software-count" id="softwareCount" role="status"></p>
        <div class="software-grid" id="softwareGrid"></div>
        <p class="integration-note">Catalogue browsing works in this prototype. Installing, updating and removing software are unavailable until a trusted native package service is integrated.</p>
      </section>`;
  }

  function mount(root) {
    const grid = root.querySelector("#softwareGrid");
    const search = root.querySelector("#softwareSearch");
    const count = root.querySelector("#softwareCount");
    let activeCategory = "All";

    function draw() {
      const term = search.value.trim().toLocaleLowerCase();
      const visible = catalogue.filter(item =>
        (activeCategory === "All" || item.category === activeCategory) &&
        (item.name + " " + item.category + " " + item.description).toLocaleLowerCase().includes(term)
      );
      grid.replaceChildren();
      visible.forEach(item => {
        const card = document.createElement("article");
        card.className = "software-card";
        const icon = document.createElement("span");
        icon.className = "software-icon";
        icon.setAttribute("aria-hidden", "true");
        icon.textContent = item.icon;
        const category = document.createElement("span");
        category.className = "software-card-category";
        category.textContent = item.category;
        const name = document.createElement("h3");
        name.textContent = item.name;
        const description = document.createElement("p");
        description.textContent = item.description;
        const action = document.createElement("button");
        action.type = "button";
        action.className = "action-button";
        action.disabled = true;
        action.title = "Native package integration is not connected.";
        action.textContent = "Install unavailable";
        card.append(icon, category, name, description, action);
        grid.append(card);
      });
      count.textContent = `${visible.length} ${visible.length === 1 ? "application" : "applications"}`;
      if (!visible.length) {
        const empty = document.createElement("p");
        empty.className = "software-empty";
        empty.textContent = "No applications match this search.";
        grid.append(empty);
      }
    }

    search.addEventListener("input", draw);
    root.querySelectorAll("[data-software-category]").forEach(button => {
      button.addEventListener("click", () => {
        activeCategory = button.dataset.softwareCategory;
        root.querySelectorAll("[data-software-category]").forEach(categoryButton => {
          const selected = categoryButton === button;
          categoryButton.classList.toggle("selected", selected);
          categoryButton.setAttribute("aria-pressed", String(selected));
        });
        draw();
      });
    });
    draw();
  }

  window.NexusAppRegistry.register({ id: "software", name: "Software Centre", render, mount });
})();
