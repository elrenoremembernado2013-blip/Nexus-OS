(() => {
  const EDITION_OPTIONS = [
    { id: "cinnamon", label: "NEXUS Standard (Cinnamon)" },
    { id: "xfce", label: "NEXUS Desktop (Xfce)" },
    { id: "lite-lxqt", label: "NEXUS Lite (LXQt)" },
    { id: "lite", label: "NEXUS Lite (Openbox)" }
  ];

  const ISSUE_CATEGORIES = [
    "Hardware & Drivers",
    "Installer & Boot",
    "Desktop Shell & UI",
    "Store & Packages",
    "Security & Firewall",
    "Gaming & Proton",
    "Lite Edition / Performance"
  ];

  const KNOWN_ISSUES = [
    {
      area: "Bare-metal hardware qualification",
      detail: "Physical Wi-Fi/Bluetooth/audio/suspend-resume across laptops and NVIDIA/AMD GPUs remain pending community Stage B/C testing."
    },
    {
      area: "QEMU / software rendering",
      detail: "VMs running bochs-drm or llvmpipe report Limited support and are never promoted as hardware GPU pass."
    },
    {
      area: "Offline wallpapers",
      detail: "Online photographic wallpaper downloads require HTTPS connectivity; offline installs fall back to built-in SVG/CSS backgrounds."
    }
  ];

  function hardwareAvailable() {
    try {
      return Boolean(window.NexusNativeServices?.status("hardware")?.available);
    } catch {
      return false;
    }
  }

  function callHardware(method) {
    if (!hardwareAvailable()) return { available: false, data: null, error: null, pending: null };
    try {
      const res = window.NexusNativeServices.call("hardware", method);
      if (res && typeof res.then === "function") {
        return { available: true, data: null, error: null, pending: res };
      }
      return { available: true, data: res && typeof res === "object" ? res : {}, error: null, pending: null };
    } catch (err) {
      return { available: false, data: null, error: err?.message || "Hardware service unavailable.", pending: null };
    }
  }

  function node(tag, className, text) {
    const el = document.createElement(tag);
    if (className) el.className = className;
    if (text !== undefined && text !== null) el.textContent = String(text);
    return el;
  }

  function statusClass(status) {
    const low = String(status || "").toLowerCase();
    if (low === "working") return "hw-badge hw-working";
    if (low === "limited support") return "hw-badge hw-limited";
    if (low === "detected") return "hw-badge hw-detected";
    if (low === "unsupported") return "hw-badge hw-unsupported";
    return "hw-badge hw-unable";
  }

  function downloadTextFile(filename, mimeType, text) {
    if (typeof Blob === "undefined" || typeof URL === "undefined" || typeof URL.createObjectURL !== "function") {
      return false;
    }
    const blob = new Blob([text], { type: mimeType });
    const url = URL.createObjectURL(blob);
    const a = document.createElement("a");
    a.href = url;
    a.download = filename;
    if (typeof a.click === "function") {
      a.click();
    }
    window.setTimeout?.(() => URL.revokeObjectURL?.(url), 1000);
    return true;
  }

  function formatCompatibilityMarkdown(inv) {
    const lines = [
      "# NEXUS OS Hardware Compatibility Report",
      "",
      `- **Environment:** ${(inv?.environment && inv.environment.label) || "Unavailable (Browser preview)"}`,
      `- **CPU:** ${inv?.cpu?.vendor || "Unavailable"} ${inv?.cpu?.model || ""} (${inv?.cpu?.physical_cores ?? "?"} cores / ${inv?.cpu?.logical_threads ?? "?"} threads)`,
      `- **RAM:** ${inv?.memory?.ram_total_mib ? `${inv.memory.ram_total_mib} MiB total (${inv.memory.ram_available_mib} MiB available)` : "Unavailable"}`,
      `- **UEFI / Secure Boot:** ${inv?.firmware?.mode || "Unavailable"} / ${inv?.firmware?.secure_boot || "unavailable"}`,
      "",
      "## Component Compatibility Matrix",
      ""
    ];
    const rows = Array.isArray(inv?.compatibility_report) ? inv.compatibility_report : [];
    if (!rows.length) {
      lines.push("- All components: **Unable to test** (native hardware service disconnected)");
    } else {
      rows.forEach(item => {
        lines.push(`- **${item.component}:** ${item.status} — ${item.evidence}`);
      });
    }
    lines.push("", "_Privacy notice: Serial numbers, MAC addresses, UUIDs, SSIDs, hostnames, and usernames are omitted._");
    return lines.join("\n") + "\n";
  }

  function buildBugReportPayload(formValues, diagData) {
    const payload = {
      schema_version: 1,
      product: "NEXUS OS",
      system_version: formValues.version || "0.3.0",
      edition: formValues.edition || "xfce",
      category: formValues.category || ISSUE_CATEGORIES[0],
      severity: formValues.severity || "Medium",
      steps_to_reproduce: formValues.steps || "",
      expected_behaviour: formValues.expected || "",
      actual_behaviour: formValues.actual || "",
      submitted_to_server: false,
      local_export_only: true,
      generated_at_utc: new Date().toISOString()
    };
    if (formValues.attachDiagnostics) {
      payload.diagnostics_attached = diagData || { status: "unavailable_in_preview", privacy_redacted: true };
    }
    return payload;
  }

  function render() {
    const live = hardwareAvailable();
    return `
      <section class="hardware-centre" aria-labelledby="hardwareTitle">
        <header class="app-heading">
          <div>
            <p class="app-eyebrow">COMPATIBILITY, DIAGNOSTICS &amp; BETA</p>
            <h2 class="content-title" id="hardwareTitle">Hardware &amp; Beta Centre</h2>
            <p class="content-sub">${live ? "Connected to privacy-redacted Linux Mint hardware, diagnostics, and recovery services." : "Browser preview · native hardware and diagnostics services are disconnected. No simulated hardware specs are shown."}</p>
          </div>
          <span class="integration-status" id="hardwareBadge">${live ? "Host Probe Connected" : "Preview Only"}</span>
        </header>
        <div class="quantum-tabs" role="tablist" aria-label="Hardware and Beta Centre sections">
          <button type="button" class="quantum-tab active" data-hw-tab="compatibility">Hardware Compatibility</button>
          <button type="button" class="quantum-tab" data-hw-tab="diagnostics">NEXUS Diagnostics</button>
          <button type="button" class="quantum-tab" data-hw-tab="beta">Beta Tester Centre</button>
        </div>
        <div id="hardwarePanel" style="margin-top:14px"></div>
        <p class="integration-note" id="hardwareStatus" role="status"></p>
      </section>`;
  }

  function mount(root) {
    const panel = root.querySelector("#hardwarePanel");
    const statusEl = root.querySelector("#hardwareStatus");
    const tabs = [...root.querySelectorAll("[data-hw-tab]")];
    let activeTab = "compatibility";
    let cachedInv = null;
    let cachedDiag = null;

    const bugForm = {
      category: ISSUE_CATEGORIES[0],
      edition: "xfce",
      version: "0.3.0",
      severity: "Medium",
      steps: "",
      expected: "",
      actual: "",
      attachDiagnostics: true
    };

    const setStatus = (msg, isError = false) => {
      if (!statusEl) return;
      statusEl.textContent = msg;
      statusEl.classList.toggle("error", isError);
    };

    const ensureInventory = () => {
      if (cachedInv && !cachedInv.pending) return cachedInv;
      const res = callHardware("inventory");
      if (res.pending) {
        cachedInv = { available: true, data: null, error: null, pending: true };
        setStatus("Collecting read-only hardware inventory…");
        res.pending
          .then(data => {
            cachedInv = { available: true, data: data && typeof data === "object" ? data : {}, error: null, pending: false };
            setStatus("");
            if (activeTab === "compatibility") draw();
          })
          .catch(err => {
            cachedInv = { available: false, data: null, error: err?.message || "Hardware inventory unavailable.", pending: false };
            setStatus(cachedInv.error, true);
            if (activeTab === "compatibility") draw();
          });
      } else {
        cachedInv = res;
      }
      return cachedInv;
    };

    const ensureDiagnostics = () => {
      if (cachedDiag && !cachedDiag.pending) return cachedDiag;
      const res = callHardware("diagnostics");
      if (res.pending) {
        cachedDiag = { available: true, data: null, error: null, pending: true };
        setStatus("Running safe read-only system diagnostics…");
        res.pending
          .then(data => {
            cachedDiag = { available: true, data: data && typeof data === "object" ? data : {}, error: null, pending: false };
            setStatus("");
            if (activeTab === "diagnostics") draw();
          })
          .catch(err => {
            cachedDiag = { available: false, data: null, error: err?.message || "Diagnostics unavailable.", pending: false };
            setStatus(cachedDiag.error, true);
            if (activeTab === "diagnostics") draw();
          });
      } else {
        cachedDiag = res;
      }
      return cachedDiag;
    };

    const drawCompatibility = () => {
      const state = ensureInventory();
      const inv = state.data;
      const available = Boolean(state.available && inv);

      const specsCard = node("article", "content-card");
      specsCard.append(node("h3", "", "Detected Hardware Specifications"));
      const dl = node("dl", "store-detail-metadata");

      const gpuText = inv?.gpus?.length
        ? inv.gpus.map(g => `${g.vendor_name || g.vendor}:${g.device} (${g.driver})`).join(", ")
        : (available ? "None detected" : "Unavailable");
      const wifiText = inv?.network?.wifi?.length
        ? inv.network.wifi.map(w => `${w.interface} (${w.driver}, ${w.operstate})`).join(", ")
        : (available ? "No Wi-Fi adapter detected" : "Unavailable");
      const ethText = inv?.network?.ethernet?.length
        ? inv.network.ethernet.map(e => `${e.interface} (${e.driver}, ${e.operstate})`).join(", ")
        : (available ? "No Ethernet adapter detected" : "Unavailable");
      const btText = inv?.bluetooth?.length
        ? inv.bluetooth.map(b => `${b.adapter} (${b.driver})`).join(", ")
        : (available ? "No Bluetooth adapter detected" : "Unavailable");
      const audioText = inv?.audio?.cards?.length
        ? `${inv.audio.cards.join("; ")} (${inv.audio.audio_server || "unknown"})`
        : (available ? "No ALSA cards detected" : "Unavailable");
      const storText = inv?.storage?.length
        ? inv.storage.map(s => `${s.device} ${s.size || ""} (${s.drive_type}, ${s.driver})`).join(", ") + (inv?.root_storage ? ` · / free: ${inv.root_storage.available_gib} GiB` : "")
        : (available ? "No block disks detected" : "Unavailable");
      const dispText = inv?.displays?.length
        ? inv.displays.map(d => `${d.connector} (${d.status}${d.modes?.length ? ", " + d.modes[0] : ""}${d.refresh_hz ? " @ " + d.refresh_hz + "Hz" : ""})`).join(", ")
        : (available ? "No active display connectors" : "Unavailable");
      const tpText = inv
        ? `${(inv.touchpads || []).length} touchpad(s) · ${(inv.input_devices || []).length} input device(s) · ${(inv.usb_devices || []).length} USB device(s)`
        : "Unavailable";

      [
        ["CPU", inv?.cpu ? `${inv.cpu.vendor || ""} ${inv.cpu.model || "Unavailable"} (${inv.cpu.physical_cores ?? "?"} cores / ${inv.cpu.logical_threads ?? inv.cpu.logical_cpus ?? "?"} threads)` : "Unavailable"],
        ["Memory (RAM)", inv?.memory?.ram_total_mib ? `${inv.memory.ram_used_mib ?? "?"} / ${inv.memory.ram_total_mib} MiB (${inv.memory.ram_available_mib ?? "?"} MiB available)` : "Unavailable"],
        ["GPU & Rendering", `${gpuText}${inv?.graphics_qualification?.hardware_acceleration ? " · " + inv.graphics_qualification.hardware_acceleration : ""}`],
        ["Wi-Fi", wifiText],
        ["Ethernet", ethText],
        ["Bluetooth", btText],
        ["Audio Hardware", audioText],
        ["Storage", storText],
        ["UEFI & Secure Boot", inv?.firmware ? `${inv.firmware.mode} · Secure Boot: ${inv.firmware.secure_boot}` : "Unavailable"],
        ["Display & Refresh", dispText],
        ["Touchpad & Peripherals", tpText]
      ].forEach(([k, v]) => dl.append(node("dt", "", k), node("dd", "", v)));
      specsCard.append(dl);

      const matrixCard = node("article", "content-card");
      matrixCard.style.marginTop = "12px";
      matrixCard.append(
        node("h3", "", "Compatibility Report"),
        node("p", "settings-hint", "Statuses reflect only verified evidence (Working, Limited support, Detected, Unsupported, or Unable to test). Untested hardware is never marked Working.")
      );

      const matrixList = node("div", "store-operation-list");
      matrixList.style.marginTop = "10px";
      const reportRows = Array.isArray(inv?.compatibility_report) && inv.compatibility_report.length
        ? inv.compatibility_report
        : [
            { component: "CPU & Architecture", status: "Unable to test", evidence: "Native hardware probe disconnected in browser preview." },
            { component: "Graphics, Wi-Fi, Bluetooth & Audio", status: "Unable to test", evidence: "Requires Linux host sysfs/driver inspection." },
            { component: "Storage, UEFI & Peripherals", status: "Unable to test", evidence: "Requires Linux host block and firmware inspection." }
          ];

      reportRows.forEach(item => {
        const row = node("div", "store-operation-row");
        const copy = node("div", "store-operation-copy");
        copy.append(node("strong", "", item.component), node("small", "", item.evidence));
        const badge = node("span", statusClass(item.status), item.status);
        row.append(copy, badge);
        matrixList.append(row);
      });
      matrixCard.append(matrixList);

      const exportRow = node("div", "");
      exportRow.style.cssText = "display:flex;gap:8px;flex-wrap:wrap;margin-top:12px";
      const jsonBtn = node("button", "action-button primary", "Export Compatibility JSON");
      jsonBtn.type = "button";
      jsonBtn.dataset.hwAction = "export-compat-json";
      const mdBtn = node("button", "action-button secondary-button", "Export Compatibility Markdown");
      mdBtn.type = "button";
      mdBtn.dataset.hwAction = "export-compat-md";
      const refreshBtn = node("button", "action-button secondary-button", "Refresh Probe");
      refreshBtn.type = "button";
      refreshBtn.dataset.hwAction = "refresh-hw";
      exportRow.append(jsonBtn, mdBtn, refreshBtn);
      matrixCard.append(exportRow);

      panel.append(specsCard, matrixCard);
    };

    const drawDiagnostics = () => {
      const state = ensureDiagnostics();
      const diag = state.data;
      const available = Boolean(state.available && diag);

      const diagCard = node("article", "content-card");
      diagCard.append(
        node("h3", "", "Safe System Diagnostics"),
        node("p", "settings-hint", "Strictly read-only checks. No disks are modified, no drivers are installed, and no data is uploaded automatically.")
      );

      const dl = node("dl", "store-detail-metadata");
      const failedCount = Array.isArray(diag?.failed_systemd_services) ? diag.failed_systemd_services.length : null;
      const rootMount = (diag?.storage_availability || []).find(s => s.mount === "/");
      const logErrs = diag?.system_logs?.recent_errors?.length ?? null;
      [
        ["Failed systemd services", available ? (failedCount === 0 ? "0 failed units" : `${failedCount} failed: ${diag.failed_systemd_services.map(u => u.unit).join(", ")}`) : "Unavailable"],
        ["Storage availability", rootMount ? `${rootMount.available_gib} GiB free / ${rootMount.total_gib} GiB (${rootMount.used_percent}% used)` : "Unavailable"],
        ["System logs (errors)", available ? (diag?.system_logs?.source === "unavailable" ? diag.system_logs.note : `${logErrs} recent error line(s) via ${diag.system_logs.source}`) : "Unavailable"],
        ["Network connectivity", available ? `NM: ${diag.connectivity?.networkmanager_state || "unknown"} · default route: ${diag.connectivity?.default_route_present ? "yes" : "no"}` : "Unavailable"],
        ["Package manager", available ? `dpkg: ${diag.package_manager?.dpkg_audit_status || "unknown"} · APT: ${diag.package_manager?.apt_available ? "yes" : "no"} · Flatpak: ${diag.package_manager?.flatpak_available ? "yes" : "no"}` : "Unavailable"],
        ["Security updates", available ? `${diag.security_updates?.status || "unknown"} (${diag.security_updates?.upgradable_count ?? "?"} upgradable, ${diag.security_updates?.security_origin_count ?? "?"} security)` : "Unavailable"],
        ["Hardware drivers", available ? `${(diag.inventory?.gpus || []).length} GPU(s) · ${(diag.inventory?.network?.wifi || []).length} Wi-Fi · ${diag.inventory?.firmware?.missing_firmware_hints?.length ?? 0} firmware hints` : "Unavailable"],
        ["Boot & recovery", available ? `UEFI: ${diag.boot_recovery?.uefi_active ? "yes" : "no"} · Secure Boot: ${diag.boot_recovery?.secure_boot_state || "unknown"} · EFI GRUB: ${diag.boot_recovery?.efi_grub_present ? "yes" : "no"}` : "Unavailable"]
      ].forEach(([k, v]) => dl.append(node("dt", "", k), node("dd", "", v)));
      diagCard.append(dl);

      const privacyBox = node("aside", "store-trust-note");
      privacyBox.style.marginTop = "12px";
      privacyBox.append(
        node("strong", "", "Privacy & Local Export Policy"),
        node("p", "", "Exported diagnostics include only redacted hardware models/drivers, failed systemd unit names, disk usage percentages, redacted log lines, package manager audit status, and UEFI/Secure Boot flags. Passwords, authentication tokens, private keys, MAC addresses, UUIDs, Wi-Fi SSIDs, hostnames, and personal usernames are strictly excluded. Nothing is ever uploaded automatically.")
      );

      const btnRow = node("div", "");
      btnRow.style.cssText = "display:flex;gap:8px;flex-wrap:wrap;margin-top:12px";
      const exportBtn = node("button", "action-button primary", "Export Redacted Diagnostics (JSON)");
      exportBtn.type = "button";
      exportBtn.dataset.hwAction = "export-diag-json";
      const copyBtn = node("button", "action-button secondary-button", "Copy Diagnostics Summary");
      copyBtn.type = "button";
      copyBtn.dataset.hwAction = "copy-diag";
      const refreshBtn = node("button", "action-button secondary-button", "Re-run Diagnostics");
      refreshBtn.type = "button";
      refreshBtn.dataset.hwAction = "refresh-diag";
      btnRow.append(exportBtn, copyBtn, refreshBtn);
      diagCard.append(privacyBox, btnRow);
      panel.append(diagCard);
    };

    const drawBeta = () => {
      const formCard = node("article", "content-card");
      formCard.append(
        node("h3", "", "Beta Bug Report Builder (Local Export Only)"),
        node("p", "settings-hint", "No remote bug-tracking backend is connected. Export your structured report locally and attach it to a GitHub issue after reviewing its contents.")
      );

      const grid = node("div", "");
      grid.style.cssText = "display:grid;grid-template-columns:repeat(auto-fit,minmax(170px,1fr));gap:10px;margin-top:10px";

      const catSelect = document.createElement("select");
      catSelect.id = "betaCategory";
      catSelect.setAttribute("aria-label", "Issue category");
      ISSUE_CATEGORIES.forEach(c => {
        const opt = document.createElement("option");
        opt.value = c;
        opt.textContent = c;
        if (c === bugForm.category) opt.selected = true;
        catSelect.append(opt);
      });

      const edSelect = document.createElement("select");
      edSelect.id = "betaEdition";
      edSelect.setAttribute("aria-label", "NEXUS Edition");
      EDITION_OPTIONS.forEach(e => {
        const opt = document.createElement("option");
        opt.value = e.id;
        opt.textContent = e.label;
        if (e.id === bugForm.edition) opt.selected = true;
        edSelect.append(opt);
      });

      const sevSelect = document.createElement("select");
      sevSelect.id = "betaSeverity";
      sevSelect.setAttribute("aria-label", "Issue severity");
      ["Low", "Medium", "High", "Critical"].forEach(s => {
        const opt = document.createElement("option");
        opt.value = s;
        opt.textContent = s;
        if (s === bugForm.severity) opt.selected = true;
        sevSelect.append(opt);
      });

      const verInput = document.createElement("input");
      verInput.type = "text";
      verInput.id = "betaVersion";
      verInput.value = bugForm.version;
      verInput.setAttribute("aria-label", "System version");

      [
        ["Issue Category", catSelect],
        ["Edition", edSelect],
        ["Severity", sevSelect],
        ["System Version", verInput]
      ].forEach(([lbl, ctrl]) => {
        const wrap = node("label", "setting-row");
        wrap.style.cssText = "display:flex;flex-direction:column;align-items:stretch;gap:4px;border:0;padding:0";
        wrap.append(node("span", "", lbl), ctrl);
        grid.append(wrap);
      });
      formCard.append(grid);

      const addTextarea = (id, label, placeholder, val) => {
        const wrap = node("label", "");
        wrap.style.cssText = "display:flex;flex-direction:column;gap:4px;margin-top:10px;font-size:12px";
        const ta = document.createElement("textarea");
        ta.id = id;
        ta.rows = 2;
        ta.placeholder = placeholder;
        ta.value = val;
        ta.className = "note-area";
        ta.style.minHeight = "54px";
        wrap.append(node("span", "", label), ta);
        formCard.append(wrap);
      };

      addTextarea("betaSteps", "Steps to Reproduce", "1. Open ...\n2. Click ...", bugForm.steps);
      addTextarea("betaExpected", "Expected Behaviour", "What should happen", bugForm.expected);
      addTextarea("betaActual", "Actual Behaviour", "What happened instead", bugForm.actual);

      const attachLabel = node("label", "");
      attachLabel.style.cssText = "display:flex;gap:8px;align-items:center;margin-top:10px;font-size:12px";
      const attachBox = document.createElement("input");
      attachBox.type = "checkbox";
      attachBox.id = "betaAttachDiag";
      attachBox.checked = bugForm.attachDiagnostics;
      attachLabel.append(attachBox, node("span", "", "Attach redacted local diagnostics snapshot (never auto-uploaded)"));
      formCard.append(attachLabel);

      const actionRow = node("div", "");
      actionRow.style.cssText = "display:flex;gap:8px;flex-wrap:wrap;margin-top:12px";
      const expJsonBtn = node("button", "action-button primary", "Export Bug Report (JSON)");
      expJsonBtn.type = "button";
      expJsonBtn.dataset.hwAction = "export-bug-json";
      const expMdBtn = node("button", "action-button secondary-button", "Export Bug Report (Markdown)");
      expMdBtn.type = "button";
      expMdBtn.dataset.hwAction = "export-bug-md";
      actionRow.append(expJsonBtn, expMdBtn);
      formCard.append(actionRow);

      const knownCard = node("article", "content-card");
      knownCard.style.marginTop = "12px";
      knownCard.append(node("h3", "", "Known Beta Issues & Feedback Instructions"));
      const ul = node("ul", "store-requirements");
      KNOWN_ISSUES.forEach(item => ul.append(node("li", "", `${item.area}: ${item.detail}`)));
      knownCard.append(
        ul,
        node("p", "settings-hint", "To share feedback: export your JSON/Markdown report above, review it in a text editor, and open an issue at https://github.com/elrenoremembernado2013-blip/Nexus-OS/issues.")
      );

      panel.append(formCard, knownCard);
    };

    const syncBugFormFromDom = () => {
      const cat = root.querySelector("#betaCategory");
      const ed = root.querySelector("#betaEdition");
      const sev = root.querySelector("#betaSeverity");
      const ver = root.querySelector("#betaVersion");
      const steps = root.querySelector("#betaSteps");
      const exp = root.querySelector("#betaExpected");
      const act = root.querySelector("#betaActual");
      const att = root.querySelector("#betaAttachDiag");
      if (cat) bugForm.category = cat.value;
      if (ed) bugForm.edition = ed.value;
      if (sev) bugForm.severity = sev.value;
      if (ver) bugForm.version = ver.value;
      if (steps) bugForm.steps = steps.value;
      if (exp) bugForm.expected = exp.value;
      if (act) bugForm.actual = act.value;
      if (att) bugForm.attachDiagnostics = Boolean(att.checked);
    };

    const draw = () => {
      panel.replaceChildren();
      tabs.forEach(t => {
        const selected = t.dataset.hwTab === activeTab;
        t.classList.toggle("active", selected);
        if (typeof t.setAttribute === "function") {
          t.setAttribute("role", "tab");
          t.setAttribute("aria-selected", String(selected));
        }
      });
      if (activeTab === "compatibility") drawCompatibility();
      else if (activeTab === "diagnostics") drawDiagnostics();
      else drawBeta();
    };

    const onClick = event => {
      const tab = event.target.closest("[data-hw-tab]");
      if (tab) {
        if (activeTab === "beta") syncBugFormFromDom();
        activeTab = tab.dataset.hwTab;
        draw();
        return;
      }
      const btn = event.target.closest("[data-hw-action]");
      if (!btn) return;
      const action = btn.dataset.hwAction;
      if (action === "refresh-hw") {
        cachedInv = null;
        draw();
      } else if (action === "refresh-diag") {
        cachedDiag = null;
        draw();
      } else if (action === "export-compat-json") {
        const inv = ensureInventory().data || { status: "unavailable_in_preview", compatibility_report: [] };
        downloadTextFile("nexus-hardware-compatibility.json", "application/json", JSON.stringify(inv, null, 2));
        setStatus("Exported local hardware compatibility JSON (no data uploaded).");
      } else if (action === "export-compat-md") {
        const md = formatCompatibilityMarkdown(ensureInventory().data);
        downloadTextFile("nexus-hardware-compatibility.md", "text/markdown", md);
        setStatus("Exported local hardware compatibility Markdown (no data uploaded).");
      } else if (action === "export-diag-json") {
        const diag = ensureDiagnostics().data || { status: "unavailable_in_preview", privacy_audit: { auto_upload: false } };
        downloadTextFile("nexus-diagnostics-redacted.json", "application/json", JSON.stringify(diag, null, 2));
        setStatus("Exported redacted local diagnostics JSON (no data uploaded).");
      } else if (action === "copy-diag") {
        const summary = JSON.stringify(ensureDiagnostics().data || { status: "unavailable_in_preview" }, null, 2);
        navigator?.clipboard?.writeText?.(summary).catch(() => {});
        setStatus("Prepared redacted diagnostics summary locally (no data uploaded).");
      } else if (action === "export-bug-json") {
        syncBugFormFromDom();
        const diag = bugForm.attachDiagnostics ? (ensureDiagnostics().data || null) : null;
        const report = buildBugReportPayload(bugForm, diag);
        downloadTextFile("nexus-beta-bug-report.json", "application/json", JSON.stringify(report, null, 2));
        setStatus("Exported local beta bug report JSON. No server submission was performed.");
      } else if (action === "export-bug-md") {
        syncBugFormFromDom();
        const diag = bugForm.attachDiagnostics ? (ensureDiagnostics().data || null) : null;
        const report = buildBugReportPayload(bugForm, diag);
        const md = [
          "# NEXUS OS Beta Bug Report",
          "",
          `- **Category:** ${report.category}`,
          `- **Edition:** ${report.edition}`,
          `- **System Version:** ${report.system_version}`,
          `- **Severity:** ${report.severity}`,
          "",
          "## Steps to Reproduce",
          report.steps_to_reproduce || "(none provided)",
          "",
          "## Expected Behaviour",
          report.expected_behaviour || "(none provided)",
          "",
          "## Actual Behaviour",
          report.actual_behaviour || "(none provided)",
          "",
          "## Attached Redacted Diagnostics",
          report.diagnostics_attached ? "Included (redacted local snapshot)" : "Not attached"
        ].join("\n") + "\n";
        downloadTextFile("nexus-beta-bug-report.md", "text/markdown", md);
        setStatus("Exported local beta bug report Markdown. No server submission was performed.");
      }
    };

    root.addEventListener("click", onClick);
    draw();
    return () => root.removeEventListener("click", onClick);
  }

  window.NexusAppRegistry.register({ id: "hardware", name: "Hardware & Beta Centre", render, mount });
  window.NexusHardwareReportUtils = Object.freeze({
    formatCompatibilityMarkdown,
    buildBugReportPayload
  });
})();
