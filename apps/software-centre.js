(() => {
  const catalog = window.NexusApplicationCatalog;
  const routeTitles = {
    home: "Home",
    discover: "Discover",
    apps: "Apps",
    games: "Games",
    categories: "Categories",
    collections: "Collections",
    library: "My Library",
    wishlist: "Wishlist",
    downloads: "Downloads",
    updates: "Updates",
    developer: "Developer Hub",
    search: "Search results",
    category: "Category",
    collection: "Collection",
    detail: "Application details",
  };
  const featuredId = "calendar";

  function node(tagName, className, text) {
    const element = document.createElement(tagName);
    if (className) element.className = className;
    if (text !== undefined) element.textContent = text;
    return element;
  }

  function makeIcon(path, className = "app-icon-image") {
    const image = node("img", className);
    image.src = path;
    image.alt = "";
    image.decoding = "async";
    image.setAttribute("aria-hidden", "true");
    return image;
  }

  function render() {
    const navGroups = [
      { title: "Discover", items: [["home", "Home"], ["discover", "Discover"]] },
      { title: "Browse", items: [["apps", "Apps"], ["games", "Games"], ["categories", "Categories"], ["collections", "Collections"]] },
      { title: "Your library", items: [["library", "My Library"], ["wishlist", "Wishlist"], ["downloads", "Downloads"], ["updates", "Updates"]] },
      { title: "For creators", items: [["developer", "Developer Hub"]] },
    ];
    return `
      <section class="software-centre" aria-label="NEXUS Store">
        <aside class="store-sidebar" aria-label="Store navigation">
          <div class="store-brand"><span class="store-brand-mark" aria-hidden="true">N</span><div><strong>NEXUS Store</strong><small>Explore the ecosystem</small></div></div>
          ${navGroups.map(group => `
            <div class="store-nav-group">
              <p>${group.title}</p>
              ${group.items.map(([id, label]) => `<button type="button" class="store-nav-item" data-store-view="${id}" aria-current="false">${label}</button>`).join("")}
            </div>`).join("")}
          <div class="store-sidebar-note"><span class="store-status-dot"></span><span>Prototype catalogue<br><small>Native package service disconnected</small></span></div>
        </aside>
        <div class="store-workspace">
          <header class="store-toolbar">
            <div class="store-toolbar-title">
              <button type="button" class="store-back" id="storeBack" aria-label="Go back" disabled>‹</button>
              <h2 id="storeViewTitle">Home</h2>
            </div>
            <label class="store-search">
              <span aria-hidden="true">⌕</span>
              <input id="storeSearch" type="search" placeholder="Search apps, games, developers" aria-label="Search apps, games and developers">
              <kbd>⌘ K</kbd>
            </label>
          </header>
          <div class="store-content" id="storePage" tabindex="-1"></div>
          <p class="store-message" id="storeMessage" role="status" aria-live="polite"></p>
        </div>
      </section>`;
  }

  function mount(root, context = {}) {
    const page = root.querySelector("#storePage");
    const search = root.querySelector("#storeSearch");
    const title = root.querySelector("#storeViewTitle");
    const back = root.querySelector("#storeBack");
    const message = root.querySelector("#storeMessage");
    const history = [{ view: "home" }];
    let route = history[0];
    let query = "";
    let sort = "recommended";
    let activeCategoryFilter = "All";

    function go(nextRoute, push = true) {
      if (push && JSON.stringify(nextRoute) !== JSON.stringify(route)) history.push(nextRoute);
      else if (!push) history[history.length - 1] = nextRoute;
      route = nextRoute;
      renderPage();
    }

    function goBack() {
      if (history.length > 1) {
        history.pop();
        route = history[history.length - 1];
        renderPage();
      } else {
        go({ view: "home" }, false);
      }
    }

    function setMessage(text, isError = false) {
      message.textContent = text;
      message.classList.toggle("error", isError);
    }

    function getApplication(id) {
      return catalog.getById(id);
    }

    function matchesSearch(application, term) {
      const content = [
        application.name,
        application.description,
        application.developer,
        application.category,
        application.type,
        ...application.tags,
      ].join(" ").toLocaleLowerCase();
      return content.includes(term);
    }

    function sorted(items) {
      const result = [...items];
      if (sort === "alphabetical") result.sort((a, b) => a.name.localeCompare(b.name));
      else if (sort === "originals") result.sort((a, b) => Number(!a.id || a.developer !== "NEXUS") - Number(b.developer !== "NEXUS") || a.name.localeCompare(b.name));
      return result;
    }

    function appAction(application) {
      if (catalog.isInstalled(application)) return { label: "Open", action: "open", disabled: !application.launchTarget };
      if (application.installMode === "internal") return { label: "Add to launcher", action: "install", disabled: false };
      return { label: "Unavailable", action: "unavailable", disabled: true };
    }

    function makeTag(text, className = "") {
      return node("span", `store-tag ${className}`.trim(), text);
    }

    function makeAppCard(application, compact = false) {
      const card = node("article", compact ? "store-app-card compact" : "store-app-card");
      const header = node("div", "store-app-card-header");
      const icon = node("span", `store-app-icon icon-${application.category.toLocaleLowerCase().replace(/[^a-z0-9]+/g, "-")}`);
      icon.setAttribute("aria-hidden", "true");
      icon.append(makeIcon(application.icon));
      const identity = node("div", "store-app-identity");
      identity.append(node("h4", "", application.name), node("p", "", `${application.developer} · ${application.category}`));
      const favorite = node("button", `store-favorite${catalog.isWishlisted(application.id) ? " selected" : ""}`, catalog.isWishlisted(application.id) ? "♥" : "♡");
      favorite.type = "button";
      favorite.dataset.storeAction = "wishlist";
      favorite.dataset.appId = application.id;
      favorite.setAttribute("aria-label", `${catalog.isWishlisted(application.id) ? "Remove" : "Add"} ${application.name} ${catalog.isWishlisted(application.id) ? "from" : "to"} wishlist`);
      header.append(icon, identity, favorite);
      const description = node("p", "store-app-description", application.description);
      const metadata = node("div", "store-app-meta");
      metadata.append(
        makeTag(application.type, "subtle"),
        makeTag(application.capability === "planned" ? "Planned" : application.capability === "preview" ? "Preview" : application.capability === "unavailable" ? "Unavailable" : "Works in prototype")
      );
      const action = appAction(application);
      const footer = node("div", "store-app-card-footer");
      const details = node("button", "store-text-button", "Details");
      details.type = "button";
      details.dataset.storeAction = "details";
      details.dataset.appId = application.id;
      const primary = node("button", `action-button store-card-action${action.disabled ? " unavailable" : " primary"}`, action.label);
      primary.type = "button";
      primary.dataset.storeAction = action.action;
      primary.dataset.appId = application.id;
      primary.disabled = action.disabled;
      if (action.disabled) primary.title = application.installMode === "unavailable"
        ? "This app has no compatible installer or launcher integration yet."
        : "This app cannot be launched from the NEXUS desktop.";
      footer.append(details, primary);
      card.append(header, description, metadata, footer);
      card.addEventListener("dblclick", event => {
        if (event.target.closest("button")) return;
        go({ view: "detail", appId: application.id });
      });
      card.addEventListener("keydown", event => {
        if (event.key === "Enter" && event.target === card) go({ view: "detail", appId: application.id });
      });
      card.tabIndex = 0;
      card.setAttribute("aria-label", `${application.name}. ${application.category}. Open details.`);
      return card;
    }

    function makeAppGrid(items, compact = false) {
      const grid = node("div", compact ? "store-app-grid compact" : "store-app-grid");
      if (!items.length) {
        const empty = node("div", "store-empty");
        empty.append(node("strong", "", "No matching applications"), node("p", "", "Try another search or category."));
        grid.append(empty);
        return grid;
      }
      sorted(items).forEach(application => grid.append(makeAppCard(application, compact)));
      return grid;
    }

    function makeSection(titleText, descriptionText, items, action = null) {
      const section = node("section", "store-section");
      const heading = node("div", "store-section-heading");
      const copy = node("div");
      copy.append(node("h3", "", titleText), node("p", "", descriptionText));
      heading.append(copy);
      if (action) {
        const link = node("button", "store-text-button", action.label);
        link.type = "button";
        link.dataset.storeView = action.view;
        heading.append(link);
      }
      section.append(heading, makeAppGrid(items, true));
      return section;
    }

    function sectionOf(items, titleText, descriptionText, action = null) {
      return makeSection(titleText, descriptionText, items, action);
    }

    function addFeatureBanner(container, application, eyebrow, headline, description, primaryLabel) {
      const banner = node("section", "store-feature");
      const copy = node("div", "store-feature-copy");
      copy.append(node("p", "store-eyebrow", eyebrow), node("h3", "", headline), node("p", "", description));
      const actions = node("div", "store-feature-actions");
      const details = node("button", "action-button primary", "View details");
      details.type = "button";
      details.dataset.storeAction = "details";
      details.dataset.appId = application.id;
      const primary = node("button", "store-text-button", primaryLabel);
      primary.type = "button";
      const action = appAction(application);
      primary.dataset.storeAction = action.action;
      primary.dataset.appId = application.id;
      primary.disabled = action.disabled;
      if (action.disabled) primary.title = "No compatible installer or launcher integration is available.";
      actions.append(details, primary);
      const art = node("div", "store-feature-art");
      art.setAttribute("aria-hidden", "true");
      const glyph = makeIcon(application.icon, "store-feature-glyph");
      const label = node("span", "store-feature-art-label", "NEXUS ORIGINAL");
      art.append(glyph, label);
      banner.append(copy, actions, art);
      container.append(banner);
    }

    function renderHome() {
      const wrapper = node("div", "store-page store-home");
      const featured = getApplication(featuredId);
      addFeatureBanner(
        wrapper,
        featured,
        "NEXUS ORIGINAL · BUNDLED APP",
        "Make room for what matters.",
        "NEXUS Calendar keeps your plans in a simple month view. Events stay in this browser; reminders and cloud sync are not connected.",
        catalog.isInstalled(featured) ? "Open Calendar" : "Add to launcher"
      );
      const categories = node("div", "store-category-strip");
      ["Productivity", "Games", "Utilities", "Development", "Multimedia", "Personalization"].forEach(category => {
        const button = node("button", "store-category-chip", category);
        button.type = "button";
        button.dataset.storeCategory = category;
        categories.append(button);
      });
      wrapper.append(categories);
      wrapper.append(sectionOf(
        catalog.getAll().filter(application => application.collectionIds.includes("nexus-originals") && application.capability !== "planned"),
        "Made for NEXUS",
        "First-party apps and previews. NEXUS Original is not a security certification.",
        { label: "View collection", view: "collections" }
      ));
      wrapper.append(sectionOf(
        catalog.getAll().filter(application => application.capability === "functional" && !application.installedByDefault),
        "Ready to add",
        "Bundled app code is already present; adding it registers the app in your launcher.",
        { label: "Browse apps", view: "apps" }
      ));
      const notice = node("aside", "store-trust-note");
      notice.append(
        node("strong", "", "NEXUS Verified is not active yet."),
        node("p", "", "Listings have not passed automated security checks. No app is marked verified, and third-party packages cannot be installed.")
      );
      wrapper.append(notice);
      page.append(wrapper);
    }

    function renderCollections() {
      const wrapper = node("div", "store-page");
      const intro = node("div", "store-page-intro");
      intro.append(node("h3", "", "Curated collections"), node("p", "", "Explore themed groups assembled from the current catalogue."));
      wrapper.append(intro);
      catalog.collections.forEach(collection => {
        const items = catalog.getAll().filter(application => application.collectionIds.includes(collection.id));
        const row = node("button", "store-collection-row");
        row.type = "button";
        row.dataset.storeCollection = collection.id;
        row.append(node("span", "store-collection-mark", collection.name.slice(0, 1)), node("span", "store-collection-copy", collection.name), node("small", "", `${items.length} listings`), node("span", "store-collection-arrow", "›"));
        wrapper.append(row);
      });
      page.append(wrapper);
    }

    function renderDiscover() {
      const wrapper = node("div", "store-page");
      const intro = node("div", "store-page-intro");
      intro.append(node("h3", "", "Find your next tool"), node("p", "", "Explore the catalogue by collection, capability and category."));
      wrapper.append(intro);
      catalog.collections.forEach(collection => {
        const items = catalog.getAll().filter(application => application.collectionIds.includes(collection.id));
        const row = node("button", "store-collection-row");
        row.type = "button";
        row.dataset.storeCollection = collection.id;
        row.append(node("span", "store-collection-mark", collection.name.slice(0, 1)), node("span", "store-collection-copy", collection.name), node("small", "", `${items.length} listings`), node("span", "store-collection-arrow", "›"));
        wrapper.append(row);
      });
      wrapper.append(sectionOf(catalog.getAll().filter(application => application.capability === "functional"), "Available now", "Apps with working prototype behavior.", { label: "Browse all apps", view: "apps" }));
      wrapper.append(sectionOf(catalog.getAll().filter(application => application.category === "Games"), "Games & play", "Gaming UI is a preview; it does not install or launch games.", { label: "Explore games", view: "games" }));
      page.append(wrapper);
    }

    function makeFilterControls(categories) {
      const controls = node("div", "store-filter-controls");
      const categoryLabel = node("label", "", "Category");
      const categorySelect = node("select", "store-select");
      categorySelect.id = "storeCategoryFilter";
      categorySelect.setAttribute("aria-label", "Filter by category");
      ["All", ...categories].forEach(category => {
        const option = node("option", "", category);
        option.value = category;
        option.selected = category === activeCategoryFilter;
        categorySelect.append(option);
      });
      categoryLabel.append(categorySelect);
      const sortLabel = node("label", "", "Sort");
      const sortSelect = node("select", "store-select");
      sortSelect.id = "storeSort";
      sortSelect.setAttribute("aria-label", "Sort applications");
      [["recommended", "Recommended"], ["alphabetical", "A–Z"], ["originals", "NEXUS Originals first"]].forEach(([value, label]) => {
        const option = node("option", "", label);
        option.value = value;
        option.selected = sort === value;
        sortSelect.append(option);
      });
      sortLabel.append(sortSelect);
      controls.append(categoryLabel, sortLabel);
      return controls;
    }

    function renderAppListing(items, heading, subtitle, categoryFilter = true) {
      const wrapper = node("div", "store-page");
      const intro = node("div", "store-listing-heading");
      const titleText = heading;
      intro.append(node("h3", "", titleText), node("p", "", subtitle));
      const categories = [...new Set(catalog.getAll().map(application => application.category))].sort();
      if (categoryFilter) wrapper.append(makeFilterControls(categories));
      const visible = categoryFilter && activeCategoryFilter !== "All"
        ? items.filter(application => application.category === activeCategoryFilter)
        : items;
      intro.prepend(node("p", "store-result-count", `${visible.length} ${visible.length === 1 ? "listing" : "listings"}`));
      wrapper.append(intro, makeAppGrid(visible));
      page.append(wrapper);
    }

    function renderCategories() {
      const wrapper = node("div", "store-page store-categories-page");
      const intro = node("div", "store-page-intro");
      intro.append(node("h3", "", "Browse by category"), node("p", "", "Categories show matching listings, including apps that are still planned or unavailable."));
      wrapper.append(intro);
      const grid = node("div", "store-category-grid");
      catalog.categories.forEach(category => {
        const count = catalog.getAll().filter(application => application.category === category).length;
        const button = node("button", "store-category-tile");
        button.type = "button";
        button.dataset.storeCategory = category;
        button.append(node("strong", "", category), node("span", "", `${count} ${count === 1 ? "listing" : "listings"}`), node("span", "store-category-arrow", "›"));
        grid.append(button);
      });
      wrapper.append(grid);
      page.append(wrapper);
    }

    function renderLibrary() {
      const wrapper = node("div", "store-page");
      const installed = catalog.getInstalled();
      const intro = node("div", "store-page-intro");
      intro.append(node("h3", "", "Apps in your NEXUS launcher"), node("p", "", "Desktop-included apps stay available. Optional bundled apps can be removed from the launcher."));
      wrapper.append(intro);
      if (catalog.getStorageError()) {
        wrapper.append(node("p", "store-error", catalog.getStorageError()));
      }
      if (!installed.length) wrapper.append(makeAppGrid([]));
      installed.forEach(application => {
        const row = node("article", "store-library-row");
        const icon = node("span", "store-app-icon");
        icon.append(makeIcon(application.icon));
        const copy = node("div", "store-library-copy");
        copy.append(node("strong", "", application.name), node("small", "", application.installedByDefault ? "Included with the desktop" : "Added to this browser's launcher"));
        const open = node("button", "action-button", "Open");
        open.type = "button";
        open.dataset.storeAction = "open";
        open.dataset.appId = application.id;
        row.append(icon, copy, open);
        if (catalog.canRemove(application.id)) {
          const remove = node("button", "store-text-button", "Remove");
          remove.type = "button";
          remove.dataset.storeAction = "remove";
          remove.dataset.appId = application.id;
          row.append(remove);
        }
        wrapper.append(row);
      });
      page.append(wrapper);
    }

    function renderWishlist() {
      const ids = new Set(catalog.getAll().filter(application => catalog.isWishlisted(application.id)).map(application => application.id));
      const wrapper = node("div", "store-page");
      const intro = node("div", "store-page-intro");
      intro.append(node("h3", "", "Saved for later"), node("p", "", "Your wishlist is stored locally in this browser."));
      wrapper.append(intro, makeAppGrid(catalog.getAll().filter(application => ids.has(application.id))));
      page.append(wrapper);
    }

    function renderDownloads() {
      const wrapper = node("div", "store-page");
      const intro = node("div", "store-page-intro");
      intro.append(node("h3", "", "Downloads & activity"), node("p", "", "This prototype does not download executable packages."));
      wrapper.append(intro);
      const note = node("aside", "store-trust-note");
      note.append(
        node("strong", "", "Internal installs register bundled apps instantly."),
        node("p", "", "The Calendar bundle is already part of this prototype. Adding it does not fetch files, show fake progress, or install software on your computer.")
      );
      wrapper.append(note);
      const operations = catalog.getOperations();
      if (!operations.length) {
        const empty = node("div", "store-empty store-empty-tall");
        empty.append(node("strong", "", "No activity yet"), node("p", "", "When you add or remove a supported bundled app, the action will appear here."));
        wrapper.append(empty);
      } else {
        const list = node("div", "store-operation-list");
        operations.forEach(operation => {
          const application = getApplication(operation.applicationId);
          if (!application) return;
          const row = node("article", "store-operation-row");
          const icon = node("span", "store-app-icon");
          icon.append(makeIcon(application.icon));
          row.append(icon);
          const copy = node("div", "store-operation-copy");
          copy.append(node("strong", "", `${application.name} · ${operation.kind === "add" ? "Added" : "Removed"}`), node("small", "", operation.detail));
          const completed = node("span", "store-operation-status", "Complete");
          row.append(copy, completed);
          list.append(row);
        });
        wrapper.append(list);
      }
      page.append(wrapper);
    }

    function renderUpdates() {
      const wrapper = node("div", "store-page");
      const intro = node("div", "store-page-intro");
      intro.append(node("h3", "", "Updates"), node("p", "", "Update checks require a trusted native package service."));
      wrapper.append(intro);
      const notice = node("aside", "store-trust-note");
      notice.append(
        node("strong", "", "Update status is unknown."),
        node("p", "", "The Store cannot query package versions or install updates in this browser prototype. It will not report “up to date” without checking.")
      );
      wrapper.append(notice);
      page.append(wrapper);
    }

    function renderDeveloperHub() {
      const wrapper = node("div", "store-page");
      const intro = node("div", "store-page-intro");
      intro.append(node("h3", "", "Build for NEXUS"), node("p", "", "Developer publishing is a future service, not an active submission portal."));
      const requirements = node("ul", "store-requirements");
      [
        "Publisher identity and account management",
        "Signed application bundles and reproducible metadata",
        "Automated malware and dependency review",
        "Human review, permissions disclosure and update policy",
      ].forEach(text => requirements.append(node("li", "", text)));
      const notice = node("aside", "store-trust-note");
      notice.append(node("strong", "", "No app uploads are accepted."), node("p", "", "This prototype has no publisher accounts, upload endpoint, signing service or review pipeline."));
      wrapper.append(intro, requirements, notice);
      page.append(wrapper);
    }

    function renderDetail(application) {
      if (!application) {
        page.append(node("div", "store-empty", "This listing is no longer available."));
        return;
      }
      const wrapper = node("div", "store-page store-detail");
      const identity = node("div", "store-detail-identity");
      const icon = node("span", "store-app-icon store-detail-icon");
      icon.append(makeIcon(application.icon));
      const copy = node("div", "store-detail-copy");
      copy.append(node("p", "store-eyebrow", application.type), node("h3", "", application.name), node("p", "", `${application.developer} · ${application.category}`));
      identity.append(icon, copy);
      const actionArea = node("div", "store-detail-actions");
      const action = appAction(application);
      const primary = node("button", `action-button store-detail-primary${action.disabled ? " unavailable" : " primary"}`, action.label);
      primary.type = "button";
      primary.dataset.storeAction = action.action;
      primary.dataset.appId = application.id;
      primary.disabled = action.disabled;
      if (action.disabled) primary.title = "A compatible installer or launcher integration is not available.";
      actionArea.append(primary);
      if (catalog.canRemove(application.id)) {
        const remove = node("button", "store-text-button", "Remove from launcher");
        remove.type = "button";
        remove.dataset.storeAction = "remove";
        remove.dataset.appId = application.id;
        actionArea.append(remove);
      }
      const favorite = node("button", "store-text-button", catalog.isWishlisted(application.id) ? "♥ Saved to wishlist" : "♡ Add to wishlist");
      favorite.type = "button";
      favorite.dataset.storeAction = "wishlist";
      favorite.dataset.appId = application.id;
      actionArea.append(favorite);
      const body = node("div", "store-detail-body");
      const main = node("div", "store-detail-main");
      main.append(node("p", "store-detail-description", application.description));
      const preview = node("div", "store-preview-placeholder");
      preview.append(makeIcon(application.icon, "store-preview-icon"), node("strong", "", "No screenshots supplied"), node("small", "", "This listing does not use mock product imagery."));
      main.append(preview);
      const releaseHeading = node("h4", "", "Release notes");
      main.append(releaseHeading, node("p", "store-detail-notes", application.releaseNotes));
      const metadata = node("dl", "store-detail-metadata");
      [
        ["Version", application.version || "Not released"],
        ["Size", application.size],
        ["Compatibility", application.compatibility],
        ["Rating", application.rating === null ? "Not rated" : String(application.rating)],
        ["Availability", application.capability === "functional" ? "Works in this prototype" : application.capability === "preview" ? "Preview only" : application.capability === "planned" ? "Planned" : "Unavailable"],
        ["Security status", application.trust],
      ].forEach(([term, value]) => {
        metadata.append(node("dt", "", term), node("dd", "", value));
      });
      const permissions = node("section", "store-permissions");
      permissions.append(node("h4", "", "Permissions & data"));
      const permissionList = node("ul");
      application.permissions.forEach(permission => permissionList.append(node("li", "", permission)));
      permissions.append(permissionList);
      const trust = node("p", "store-detail-security-note", "NEXUS Verified and automated security checks are not active. Listings are not endorsements or safety certifications.");
      body.append(main, node("aside", "store-detail-aside"));
      body.lastChild.append(metadata, permissions, trust);
      wrapper.append(identity, actionArea, body);
      page.append(wrapper);
    }

    function renderCollection(collectionId) {
      const collection = catalog.collections.find(item => item.id === collectionId);
      if (!collection) {
        page.append(node("div", "store-empty", "This collection is not available."));
        return;
      }
      const wrapper = node("div", "store-page");
      const intro = node("div", "store-page-intro");
      intro.append(node("h3", "", collection.name), node("p", "", collection.description));
      wrapper.append(intro, makeAppGrid(catalog.getAll().filter(application => application.collectionIds.includes(collectionId))));
      page.append(wrapper);
    }

    function renderPage() {
      title.textContent = routeTitles[route.view] || "NEXUS Store";
      back.disabled = history.length <= 1;
      root.querySelectorAll("[data-store-view]").forEach(button => {
        const selected = button.dataset.storeView === route.view || (route.view === "category" && button.dataset.storeView === (route.category === "Games" ? "games" : "apps"));
        button.setAttribute("aria-current", selected ? "page" : "false");
      });
      page.replaceChildren();
      setMessage(catalog.getStorageError());
      if (catalog.getStorageError()) message.classList.add("error");

      switch (route.view) {
        case "home": renderHome(); break;
        case "discover": renderDiscover(); break;
        case "apps": renderAppListing(catalog.getAll().filter(application => application.category !== "Games"), "Apps", "Search and filter the NEXUS catalogue."); break;
        case "games": renderAppListing(catalog.getAll().filter(application => application.category === "Games"), "Games", "Game installs and compatibility are not available in this prototype.", false); break;
        case "categories": renderCategories(); break;
        case "collections": renderCollections(); break;
        case "collection": renderCollection(route.collectionId); break;
        case "category": renderAppListing(catalog.getAll().filter(application => application.category === route.category), route.category, `Listings in ${route.category}.` , false); break;
        case "library": renderLibrary(); break;
        case "wishlist": renderWishlist(); break;
        case "downloads": renderDownloads(); break;
        case "updates": renderUpdates(); break;
        case "developer": renderDeveloperHub(); break;
        case "search":
          renderAppListing(catalog.getAll().filter(application => matchesSearch(application, query.trim().toLocaleLowerCase())), `Results for “${query.trim()}”`, "Matches include app names, descriptions, developers, categories and tags.", false);
          break;
        case "detail": renderDetail(getApplication(route.appId)); break;
        default: renderHome();
      }
    }

    function installApplication(id) {
      const application = getApplication(id);
      if (!application) return;
      try {
        catalog.install(id);
        setMessage(`${application.name} was added to the NEXUS launcher.`);
        context.notify?.(`${application.name} added to launcher`);
      } catch (error) {
        setMessage(error.message, true);
      }
    }

    function removeApplication(id) {
      const application = getApplication(id);
      if (!application) return;
      if (!window.confirm(`Remove ${application.name} from the NEXUS launcher? Its local app data will be retained.`)) return;
      try {
        catalog.remove(id);
        setMessage(`${application.name} was removed from the launcher.`);
        context.notify?.(`${application.name} removed from launcher`);
      } catch (error) {
        setMessage(error.message, true);
      }
    }

    function openApplication(id) {
      const application = getApplication(id);
      if (!application?.launchTarget || !catalog.isInstalled(application)) {
        setMessage("This app is not installed in the NEXUS launcher.", true);
        return;
      }
      if (typeof context.launchApp !== "function") {
        setMessage("The desktop launcher is unavailable.", true);
        return;
      }
      context.launchApp(application.launchTarget);
    }

    function handleAction(action, id) {
      if (action === "details") go({ view: "detail", appId: id });
      else if (action === "install") installApplication(id);
      else if (action === "remove") removeApplication(id);
      else if (action === "open") openApplication(id);
      else if (action === "wishlist") {
        try {
          const saved = catalog.toggleWishlist(id);
          setMessage(saved ? "Added to your wishlist." : "Removed from your wishlist.");
        } catch (error) {
          setMessage(error.message, true);
        }
      }
      if (action !== "open" && action !== "details") renderPage();
    }

    root.addEventListener("click", event => {
      const actionButton = event.target.closest("[data-store-action]");
      if (actionButton && !actionButton.disabled) {
        handleAction(actionButton.dataset.storeAction, actionButton.dataset.appId);
        return;
      }
      const viewButton = event.target.closest("[data-store-view]");
      if (viewButton && !viewButton.disabled) {
        activeCategoryFilter = "All";
        go({ view: viewButton.dataset.storeView });
        return;
      }
      const categoryButton = event.target.closest("[data-store-category]");
      if (categoryButton && !categoryButton.disabled) {
        activeCategoryFilter = "All";
        go({ view: "category", category: categoryButton.dataset.storeCategory });
        return;
      }
      const collectionButton = event.target.closest("[data-store-collection]");
      if (collectionButton) {
        go({ view: "collection", collectionId: collectionButton.dataset.storeCollection });
      }
    });

    root.addEventListener("input", event => {
      if (event.target !== search) return;
      query = search.value;
      if (query.trim()) {
        if (route.view !== "search") go({ view: "search" });
        else renderPage();
      } else if (route.view === "search") {
        go({ view: "apps" }, false);
      }
      search.focus();
      search.setSelectionRange(query.length, query.length);
    });

    root.addEventListener("change", event => {
      if (event.target.id === "storeCategoryFilter") {
        activeCategoryFilter = event.target.value;
        renderPage();
      } else if (event.target.id === "storeSort") {
        sort = event.target.value;
        renderPage();
      }
    });

    root.querySelector("#storeBack").addEventListener("click", goBack);
    root.addEventListener("keydown", event => {
      if ((event.metaKey || event.ctrlKey) && event.key.toLocaleLowerCase() === "k") {
        event.preventDefault();
        search.focus();
      }
      if (event.key === "Escape" && document.activeElement === search) {
        search.value = "";
        query = "";
        if (route.view === "search") go({ view: "apps" }, false);
      }
    });
    const unsubscribe = catalog.subscribe(renderPage);
    renderPage();
    return unsubscribe;
  }

  window.NexusAppRegistry.register({ id: "software", name: "NEXUS Store", render, mount });
})();
