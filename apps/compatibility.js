(() => {
  const STATUS_CLASSES = {
    "Native": "native",
    "Compatible": "compatible",
    "Partially compatible": "partial",
    "Experimental": "experimental",
    "Unsupported": "unsupported",
    "Not tested": "untested",
  };

  const CURATED_CATALOG = [
    {
      id: "firefox-linux",
      name: "Mozilla Firefox",
      source_os: "Linux",
      format: "APT / Flatpak",
      execution: "Native",
      runtime: "Linux APT / Flatpak",
      status: "Native",
      tested: "Tested",
      arch: ["amd64", "arm64"],
      limitations: "Hardware video decode depends on Mesa/VA-API or NVIDIA drivers.",
      guidance: "Install via NEXUS Store (APT firefox or Flathub org.mozilla.firefox).",
    },
    {
      id: "libreoffice-linux",
      name: "LibreOffice Suite",
      source_os: "Linux",
      format: "APT / Flatpak",
      execution: "Native",
      runtime: "Linux APT / Flatpak",
      status: "Native",
      tested: "Tested",
      arch: ["amd64", "arm64"],
      limitations: "Complex proprietary DOCX/XLSX macros may vary slightly.",
      guidance: "Install via NEXUS Store (APT libreoffice or Flatpak org.libreoffice.LibreOffice).",
    },
    {
      id: "appimage-generic",
      name: "Portable Linux AppImages (.AppImage)",
      source_os: "Linux",
      format: ".AppImage (ELF + SquashFS)",
      execution: "Native",
      runtime: "FUSE2 (libfuse2t64 / libfuse2)",
      status: "Compatible",
      tested: "Estimated",
      arch: ["x86_64", "aarch64"],
      limitations: "Requires matching CPU architecture, explicit user execute permission, and FUSE2 (or --appimage-extract).",
      guidance: "Verify download checksum and permissions in Compatibility Centre before running.",
    },
    {
      id: "notepadpp-win",
      name: "Notepad++ (.exe)",
      source_os: "Windows",
      format: ".exe (PE32 / PE32+)",
      execution: "Translated",
      runtime: "Wine",
      status: "Compatible",
      tested: "Estimated",
      arch: ["x86_64", "i386"],
      limitations: "Estimated from Wine compatibility tiers; isolated prefix recommended. Native equivalents: Mousepad, FeatherPad, VS Code.",
      guidance: "Create an isolated Wine prefix, inspect the .exe, and launch with confirmation.",
    },
    {
      id: "steam-proton-games",
      name: "Windows Steam Games via Proton",
      source_os: "Windows",
      format: "Steam / PE32+",
      execution: "Translated",
      runtime: "Proton (Steam Play) + Vulkan/DXVK",
      status: "Partially compatible",
      tested: "Estimated",
      arch: ["x86_64"],
      limitations: "Single-player & Valve-verified games often work; titles with kernel anti-cheat (Vanguard, Ricochet, Faceit) are Unsupported.",
      guidance: "Enable Steam Play in Steam and check Vulkan/GPU readiness in Gaming Hub.",
    },
    {
      id: "adobe-cc-win",
      name: "Adobe Creative Cloud / Photoshop (.exe)",
      source_os: "Windows",
      format: ".exe",
      execution: "Translated",
      runtime: "Wine",
      status: "Unsupported",
      tested: "Estimated",
      arch: ["x86_64"],
      limitations: "Creative Cloud background services, DRM, and GPU hooks fail reliably under Wine.",
      guidance: "Use GIMP, Krita, Darktable, or Photopea (Web App) instead.",
    },
    {
      id: "rufus-win",
      name: "Rufus USB Writer (.exe)",
      source_os: "Windows",
      format: ".exe",
      execution: "Translated",
      runtime: "Wine",
      status: "Unsupported",
      tested: "Estimated",
      arch: ["x86_64"],
      limitations: "Relies on Windows raw USB block-device drivers unavailable in Wine.",
      guidance: "Use Linux Mint USB Image Writer (mintstick) or BalenaEtcher AppImage.",
    },
    {
      id: "fdroid-android",
      name: "F-Droid & Open-Source Android APKs (.apk)",
      source_os: "Android",
      format: ".apk",
      execution: "Containerised",
      runtime: "Waydroid (LXC + Wayland)",
      status: "Compatible",
      tested: "Estimated",
      arch: ["x86_64", "arm64"],
      limitations: "Needs Waydroid + Wayland (or nested Weston on X11) + kernel binder; ARM-only APKs on x86_64 need translation.",
      guidance: "Optional on 4+ GiB RAM systems; keep disabled on Lite 512 MB / 1 GB editions.",
    },
    {
      id: "gms-banking-android",
      name: "Google Play Integrity / Banking Apps (.apk)",
      source_os: "Android",
      format: ".apk",
      execution: "Containerised",
      runtime: "Waydroid + Certified Google Play Integrity",
      status: "Unsupported",
      tested: "Estimated",
      arch: ["x86_64", "arm64"],
      limitations: "Waydroid does not bundle certified Google Play Services or Play Integrity attestation.",
      guidance: "Use the provider's official Web App in Firefox instead.",
    },
    {
      id: "macos-app-dmg",
      name: "macOS Applications (.dmg / .pkg / .app)",
      source_os: "Apple (macOS)",
      format: ".dmg / .pkg / .app",
      execution: "Unsupported",
      runtime: "None on Linux (Darwin/Mach-O)",
      status: "Unsupported",
      tested: "Tested",
      arch: ["arm64", "x86_64"],
      limitations: "Incompatible Mach-O ABI, proprietary Apple frameworks, code signing, and Apple licensing terms.",
      guidance: "Use Web Apps (iCloud Web, Apple Music Web) or native Linux equivalents (Kdenlive, Ardour, LibreOffice).",
    },
    {
      id: "ios-ipa-app",
      name: "iOS / iPadOS Apps (.ipa)",
      source_os: "Apple (iOS)",
      format: ".ipa",
      execution: "Unsupported",
      runtime: "None on Linux (iOS FairPlay/UIKit)",
      status: "Unsupported",
      tested: "Tested",
      arch: ["arm64"],
      limitations: "Encrypted App Store FairPlay binaries and iOS UIKit cannot run legally or technically on Linux.",
      guidance: "Use the service's Web App or an open-source Linux/Android alternative.",
    },
  ];

  function u16le(bytes, offset) {
    if (offset + 2 > bytes.length) return 0;
    return bytes[offset] | (bytes[offset + 1] << 8);
  }

  function u32le(bytes, offset) {
    if (offset + 4 > bytes.length) return 0;
    return (bytes[offset] | (bytes[offset + 1] << 8) | (bytes[offset + 2] << 16) | (bytes[offset + 3] << 24)) >>> 0;
  }

  function asciiSlice(bytes, start, len) {
    let out = "";
    const end = Math.min(bytes.length, start + len);
    for (let i = start; i < end; i += 1) out += String.fromCharCode(bytes[i]);
    return out;
  }

  function containsBytes(haystack, needleStr) {
    const needle = Array.from(needleStr, c => c.charCodeAt(0));
    outer: for (let i = 0; i <= haystack.length - needle.length; i += 1) {
      for (let j = 0; j < needle.length; j += 1) {
        if (haystack[i + j] !== needle[j]) continue outer;
      }
      return true;
    }
    return false;
  }

  function classifyBuffer(bytesInput, filename = "unknown", hostStatus = null) {
    const bytes = bytesInput instanceof Uint8Array ? bytesInput : new Uint8Array(bytesInput || []);
    const lower = String(filename || "").toLowerCase();
    const hostArch = hostStatus?.host?.machine || "x86_64";
    const linuxRt = hostStatus?.ecosystems?.linux || {};
    const winRt = hostStatus?.ecosystems?.windows || {};
    const androidRt = hostStatus?.ecosystems?.android || {};
    const knownHost = Boolean(hostStatus?.host);

    const out = {
      filename,
      size_bytes: bytes.length,
      executed: false,
      format: "Unknown",
      source_os: "Unknown",
      target_arch: "unknown",
      execution_kind: "Unknown",
      runtime: "None detected",
      runtime_installed: false,
      status: "Not tested",
      confidence: "Estimated compatibility (browser static header check; file was NOT executed)",
      missing_dependencies: [],
      security_notes: [
        "File was inspected read-only via header/magic bytes and has NOT been executed.",
        "Always verify publisher signatures and SHA-256 checksums before running downloaded software.",
      ],
      guidance: "Unknown format: verify the origin and avoid executing unrecognised binaries.",
    };

    // Windows PE (.exe)
    if (bytes.length >= 64 && bytes[0] === 0x4d && bytes[1] === 0x5a) {
      const peOff = u32le(bytes, 0x3c);
      const isPe = peOff + 6 <= bytes.length &&
        bytes[peOff] === 0x50 && bytes[peOff + 1] === 0x45 && bytes[peOff + 2] === 0 && bytes[peOff + 3] === 0;
      if (isPe) {
        const mach = u16le(bytes, peOff + 4);
        const archMap = { 0x014c: "i386 (32-bit x86)", 0x8664: "x86_64 (64-bit)", 0xaa64: "arm64" };
        const tArch = archMap[mach] || `0x${mach.toString(16)}`;
        const wineOk = knownHost ? Boolean(winRt.wine_installed) : false;
        out.format = "Windows PE Executable (.exe)";
        out.source_os = "Windows";
        out.target_arch = tArch;
        out.execution_kind = "Translated (Wine / Proton)";
        out.runtime = "Wine (or Proton for Steam games)";
        out.runtime_installed = wineOk;
        out.status = mach === 0xaa64 ? "Unsupported" : (knownHost ? (wineOk ? "Compatible" : "Partially compatible") : "Partially compatible");
        out.guidance = wineOk
          ? "Run inside an isolated Wine prefix after confirming publisher trust."
          : "Requires optional Wine runtime (or Proton via Steam); check native Linux alternatives first.";
        if (knownHost && !wineOk) out.missing_dependencies.push("wine / wine64 runtime");
        else if (!knownHost) out.missing_dependencies.push("Wine runtime availability unknown in browser preview");
        if (mach === 0x014c) out.security_notes.push("32-bit Windows binary requires i386 multiarch & wine32 on 64-bit Linux.");
        if (mach === 0xaa64) out.missing_dependencies.push("Windows ARM64 translation on x86_64 host");
        return out;
      }
      out.format = "Legacy DOS MZ Binary";
      out.source_os = "Windows / DOS";
      out.execution_kind = "Translated (DOSBox / Wine)";
      out.runtime = "DOSBox";
      out.status = "Experimental";
      out.guidance = "Legacy 16-bit DOS binaries require DOSBox rather than modern Wine.";
      return out;
    }

    // Windows MSI (.msi OLE Compound Document)
    if (bytes.length >= 8 && bytes[0] === 0xd0 && bytes[1] === 0xcf && bytes[2] === 0x11 && bytes[3] === 0xe0 && lower.endsWith(".msi")) {
      const wineOk = knownHost ? Boolean(winRt.wine_installed) : false;
      out.format = "Windows Installer Package (.msi)";
      out.source_os = "Windows";
      out.target_arch = "x86 / x86_64";
      out.execution_kind = "Translated (Wine msiexec)";
      out.runtime = "Wine (msiexec)";
      out.runtime_installed = wineOk;
      out.status = wineOk ? "Compatible" : "Partially compatible";
      out.guidance = "Install inside a dedicated Wine prefix via `wine msiexec /i <file>.msi` after verification.";
      if (!wineOk) out.missing_dependencies.push(knownHost ? "wine runtime" : "Wine runtime status unknown in preview");
      return out;
    }

    // Debian .deb archive
    if (bytes.length >= 24 && asciiSlice(bytes, 0, 8) === "!<arch>\n" && containsBytes(bytes.subarray(0, 128), "debian-binary")) {
      out.format = "Debian / Ubuntu Package (.deb)";
      out.source_os = "Linux";
      out.target_arch = "Inspect via dpkg-deb on Linux host";
      out.execution_kind = "Native";
      out.runtime = "APT / dpkg";
      out.runtime_installed = knownHost ? Boolean(linuxRt.apt) : false;
      out.status = "Native";
      out.confidence = "Format verified via .deb header (library dependencies checked at install time via APT)";
      out.guidance = "Install via PolicyKit (`sudo apt install ./file.deb`) only from trusted signed publishers.";
      return out;
    }

    // Linux ELF / AppImage
    if (bytes.length >= 20 && bytes[0] === 0x7f && bytes[1] === 0x45 && bytes[2] === 0x4c && bytes[3] === 0x46) {
      const eMach = u16le(bytes, 18);
      const elfArch = { 62: "x86_64", 183: "aarch64", 3: "i386" }[eMach] || `machine-${eMach}`;
      const isAppImage = (bytes.length >= 11 && bytes[8] === 0x41 && bytes[9] === 0x49 && bytes[10] === 0x02) || lower.endsWith(".appimage");
      const archMatch = elfArch === hostArch || (elfArch === "i386" && hostArch === "x86_64");
      if (isAppImage) {
        const fuseOk = knownHost ? Boolean(linuxRt.appimage_fuse2) : false;
        out.format = "Linux AppImage";
        out.source_os = "Linux";
        out.target_arch = elfArch;
        out.execution_kind = "Native (portable bundle)";
        out.runtime = "Linux kernel + FUSE2";
        out.runtime_installed = archMatch && fuseOk;
        out.status = !archMatch ? "Unsupported" : (knownHost ? (fuseOk ? "Compatible" : "Partially compatible") : "Compatible");
        out.guidance = archMatch
          ? "Verify SHA-256 checksum and explicitly enable +x permission only when ready to launch."
          : `Architecture mismatch (${elfArch} vs host ${hostArch}).`;
        if (knownHost && !fuseOk) out.missing_dependencies.push("libfuse2 / libfuse2t64 (or --appimage-extract)");
        if (!archMatch) out.missing_dependencies.push(`compatible CPU (${elfArch})`);
        return out;
      }
      out.format = "Linux Native ELF Binary";
      out.source_os = "Linux";
      out.target_arch = elfArch;
      out.execution_kind = "Native";
      out.runtime = "Linux ELF loader";
      out.runtime_installed = archMatch;
      out.status = archMatch ? "Native" : "Unsupported";
      out.guidance = "Inspect source trust before executing standalone ELF binaries.";
      return out;
    }

    // ZIP containers: Android APK vs Apple IPA
    if (bytes.length >= 4 && bytes[0] === 0x50 && bytes[1] === 0x4b && (bytes[2] === 0x03 || bytes[2] === 0x05)) {
      const hasAndroidManifest = containsBytes(bytes, "AndroidManifest.xml") || lower.endsWith(".apk");
      const hasIpaPayload = containsBytes(bytes, "Payload/") || lower.endsWith(".ipa");
      const hasGms = containsBytes(bytes, "com.google.android.gms") || containsBytes(bytes, "com.android.vending");
      if (hasAndroidManifest && !lower.endsWith(".ipa")) {
        const wdOk = knownHost ? Boolean(androidRt.waydroid_installed) : false;
        out.format = "Android Application Package (.apk)";
        out.source_os = "Android";
        out.target_arch = "Inspect APK lib/ ABIs on host";
        out.execution_kind = "Containerised (Waydroid)";
        out.runtime = "Waydroid";
        out.runtime_installed = wdOk;
        out.status = hasGms ? "Unsupported" : (wdOk ? "Compatible" : "Partially compatible");
        out.guidance = hasGms
          ? "APK references Google Play Services; apps requiring Play Integrity are Unsupported on Waydroid by default."
          : "Install inside optional Waydroid container (4+ GiB RAM recommended) after verifying APK signature.";
        if (!wdOk) out.missing_dependencies.push(knownHost ? "waydroid container runtime" : "Waydroid runtime status unknown in preview");
        if (hasGms) out.missing_dependencies.push("Google Play Services / Play Integrity (not bundled)");
        return out;
      }
      if (hasIpaPayload) {
        out.format = "Apple iOS Application Archive (.ipa)";
        out.source_os = "Apple (iOS / iPadOS)";
        out.target_arch = "arm64 (Apple Silicon)";
        out.execution_kind = "Unsupported";
        out.runtime = "None on Linux";
        out.status = "Unsupported";
        out.confidence = "Verified unsupported format (iOS FairPlay / UIKit)";
        out.guidance = "iOS .ipa apps cannot run on Linux. Use a Web App or native Linux/Android alternative.";
        return out;
      }
    }

    // Apple macOS DMG / PKG / Mach-O
    const isMachO = bytes.length >= 4 && (
      (bytes[0] === 0xfe && bytes[1] === 0xed && bytes[2] === 0xfa && bytes[3] === 0xcf) ||
      (bytes[0] === 0xcf && bytes[1] === 0xfa && bytes[2] === 0xed && bytes[3] === 0xfe) ||
      (bytes[0] === 0xca && bytes[1] === 0xfe && bytes[2] === 0xba && bytes[3] === 0xbe)
    );
    const isXar = bytes.length >= 4 && asciiSlice(bytes, 0, 4) === "xar!";
    if (lower.endsWith(".dmg") || lower.endsWith(".pkg") || isXar || isMachO || containsBytes(bytes.subarray(Math.max(0, bytes.length - 512)), "koly")) {
      out.format = lower.endsWith(".dmg") ? "Apple macOS Disk Image (.dmg)" : (isXar || lower.endsWith(".pkg") ? "Apple macOS Installer (.pkg)" : "Apple Mach-O Binary");
      out.source_os = "Apple (macOS)";
      out.target_arch = "arm64 / x86_64 (Darwin Mach-O)";
      out.execution_kind = "Unsupported";
      out.runtime = "None on Linux (Darwin/XNU)";
      out.status = "Unsupported";
      out.confidence = "Verified unsupported OS format & Apple licensing restriction";
      out.guidance = "macOS apps cannot run on Linux. Use Web Apps (e.g. iCloud.com) or Linux-native alternatives (LibreOffice, GIMP, Kdenlive, Ardour).";
      return out;
    }

    // Flatpak ref
    if (lower.endsWith(".flatpakref") || lower.endsWith(".flatpak") || containsBytes(bytes.subarray(0, 256), "[Flatpak Ref]")) {
      const fpOk = knownHost ? Boolean(linuxRt.flatpak) : false;
      out.format = "Linux Flatpak Reference / Bundle";
      out.source_os = "Linux";
      out.target_arch = hostArch;
      out.execution_kind = "Containerised (Flatpak sandbox)";
      out.runtime = "Flatpak";
      out.runtime_installed = fpOk;
      out.status = fpOk ? "Native" : "Partially compatible";
      out.guidance = fpOk ? "Install via Flatpak and review portal permissions in Settings -> Privacy & Security." : "Install Flatpak via NEXUS Store.";
      if (!fpOk) out.missing_dependencies.push("flatpak");
      return out;
    }

    return out;
  }

  window.NexusCompatibilityClassifier = Object.freeze({
    CURATED_CATALOG,
    STATUS_CLASSES,
    classifyBuffer,
  });

  function compatAvailable() {
    try {
      return Boolean(window.NexusNativeServices?.status("compatibility")?.available);
    } catch {
      return false;
    }
  }

  function el(tag, className, text) {
    const node = document.createElement(tag);
    if (className) node.className = className;
    if (text !== undefined) node.textContent = text;
    return node;
  }

  function makeStatusBadge(status) {
    const cls = STATUS_CLASSES[status] || "untested";
    return el("span", `compat-badge compat-${cls}`, status);
  }

  function render() {
    const connected = compatAvailable();
    return `
      <section class="compat-centre" aria-labelledby="compatTitle">
        <header class="app-heading">
          <div>
            <p class="app-eyebrow">CROSS-PLATFORM APPLICATION COMPATIBILITY</p>
            <h2 class="content-title" id="compatTitle">NEXUS Compatibility Centre</h2>
            <p class="content-sub">${connected ? "Connected to live host runtime, architecture, and magic-byte inspection services." : "Browser preview · static format inspection works locally; host runtime probes require the Linux bridge."}</p>
          </div>
          <span class="integration-status" id="compatBadge">${connected ? "Host Runtime Probe Connected" : "Preview · Static Inspector"}</span>
        </header>
        <div class="quantum-tabs" role="tablist" aria-label="Compatibility Centre sections">
          <button type="button" class="quantum-tab active" data-compat-tab="runtimes">Runtimes &amp; Host</button>
          <button type="button" class="quantum-tab" data-compat-tab="inspect">Inspect File</button>
          <button type="button" class="quantum-tab" data-compat-tab="directory">4 Ecosystems</button>
          <button type="button" class="quantum-tab" data-compat-tab="security">Prefixes &amp; Security</button>
        </div>
        <div id="compatPanel" style="margin-top:14px"></div>
        <p class="integration-note" id="compatStatus" role="status"></p>
      </section>`;
  }

  function mount(root) {
    const panel = root.querySelector("#compatPanel");
    const statusEl = root.querySelector("#compatStatus");
    const tabs = [...root.querySelectorAll("[data-compat-tab]")];
    let activeTab = "runtimes";
    let hostState = null;
    let catalogRows = CURATED_CATALOG;
    let inspectionResult = null;
    let ecosystemFilter = "All";

    const setStatus = (msg, isError = false) => {
      if (!statusEl) return;
      statusEl.textContent = msg;
      statusEl.classList.toggle("error", isError);
    };

    const refreshHost = () => {
      if (!compatAvailable()) return;
      try {
        Promise.resolve(window.NexusNativeServices.call("compatibility", "status"))
          .then(data => {
            hostState = data;
            draw();
          })
          .catch(err => setStatus(err?.message || "Could not probe host runtimes.", true));
        Promise.resolve(window.NexusNativeServices.call("compatibility", "catalog"))
          .then(data => {
            if (Array.isArray(data?.entries) && data.entries.length) {
              catalogRows = data.entries;
              if (activeTab === "directory") draw();
            }
          })
          .catch(() => {});
      } catch (err) {
        setStatus(err?.message || "Compatibility service unavailable.", true);
      }
    };

    const drawRuntimes = () => {
      const box = el("div", "compat-grid");
      const h = hostState?.host;
      const eco = hostState?.ecosystems;

      // Host summary banner
      const hostCard = el("article", "compat-card compat-card-wide");
      hostCard.append(el("h3", "", "Host Architecture & Hardware Envelope"));
      if (h) {
        hostCard.append(el("p", "compat-meta",
          `Architecture: ${h.machine} (dpkg: ${h.dpkg_arch}) · Foreign multiarch: ${h.i386_multiarch ? "i386 enabled" : "none"} · RAM: ${h.mem_total_mib ?? "?"} MiB${h.low_ram ? " (Low-RAM profile)" : ""} · Session: ${h.session_type} · Edition: ${h.desktop_env}`));
      } else {
        hostCard.append(el("p", "compat-meta",
          "Browser preview: CPU architecture, kernel binder support, Wine/Proton, and Waydroid installation state cannot be verified without the Linux host bridge."));
      }
      box.append(hostCard);

      // 1. Linux
      const linuxCard = el("article", "compat-card");
      const lxHead = el("div", "compat-card-head");
      lxHead.append(el("strong", "", "1. Linux Ecosystem"), makeStatusBadge("Native"));
      linuxCard.append(lxHead);
      if (eco?.linux) {
        linuxCard.append(el("p", "", `APT / dpkg: ${eco.linux.apt ? "Available" : "Unavailable"} · Flatpak: ${eco.linux.flatpak ? `Installed (${(eco.linux.flatpak_remotes || []).join(", ") || "no remotes"})` : "Not installed"} · AppImage FUSE2: ${eco.linux.appimage_fuse2 ? "Ready" : "Missing libfuse2"}.`));
      } else {
        linuxCard.append(el("p", "", "Supports APT (.deb), Flatpak sandboxes, portable .AppImage bundles (requires FUSE2), and native ELF binaries."));
      }
      if (compatAvailable() && eco?.linux && !eco.linux.flatpak) {
        const btn = el("button", "action-button primary", "Install Flatpak (optional)");
        btn.type = "button";
        btn.addEventListener("click", () => installRuntime("flatpak"));
        linuxCard.append(btn);
      }
      box.append(linuxCard);

      // 2. Windows
      const winCard = el("article", "compat-card");
      const winStatus = eco?.windows?.wine_installed || eco?.windows?.proton_versions?.length ? "Compatible" : "Partially compatible";
      const wnHead = el("div", "compat-card-head");
      wnHead.append(el("strong", "", "2. Windows Ecosystem (Wine & Proton)"), makeStatusBadge(eco ? (eco.windows?.wine_installed ? "Compatible" : "Not tested") : "Not tested"));
      winCard.append(wnHead);
      if (eco?.windows) {
        const w = eco.windows;
        winCard.append(el("p", "", `Wine: ${w.wine_installed ? w.wine_version : "Not installed"} · Proton: ${w.proton_versions?.length ? w.proton_versions.join(", ") : "None detected"} · Lutris: ${w.lutris ? "Yes" : "No"} · Isolated prefixes: ${w.prefixes?.length || 0}.`));
        if (!w.wine_installed && compatAvailable()) {
          const btn = el("button", "action-button primary", "Install optional Wine runtime");
          btn.type = "button";
          btn.addEventListener("click", () => installRuntime("wine"));
          winCard.append(btn);
        }
      } else {
        winCard.append(el("p", "", "Runs compatible .exe/.msi apps via Wine and Windows games via Steam Proton. Kernel anti-cheat and low-level Windows drivers are Unsupported."));
      }
      box.append(winCard);

      // 3. Android
      const andCard = el("article", "compat-card");
      const andHead = el("div", "compat-card-head");
      const andBadge = eco?.android?.waydroid_installed ? "Compatible" : (h?.low_ram || h?.is_lite_edition ? "Experimental" : "Not tested");
      andHead.append(el("strong", "", "3. Android Ecosystem (Waydroid)"), makeStatusBadge(andBadge));
      andCard.append(andHead);
      if (eco?.android) {
        const a = eco.android;
        andCard.append(el("p", "", `Waydroid: ${a.waydroid_installed ? `${a.waydroid_version || "installed"} (${a.container_status})` : "Not installed"} · Wayland ready: ${a.wayland_ready ? "Yes" : "Needs Weston/Cage on X11"} · Binder: ${a.binder_ready ? "Ready" : "Unavailable"} · Google Play Services: Not included.`));
        if (h?.low_ram || h?.is_lite_edition) {
          andCard.append(el("p", "compat-warn", "Low-RAM / Lite Edition note: Waydroid container is optional and NOT recommended below 3.5 GiB RAM."));
        } else if (!a.waydroid_installed && compatAvailable()) {
          const btn = el("button", "action-button primary", "Install optional Waydroid");
          btn.type = "button";
          btn.addEventListener("click", () => installRuntime("waydroid"));
          andCard.append(btn);
        }
      } else {
        andCard.append(el("p", "", "Optional Waydroid LXC container runs compatible open-source Android APKs. Google Play Services & Play Integrity are NOT included by default; skipped on Lite/low-RAM machines."));
      }
      box.append(andCard);

      // 4. Apple
      const appleCard = el("article", "compat-card");
      const apHead = el("div", "compat-card-head");
      apHead.append(el("strong", "", "4. Apple Ecosystem (macOS & iOS)"), makeStatusBadge("Unsupported"));
      appleCard.append(apHead);
      appleCard.append(el("p", "", "Direct macOS (.dmg/.pkg/.app) and iOS (.ipa) execution is unsupported due to Darwin Mach-O ABI, FairPlay DRM, code signing, and Apple licensing terms. Use Web Apps (iCloud Web) or Linux equivalents (LibreOffice, GIMP, Kdenlive, Ardour)."));
      box.append(appleCard);

      panel.replaceChildren(box);
    };

    const installRuntime = rt => {
      if (!compatAvailable()) {
        setStatus("Runtime installation requires the Linux host bridge.", true);
        return;
      }
      if (!window.confirm(`Install optional ${rt} runtime via Linux Mint APT (PolicyKit confirmation required)?`)) return;
      setStatus(`Preparing ${rt} runtime installation…`);
      Promise.resolve(window.NexusNativeServices.call("compatibility", "installRuntime", rt, false))
        .then(res => {
          if (res?.ok === false) {
            setStatus(res.message || `Could not install ${rt}.`, true);
          } else {
            setStatus(res?.message || `${rt} installation completed.`);
            refreshHost();
          }
        })
        .catch(err => setStatus(err?.message || `Failed to install ${rt}.`, true));
    };

    const drawInspect = () => {
      const wrap = el("div", "compat-inspect");
      const controls = el("div", "compat-inspect-controls");

      const fileLabel = el("label", "compat-file-picker");
      fileLabel.append(el("strong", "", "Inspect local installer or binary (read-only, never executed)"));
      const fileInput = el("input");
      fileInput.type = "file";
      fileInput.setAttribute("aria-label", "Choose file to inspect format and compatibility");
      fileInput.addEventListener("change", async () => {
        const file = fileInput.files?.[0];
        if (!file) return;
        try {
          const headSlice = new Uint8Array(await file.slice(0, 65536).arrayBuffer());
          let buf = headSlice;
          if (file.size > 65536 && file.name.toLowerCase().endsWith(".dmg")) {
            const tailSlice = new Uint8Array(await file.slice(Math.max(0, file.size - 512)).arrayBuffer());
            const combined = new Uint8Array(headSlice.length + tailSlice.length);
            combined.set(headSlice, 0);
            combined.set(tailSlice, headSlice.length);
            buf = combined;
          }
          inspectionResult = classifyBuffer(buf, file.name, hostState);
          inspectionResult.size_bytes = file.size;
          setStatus(`Inspected ${file.name} read-only (file was NOT executed).`);
          draw();
        } catch (err) {
          setStatus(err?.message || "Could not read selected file.", true);
        }
      });
      fileLabel.append(fileInput);
      controls.append(fileLabel);

      if (compatAvailable()) {
        const homeForm = el("form", "compat-home-form");
        const pathInput = el("input");
        pathInput.type = "text";
        pathInput.placeholder = "Home path, e.g. Downloads/app.exe or ~/app.apk";
        pathInput.setAttribute("aria-label", "Inspect file in home directory");
        const btn = el("button", "action-button primary", "Inspect Home File");
        btn.type = "submit";
        homeForm.append(pathInput, btn);
        homeForm.addEventListener("submit", ev => {
          ev.preventDefault();
          const p = pathInput.value.trim();
          if (!p) return;
          setStatus(`Inspecting ${p} on Linux host…`);
          Promise.resolve(window.NexusNativeServices.call("compatibility", "inspect", p))
            .then(res => {
              inspectionResult = res;
              setStatus(`Inspected ${res.filename || p} read-only.`);
              draw();
            })
            .catch(err => setStatus(err?.message || "File inspection failed.", true));
        });
        controls.append(homeForm);
      }

      wrap.append(controls);

      if (inspectionResult) {
        const card = el("article", "compat-card compat-card-wide");
        const head = el("div", "compat-card-head");
        head.append(el("strong", "", inspectionResult.filename || "Inspection Result"), makeStatusBadge(inspectionResult.status || "Not tested"));
        card.append(head);

        const dl = el("dl", "compat-dl");
        [
          ["Detected Format", inspectionResult.format],
          ["Source OS", inspectionResult.source_os],
          ["Target Architecture", inspectionResult.target_arch],
          ["Execution Method", inspectionResult.execution_kind],
          ["Required Runtime", `${inspectionResult.runtime} (${inspectionResult.runtime_installed ? "Installed" : "Not installed / Unknown"})`],
          ["Confidence", inspectionResult.confidence],
          ["Missing Dependencies", inspectionResult.missing_dependencies?.length ? inspectionResult.missing_dependencies.join(", ") : "None detected"],
          ["Guidance", inspectionResult.guidance],
        ].forEach(([k, v]) => {
          dl.append(el("dt", "", k), el("dd", "", String(v || "—")));
        });
        card.append(dl);
        if (Array.isArray(inspectionResult.security_notes)) {
          const ul = el("ul", "compat-sec-list");
          inspectionResult.security_notes.forEach(note => ul.append(el("li", "", note)));
          card.append(ul);
        }
        wrap.append(card);
      } else {
        wrap.append(el("p", "compat-meta", "Select a .deb, .AppImage, .flatpakref, .exe, .msi, .apk, .dmg, .pkg, or .ipa file to inspect its real format, architecture, and compatibility without running it."));
      }

      panel.replaceChildren(wrap);
    };

    const drawDirectory = () => {
      const wrap = el("div", "compat-directory");
      const filterBar = el("div", "compat-filter-bar");
      ["All", "Linux", "Windows", "Android", "Apple"].forEach(ecoName => {
        const btn = el("button", `quantum-tab${ecosystemFilter === ecoName ? " active" : ""}`, ecoName);
        btn.type = "button";
        btn.addEventListener("click", () => {
          ecosystemFilter = ecoName;
          drawDirectory();
        });
        filterBar.append(btn);
      });
      wrap.append(filterBar);

      const list = el("div", "compat-dir-list");
      catalogRows
        .filter(item => ecosystemFilter === "All" || String(item.source_os || "").startsWith(ecosystemFilter))
        .forEach(item => {
          const row = el("article", "compat-card");
          const head = el("div", "compat-card-head");
          head.append(el("strong", "", item.name), makeStatusBadge(item.status));
          row.append(
            head,
            el("p", "compat-meta", `${item.source_os} · ${item.format} · ${item.execution} · ${item.tested} compatibility · Runtime: ${item.runtime}`),
            el("p", "", item.limitations),
            el("p", "compat-guidance", item.guidance)
          );
          list.append(row);
        });
      wrap.append(list);
      panel.replaceChildren(wrap);
    };

    const drawSecurity = () => {
      const wrap = el("div", "compat-grid");
      const secCard = el("article", "compat-card compat-card-wide");
      secCard.append(el("h3", "", "Isolation, Permissions & Least-Privilege Policy"));
      const ul = el("ul", "compat-sec-list");
      [
        "Downloaded .exe, .msi, .AppImage, and .apk files are NEVER executed automatically.",
        "Wine runs each environment inside isolated prefixes (~/.local/share/nexus-os/wine-prefixes/<name>) rather than mixing system paths.",
        "Waydroid runs Android inside an unprivileged LXC container without certified Google Play Services unless explicitly configured by the user.",
        "Linux security protections (UFW firewall, PolicyKit pkexec prompts, APT GPG verification, Flatpak portals) are never disabled for compatibility.",
        "Lite editions (Openbox / LXQt) never force Wine, Proton, or Waydroid onto low-RAM systems.",
      ].forEach(line => ul.append(el("li", "", line)));
      secCard.append(ul);
      wrap.append(secCard);

      const prefixCard = el("article", "compat-card compat-card-wide");
      prefixCard.append(el("h3", "", "Isolated Wine Prefix Manager"));
      const existing = hostState?.ecosystems?.windows?.prefixes || [];
      prefixCard.append(el("p", "compat-meta", existing.length
        ? `Existing isolated prefixes: ${existing.map(p => p.name).join(", ")}`
        : "No isolated NEXUS Wine prefixes created yet (location: ~/.local/share/nexus-os/wine-prefixes/)."));

      if (compatAvailable()) {
        const form = el("form", "compat-home-form");
        const input = el("input");
        input.type = "text";
        input.placeholder = "New prefix slug (e.g. productivity-win)";
        input.setAttribute("aria-label", "Wine prefix name");
        const btn = el("button", "action-button primary", "Create Isolated Prefix");
        btn.type = "submit";
        form.append(input, btn);
        form.addEventListener("submit", ev => {
          ev.preventDefault();
          const name = input.value.trim();
          if (!name) return;
          Promise.resolve(window.NexusNativeServices.call("compatibility", "createPrefix", name))
            .then(res => {
              setStatus(`Created isolated Wine prefix "${res.name}" at ${res.path}.`);
              input.value = "";
              refreshHost();
            })
            .catch(err => setStatus(err?.message || "Could not create prefix.", true));
        });
        prefixCard.append(form);
      }
      wrap.append(prefixCard);

      panel.replaceChildren(wrap);
    };

    const draw = () => {
      tabs.forEach(t => t.classList.toggle("active", t.dataset.compatTab === activeTab));
      if (activeTab === "runtimes") drawRuntimes();
      else if (activeTab === "inspect") drawInspect();
      else if (activeTab === "directory") drawDirectory();
      else drawSecurity();
    };

    tabs.forEach(t => {
      t.addEventListener("click", () => {
        activeTab = t.dataset.compatTab;
        draw();
      });
    });

    draw();
    refreshHost();
    return () => {};
  }

  window.NexusAppRegistry.register({
    id: "compatibility",
    name: "Compatibility Centre",
    render,
    mount,
  });
})();
