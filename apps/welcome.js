(() => {
  const FIRSTBOOT_KEY = "nexus-firstboot-done";

  const FIRSTBOOT_STEPS = [
    {
      id: "welcome",
      title: "Welcome to NEXUS OS",
      summary: "NEXUS OS pairs a dark-first desktop experience with Linux Mint's Ubuntu-based APT ecosystem and Cinnamon desktop."
    },
    {
      id: "theme",
      title: "Choose Your Theme",
      summary: "Pick a built-in NEXUS theme preset (Midnight, Nebula, Arctic, Emerald, or Solar) and Light/Dark preference."
    },
    {
      id: "wallpaper",
      title: "Select a Wallpaper",
      summary: "Choose a verified photographic background or customise later in Settings."
    },
    {
      id: "network",
      title: "Network & Updates",
      summary: "Verify connectivity and keep Linux Mint security updates current via Mint Update Manager or APT."
    },
    {
      id: "apps",
      title: "Optional Applications",
      summary: "Install curated apps like GameMode, Lutris, Heroic, or LibreOffice safely from NEXUS Store."
    },
    {
      id: "gaming",
      title: "Gaming & Hardware Readiness",
      summary: "Inspect Vulkan/Mesa drivers, Steam & Proton compatibility, controllers, and Gaming Mode in Gaming Hub."
    },
    {
      id: "security",
      title: "Privacy, Security & Desktop Tour",
      summary: "Review UFW firewall, UEFI Secure Boot, LUKS encryption, and shortcuts (Alt+F4 close, Ctrl+Alt+Arrow snap/workspace)."
    }
  ];

  function installerServiceAvailable() {
    try {
      return Boolean(window.NexusNativeServices?.status("installer")?.available);
    } catch {
      return false;
    }
  }

  function readPreflight() {
    if (!installerServiceAvailable()) return { available: false, data: null, error: null };
    try {
      const data = window.NexusNativeServices.call("installer", "preflight");
      return { available: true, data: data && typeof data === "object" ? data : {}, error: null };
    } catch (err) {
      return { available: false, data: null, error: err?.message || "Installer preflight unavailable." };
    }
  }

  function node(tag, className, text) {
    const el = document.createElement(tag);
    if (className) el.className = className;
    if (text !== undefined) el.textContent = String(text);
    return el;
  }

  function readStorage(key) {
    try {
      return window.localStorage.getItem(key);
    } catch {
      return null;
    }
  }

  function writeStorage(key, value) {
    try {
      window.localStorage.setItem(key, value);
    } catch {
      // Ignore storage restrictions in browser preview.
    }
  }

  function render() {
    const live = installerServiceAvailable();
    return `
      <section class="welcome-app" aria-labelledby="welcomeTitle">
        <header class="app-heading">
          <div>
            <p class="app-eyebrow">NEXUS SETUP &amp; INSTALLER</p>
            <h2 class="content-title" id="welcomeTitle">NEXUS Welcome &amp; Installer</h2>
            <p class="content-sub">${live ? "Connected to Linux Mint hardware preflight & Ubiquity launcher." : "Interactive first-boot walkthrough & live-session installer guide (browser preview)."}</p>
          </div>
          <span class="integration-status">${live ? "Live Host Connected" : "Preview Mode"}</span>
        </header>
        <div class="quantum-tabs" role="tablist" aria-label="Welcome and Installer modes">
          <button type="button" class="quantum-tab active" data-welcome-mode="firstboot">First-Boot Setup</button>
          <button type="button" class="quantum-tab" data-welcome-mode="installer">Install NEXUS OS (Ubiquity)</button>
        </div>
        <div id="welcomePanel" style="margin-top:14px"></div>
        <p class="integration-note" id="welcomeStatus" role="status"></p>
      </section>`;
  }

  function mount(root, context = {}) {
    const panel = root.querySelector("#welcomePanel");
    const statusEl = root.querySelector("#welcomeStatus");
    const modeTabs = [...root.querySelectorAll("[data-welcome-mode]")];
    let mode = "firstboot";
    let stepIndex = 0;

    const setStatus = (msg, isError = false) => {
      if (!statusEl) return;
      statusEl.textContent = msg;
      statusEl.classList.toggle("error", isError);
    };

    const drawFirstBoot = () => {
      const step = FIRSTBOOT_STEPS[stepIndex];
      const done = readStorage(FIRSTBOOT_KEY) === "true";
      const card = node("article", "content-card");
      card.append(
        node("p", "settings-kicker", `STEP ${stepIndex + 1} OF ${FIRSTBOOT_STEPS.length}`),
        node("h3", "", step.title),
        node("p", "", step.summary)
      );

      if (step.id === "theme") {
        const presets = Object.values(window.NexusPersonalisationCatalog?.THEME_PRESETS || {});
        const row = node("div", "theme-preset-grid");
        presets.forEach(p => {
          const btn = node("button", "theme-preset-btn", p.label);
          btn.type = "button";
          btn.dataset.welcomeTheme = p.id;
          row.append(btn);
        });
        card.append(row);
      } else if (step.id === "wallpaper") {
        const wps = (window.NexusPersonalisationCatalog?.WALLPAPERS || []).slice(0, 4);
        const row = node("div", "theme-preset-grid");
        wps.forEach(w => {
          const btn = node("button", "theme-preset-btn", `${w.label} (${w.photographer})`);
          btn.type = "button";
          btn.dataset.welcomeWallpaper = w.id;
          row.append(btn);
        });
        card.append(row);
      } else if (step.id === "apps") {
        const btn = node("button", "action-button secondary-button", "Open NEXUS Store");
        btn.type = "button";
        btn.dataset.welcomeLaunch = "software";
        card.append(btn);
      } else if (step.id === "gaming") {
        const btn = node("button", "action-button secondary-button", "Open Gaming Hub");
        btn.type = "button";
        btn.dataset.welcomeLaunch = "gaming";
        card.append(btn);
      } else if (step.id === "security") {
        const btn = node("button", "action-button secondary-button", "Open Settings & Security Overview");
        btn.type = "button";
        btn.dataset.welcomeLaunch = "settings";
        card.append(btn);
      }

      const nav = node("div", "");
      nav.style.cssText = "display:flex;gap:8px;flex-wrap:wrap;margin-top:14px";
      const backBtn = node("button", "action-button secondary-button", "Back");
      backBtn.type = "button";
      backBtn.disabled = stepIndex === 0;
      backBtn.dataset.welcomeNav = "prev";

      const nextBtn = node(
        "button",
        "action-button primary",
        stepIndex === FIRSTBOOT_STEPS.length - 1 ? "Finish Setup" : "Next"
      );
      nextBtn.type = "button";
      nextBtn.dataset.welcomeNav = stepIndex === FIRSTBOOT_STEPS.length - 1 ? "finish" : "next";

      const skipBtn = node("button", "action-button secondary-button", done ? "Setup Completed" : "Skip Remaining Steps");
      skipBtn.type = "button";
      skipBtn.dataset.welcomeNav = "skip";

      nav.append(backBtn, nextBtn, skipBtn);
      card.append(nav);
      panel.append(card);
    };

    const drawInstaller = () => {
      const pre = readPreflight();
      if (pre.error) setStatus(pre.error, true);
      const hwCard = node("article", "content-card");
      hwCard.append(
        node("h3", "", "Linux Mint Ubiquity Installer & Hardware Check"),
        node("p", "", "NEXUS OS uses Linux Mint's Ubiquity installer for partitioning, optional LUKS encryption, user account creation, and GRUB bootloader installation. Passwords are entered only inside Ubiquity and never stored in plaintext.")
      );

      const dl = node("dl", "store-detail-metadata");
      const hw = pre.data?.hardware;
      const editionName = pre.data?.edition && pre.data.edition !== "unknown" ? pre.data.edition : "Standard/Xfce";
      const minRam = pre.data?.requirements?.edition_min_ram_mib || 2048;
      const sbState = pre.data?.secure_boot_status?.secure_boot_state || "unavailable";
      const dualBootDetected = pre.data?.dual_boot_detection?.dual_boot_candidates_detected;
      const diskSummary = hw?.disks?.length
        ? hw.disks.map(d => `${d.device} (${d.size}, ${d.model})`).join(", ")
        : (pre.available ? "None detected" : "Unavailable in browser preview");
      [
        ["Edition", pre.available ? `${editionName} (min ${minRam} MiB RAM)` : "Unavailable in browser preview"],
        ["Architecture / Firmware", pre.available ? `${pre.data.arch} · ${pre.data.firmware} (Secure Boot: ${sbState})` : "Unavailable (requires x86_64 UEFI or BIOS host)"],
        ["CPU", hw?.cpu || "Unavailable"],
        ["Memory", hw?.ram_total_mib ? `${hw.ram_total_mib} MiB (min ${minRam} MiB)` : "Unavailable"],
        ["Target disks", diskSummary],
        ["Dual-boot / Existing OS", pre.available ? (dualBootDetected ? "Existing OS partitions detected — use 'Something else' or --keep-efi" : "No conflicting OS partitions detected") : "Unavailable in browser preview"],
        ["Ubiquity installer", pre.available ? (pre.data.ubiquity_available ? "Ready (live session)" : "Not installed on this non-live host") : "Unavailable in browser preview"]
      ].forEach(([k, v]) => dl.append(node("dt", "", k), node("dd", "", v)));
      hwCard.append(dl);

      if (pre.available && Array.isArray(pre.data?.structured_warnings) && pre.data.structured_warnings.length > 0) {
        const warnList = node("ul", "");
        warnList.style.cssText = "margin:8px 0 0 18px;font-size:12px";
        pre.data.structured_warnings.slice(0, 4).forEach(w => {
          warnList.append(node("li", "", `[${String(w.severity || "info").toUpperCase()}] ${w.problem} (${w.recommended_action})`));
        });
        hwCard.append(warnList);
      }

      const optCard = node("article", "content-card");
      optCard.style.marginTop = "12px";
      optCard.append(
        node("h3", "", "Partitioning, Encryption & Recovery Guidance"),
        node("p", "", "Supported Ubiquity modes: (1) Install alongside existing OS, (2) Erase disk and install NEXUS OS, (3) Manual partitioning (Something else), and optional LUKS Full-Disk Encryption. Save any LUKS passphrase securely offline. For boot diagnostics or recovery, run `nexus-recovery --diagnose` or see docs/RECOVERY_AND_BOOT.md.")
      );

      const confirmLabel = node("label", "");
      confirmLabel.style.cssText = "display:flex;gap:8px;align-items:flex-start;margin:10px 0;font-size:12px";
      const confirmBox = document.createElement("input");
      confirmBox.type = "checkbox";
      confirmBox.id = "installerDestructiveConfirm";
      const confirmSpan = node("span", "", "I understand disk partitioning and formatting are irreversible once confirmed inside Ubiquity.");
      confirmLabel.append(confirmBox, confirmSpan);

      const launchBtn = node("button", "action-button primary", "Launch Linux Mint Ubiquity Installer");
      launchBtn.type = "button";
      launchBtn.dataset.welcomeAction = "launch-ubiquity";
      launchBtn.disabled = !pre.available || !pre.data?.ubiquity_available;
      optCard.append(confirmLabel, launchBtn);

      panel.append(hwCard, optCard);
    };

    const draw = () => {
      panel.replaceChildren();
      modeTabs.forEach(t => {
        const selected = t.dataset.welcomeMode === mode;
        t.classList.toggle("active", selected);
        if (typeof t.setAttribute === "function") {
          t.setAttribute("role", "tab");
          t.setAttribute("aria-selected", String(selected));
        }
      });
      if (mode === "firstboot") drawFirstBoot();
      else drawInstaller();
    };

    const onClick = event => {
      const tab = event.target.closest("[data-welcome-mode]");
      if (tab) {
        mode = tab.dataset.welcomeMode;
        draw();
        return;
      }
      const navBtn = event.target.closest("[data-welcome-nav]");
      if (navBtn) {
        const act = navBtn.dataset.welcomeNav;
        if (act === "prev" && stepIndex > 0) stepIndex--;
        else if (act === "next" && stepIndex < FIRSTBOOT_STEPS.length - 1) stepIndex++;
        else if (act === "finish" || act === "skip") {
          writeStorage(FIRSTBOOT_KEY, "true");
          setStatus(act === "skip" ? "First-boot setup skipped. Reopen NEXUS Welcome anytime." : "First-boot setup completed.");
        }
        draw();
        return;
      }
      const themeBtn = event.target.closest("[data-welcome-theme]");
      if (themeBtn) {
        context.desktopShell?.setThemePreset?.(themeBtn.dataset.welcomeTheme, true);
        setStatus(`Selected theme preset: ${themeBtn.dataset.welcomeTheme}`);
        return;
      }
      const wpBtn = event.target.closest("[data-welcome-wallpaper]");
      if (wpBtn) {
        context.desktopShell?.setDesktopWallpaper?.(wpBtn.dataset.welcomeWallpaper, true);
        setStatus(`Applied wallpaper: ${wpBtn.dataset.welcomeWallpaper}`);
        return;
      }
      const launchBtn = event.target.closest("[data-welcome-launch]");
      if (launchBtn) {
        context.launchApp?.(launchBtn.dataset.welcomeLaunch);
        return;
      }
      const actionBtn = event.target.closest("[data-welcome-action]");
      if (actionBtn && actionBtn.dataset.welcomeAction === "launch-ubiquity") {
        const confirmed = Boolean(root.querySelector("#installerDestructiveConfirm")?.checked);
        if (!confirmed) {
          setStatus("Please confirm that you understand disk changes in Ubiquity are irreversible.", true);
          return;
        }
        try {
          const res = window.NexusNativeServices.call("installer", "launch");
          setStatus(res?.message || "Launched Ubiquity installer.");
        } catch (err) {
          setStatus(err?.message || "Could not launch Ubiquity installer.", true);
        }
      }
    };

    root.addEventListener("click", onClick);
    draw();
    return () => root.removeEventListener("click", onClick);
  }

  window.NexusAppRegistry.register({ id: "welcome", name: "Welcome & Installer", render, mount });
})();
