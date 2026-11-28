(() => {
  const maxPreviewBytes = 1024 * 1024;
  const textExtensions = /\.(txt|md|markdown|csv|json|xml|yaml|yml|log|ini|cfg|conf|html|css|js|ts|sh|py|c|h|cpp|rs)$/i;

  function validName(name) {
    if (typeof name !== "string") return false;
    const trimmed = name.trim();
    return Boolean(trimmed && trimmed !== "." && trimmed !== ".." && !/[\\/]/.test(trimmed));
  }

  function nativeFilesAvailable() {
    try {
      return Boolean(window.NexusNativeServices?.status("files")?.available);
    } catch {
      return false;
    }
  }

  function render() {
    const isNative = nativeFilesAvailable();
    return `
      <section class="file-manager" aria-labelledby="filesTitle">
        <header class="app-heading">
          <div>
            <p class="app-eyebrow">${isNative ? "LINUX HOME FILES" : "PERSONAL FILES"}</p>
            <h2 class="content-title" id="filesTitle">File Manager</h2>
            <p class="content-sub">${isNative ? "Connected to your Linux home folder (~); protected system and credential paths stay blocked." : "Your files stay under your control."}</p>
          </div>
          <div class="files-open-actions">
            ${isNative ? '<button type="button" class="action-button secondary-button" id="filesOpenNative">Open native app</button>' : ""}
            <button type="button" class="action-button" id="filesChooseFolder">Choose folder</button>
            <label class="action-button files-open-label" for="filesOpenInput">Open files</label>
            <input id="filesOpenInput" class="visually-hidden" type="file" multiple aria-label="Open files for read-only preview">
          </div>
        </header>
        <div class="files-layout">
          <aside class="files-sidebar" aria-label="File locations">
            <p class="app-eyebrow">LOCATIONS</p>
            <button type="button" class="files-location selected" id="filesHomeLocation" aria-current="location"><span aria-hidden="true">⌂</span> ${isNative ? "Home (~)" : "Selected folder"}</button>
            ${isNative ? '<button type="button" class="files-location" data-native-loc="~/Documents">Documents</button><button type="button" class="files-location" data-native-loc="~/Downloads">Downloads</button><button type="button" class="files-location" data-native-loc="~/Desktop">Desktop</button>' : ""}
            <div class="files-sidebar-note">${isNative ? "Confined strictly to your user $HOME directory (.ssh/.gnupg hidden)." : "Only a folder you choose is available to this app."}</div>
            <div class="files-storage" id="filesStorage" role="status">${isNative ? "Connecting to $HOME…" : "No folder selected"}</div>
          </aside>
          <div class="files-main">
            <nav class="files-breadcrumbs" id="filesBreadcrumbs" aria-label="Current folder"></nav>
            <div class="files-toolbar" role="group" aria-label="File actions">
              <label class="files-search"><span aria-hidden="true">⌕</span><input id="filesSearch" type="search" placeholder="Search this folder" aria-label="Search current folder"></label>
              <button type="button" class="action-button" id="filesNewFolder" disabled>New folder</button>
              <button type="button" class="action-button" id="filesNewFile" disabled>New text file</button>
              <button type="button" class="action-button" id="filesRename" disabled>Rename</button>
              <button type="button" class="action-button" id="filesCopy" disabled>Copy</button>
              <button type="button" class="action-button" id="filesCut" disabled>Cut</button>
              <button type="button" class="action-button" id="filesPaste" disabled>Paste</button>
              <button type="button" class="action-button files-danger" id="filesDelete" disabled>Delete</button>
            </div>
            <p class="files-status" id="filesStatus" role="status" aria-live="polite">${isNative ? "Loading your Linux home folder…" : "Choose a folder to browse it, or open individual files for read-only preview."}</p>
            <div class="files-list-wrap">
              <table class="files-table">
                <thead><tr><th scope="col">Name</th><th scope="col">Kind</th><th scope="col">Size</th><th scope="col">Modified</th></tr></thead>
                <tbody id="filesRows"></tbody>
              </table>
            </div>
          </div>
          <aside class="files-preview" aria-label="File preview" id="filesPreview">
            <p class="app-eyebrow">PREVIEW</p>
            <p class="files-preview-empty">Select a file to preview it.</p>
          </aside>
        </div>
        <p class="integration-note">${isNative ? "Native File Manager mode accesses only your regular user $HOME directory through the authenticated loopback bridge." : "Folder access uses the browser's explicit directory picker and is limited to the folder you grant. Removable-device management and system-wide storage details require native Linux integration."}</p>
      </section>`;
  }

  function mount(root) {
    const $ = selector => root.querySelector(selector);
    const rows = $("#filesRows");
    const status = $("#filesStatus");
    const search = $("#filesSearch");
    const preview = $("#filesPreview");
    const storage = $("#filesStorage");
    const chooseFolder = $("#filesChooseFolder");
    const openInput = $("#filesOpenInput");
    let rootHandle = null;
    let currentHandle = null;
    let path = [];
    let selectedEntry = null;
    let clipboard = null;
    let openedFiles = [];
    let previewUrl = null;
    let previewGeneration = 0;
    let listingGeneration = 0;
    let nativeMode = nativeFilesAvailable();
    let nativeHome = "";
    let nativeCurrentPath = "";

    chooseFolder.disabled = typeof window.showDirectoryPicker !== "function";
    chooseFolder.title = chooseFolder.disabled
      ? "This browser does not support secure folder access; use Open files for read-only previews."
      : "Choose one folder and grant access to it.";

    function setStatus(message, isError = false) {
      status.textContent = message;
      status.classList.toggle("error", isError);
    }

    function prettySize(bytes) {
      if (!Number.isFinite(bytes) || bytes < 0) return "—";
      if (bytes < 1024) return `${bytes} B`;
      if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`;
      return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
    }

    function clearPreview() {
      previewGeneration++;
      if (previewUrl) URL.revokeObjectURL(previewUrl);
      previewUrl = null;
      preview.replaceChildren();
      const label = document.createElement("p");
      label.className = "app-eyebrow";
      label.textContent = "PREVIEW";
      const empty = document.createElement("p");
      empty.className = "files-preview-empty";
      empty.textContent = "Select a file to preview it.";
      preview.append(label, empty);
    }

    async function entryFile(entry) {
      return entry.file || entry.handle.getFile();
    }

    async function showPreview(entry) {
      clearPreview();
      const request = previewGeneration;
      const title = document.createElement("h3");
      title.className = "files-preview-title";
      title.textContent = entry.name;
      preview.append(title);
      if (entry.kind === "directory") {
        const note = document.createElement("p");
        note.className = "files-preview-empty";
        note.textContent = "Folders do not have a file preview.";
        preview.append(note);
        return;
      }

      try {
        if (entry.nativePath && nativeMode) {
          const data = await window.NexusNativeServices.call("files", "preview", entry.nativePath);
          if (request !== previewGeneration) return;
          if (data?.tooLarge) {
            preview.append(Object.assign(document.createElement("p"), {
              className: "files-preview-empty",
              textContent: `Preview is limited to 256 KB. This file is ${prettySize(data.size)}.`
            }));
            return;
          }
          if (data?.binary || data?.text === null || data?.text === undefined) {
            preview.append(Object.assign(document.createElement("p"), {
              className: "files-preview-empty",
              textContent: `${entry.mode || ""} · Binary or non-text file (${prettySize(entry.size)})`
            }));
            return;
          }
          const pre = document.createElement("pre");
          pre.className = "files-text-preview";
          pre.textContent = data.text;
          preview.append(pre);
          return;
        }
        const file = await entryFile(entry);
        if (request !== previewGeneration) return;
        if (file.size > maxPreviewBytes) {
          const note = document.createElement("p");
          note.className = "files-preview-empty";
          note.textContent = `Preview is limited to ${prettySize(maxPreviewBytes)}. This file is ${prettySize(file.size)}.`;
          preview.append(note);
          return;
        }
        if (file.type.startsWith("image/")) {
          if (request !== previewGeneration) return;
          previewUrl = URL.createObjectURL(file);
          const image = document.createElement("img");
          image.className = "files-image-preview";
          image.src = previewUrl;
          image.alt = `Preview of ${entry.name}`;
          preview.append(image);
          return;
        }
        if (file.type.startsWith("text/") || textExtensions.test(entry.name)) {
          const text = document.createElement("pre");
          text.className = "files-text-preview";
          text.textContent = await file.text();
          if (request !== previewGeneration) return;
          preview.append(text);
          return;
        }
        const note = document.createElement("p");
        note.className = "files-preview-empty";
        note.textContent = file.type || "Preview is not available for this file type.";
        preview.append(note);
      } catch (error) {
        if (request !== previewGeneration) return;
        setStatus(`Could not preview this file: ${error.message}`, true);
      }
    }

    function updateActions() {
      if (nativeMode && !currentHandle) {
        const hasSelection = Boolean(selectedEntry?.nativePath);
        $("#filesNewFolder").disabled = false;
        $("#filesNewFile").disabled = false;
        $("#filesRename").disabled = !hasSelection;
        $("#filesCopy").disabled = true;
        $("#filesCut").disabled = true;
        $("#filesPaste").disabled = true;
        $("#filesDelete").disabled = !hasSelection;
        return;
      }
      const hasWritableFolder = Boolean(currentHandle);
      const renameButton = $("#filesRename");
      const canMove = Boolean(selectedEntry?.handle && typeof selectedEntry.handle.move === "function");
      $("#filesNewFolder").disabled = !hasWritableFolder;
      $("#filesNewFile").disabled = !hasWritableFolder;
      renameButton.disabled = !hasWritableFolder || !canMove;
      renameButton.title = hasWritableFolder && selectedEntry?.handle && !canMove
        ? "Rename requires a browser that supports FileSystemHandle.move()."
        : "";
      $("#filesCopy").disabled = !hasWritableFolder || !selectedEntry?.handle;
      $("#filesCut").disabled = !hasWritableFolder || !selectedEntry?.handle;
      $("#filesDelete").disabled = !hasWritableFolder || !selectedEntry?.handle;
      $("#filesPaste").disabled = !hasWritableFolder || !clipboard;
    }

    function selectEntry(entry, row) {
      rows.querySelectorAll("tr[aria-selected='true']").forEach(item => item.setAttribute("aria-selected", "false"));
      row.setAttribute("aria-selected", "true");
      selectedEntry = entry;
      updateActions();
      showPreview(entry);
    }

    function makeRow(entry) {
      const row = document.createElement("tr");
      row.tabIndex = 0;
      row.setAttribute("aria-selected", "false");
      const nameCell = document.createElement("td");
      const name = document.createElement("span");
      name.className = "files-entry-name";
      name.textContent = `${entry.kind === "directory" ? "▰" : "▤"}  ${entry.name}`;
      nameCell.append(name);
      const kindCell = document.createElement("td");
      kindCell.textContent = entry.kind === "directory" ? "Folder" : "File";
      const sizeCell = document.createElement("td");
      sizeCell.textContent = entry.kind === "directory" ? "—" : prettySize(entry.size);
      const modifiedCell = document.createElement("td");
      modifiedCell.textContent = entry.modified ? new Date(entry.modified).toLocaleDateString() : "—";
      row.append(nameCell, kindCell, sizeCell, modifiedCell);
      row.addEventListener("click", () => selectEntry(entry, row));
      row.addEventListener("dblclick", () => {
        if (entry.kind === "directory" && (entry.handle || entry.nativePath)) enterDirectory(entry);
        else selectEntry(entry, row);
      });
      row.addEventListener("keydown", event => {
        if (event.key === "Enter" || event.key === " ") {
          event.preventDefault();
          if (event.key === "Enter" && entry.kind === "directory" && (entry.handle || entry.nativePath)) enterDirectory(entry);
          else selectEntry(entry, row);
        }
      });
      return row;
    }

    function drawBreadcrumbs() {
      const breadcrumbs = $("#filesBreadcrumbs");
      breadcrumbs.replaceChildren();
      path.forEach((segment, index) => {
        if (index) {
          const separator = document.createElement("span");
          separator.setAttribute("aria-hidden", "true");
          separator.textContent = "/";
          breadcrumbs.append(separator);
        }
        const button = document.createElement("button");
        button.type = "button";
        button.textContent = segment.name;
        button.setAttribute("aria-current", index === path.length - 1 ? "location" : "false");
        button.addEventListener("click", async () => {
          const prevPath = path;
          const prevHandle = currentHandle;
          path = path.slice(0, index + 1);
          currentHandle = path[path.length - 1].handle;
          selectedEntry = null;
          clearPreview();
          drawBreadcrumbs();
          const ok = await drawEntries();
          if (!ok) {
            path = prevPath;
            currentHandle = prevHandle;
            drawBreadcrumbs();
          }
        });
        breadcrumbs.append(button);
      });
    }

    async function loadNativeDirectory(targetPath = "") {
      const request = ++listingGeneration;
      rows.replaceChildren();
      selectedEntry = null;
      updateActions();
      try {
        setStatus("Reading Linux directory…");
        const data = await window.NexusNativeServices.call("files", "list", targetPath);
        if (request !== listingGeneration) return false;
        nativeHome = data.home || nativeHome;
        nativeCurrentPath = data.path || targetPath || nativeHome;
        const term = search.value.trim().toLocaleLowerCase();
        const visible = (data.entries || []).filter(e => e.name.toLocaleLowerCase().includes(term));
        visible.forEach(entry => rows.append(makeRow({
          name: entry.name,
          kind: entry.kind,
          size: entry.size,
          modified: entry.modified,
          mode: entry.mode,
          nativePath: entry.path,
        })));
        const breadcrumbs = $("#filesBreadcrumbs");
        breadcrumbs.replaceChildren();
        const segs = data.relPath === "." ? [] : String(data.relPath || "").split("/").filter(Boolean);
        const homeBtn = document.createElement("button");
        homeBtn.type = "button";
        homeBtn.textContent = "~";
        homeBtn.setAttribute("aria-current", segs.length === 0 ? "location" : "false");
        homeBtn.addEventListener("click", () => loadNativeDirectory(nativeHome));
        breadcrumbs.append(homeBtn);
        let acc = nativeHome;
        segs.forEach((seg, idx) => {
          acc = `${acc}/${seg}`;
          const targetSeg = acc;
          const sep = document.createElement("span");
          sep.setAttribute("aria-hidden", "true");
          sep.textContent = "/";
          const btn = document.createElement("button");
          btn.type = "button";
          btn.textContent = seg;
          btn.setAttribute("aria-current", idx === segs.length - 1 ? "location" : "false");
          btn.addEventListener("click", () => loadNativeDirectory(targetSeg));
          breadcrumbs.append(sep, btn);
        });
        storage.textContent = `${visible.length} item${visible.length === 1 ? "" : "s"} · ${data.free_gib ?? "?"} GiB free`;
        setStatus(`${visible.length} item${visible.length === 1 ? "" : "s"} in ${data.relPath === "." ? "~" : "~/" + data.relPath}.`);
        return true;
      } catch (error) {
        setStatus(error?.message || "Could not read directory.", true);
        return false;
      }
    }

    async function drawEntries() {
      if (nativeMode && !currentHandle) {
        return loadNativeDirectory(nativeCurrentPath);
      }
      const request = ++listingGeneration;
      rows.replaceChildren();
      selectedEntry = null;
      updateActions();
      if (!currentHandle) {
        const term = search.value.trim().toLocaleLowerCase();
        const visible = openedFiles.filter(file => file.name.toLocaleLowerCase().includes(term));
        visible.forEach(file => rows.append(makeRow({
          name: file.name,
          kind: "file",
          size: file.size,
          modified: file.lastModified,
          file
        })));
        storage.textContent = openedFiles.length
          ? `${openedFiles.length} selected file${openedFiles.length === 1 ? "" : "s"} · read-only`
          : "No folder selected";
        if (openedFiles.length) setStatus(`${visible.length} file${visible.length === 1 ? "" : "s"} shown. Opened files are read-only.`);
        return true;
      }

      try {
        setStatus("Reading the selected folder…");
        const directory = currentHandle;
        const term = search.value.trim().toLocaleLowerCase();
        const entries = [];
        for await (const [name, handle] of directory.entries()) {
          if (request !== listingGeneration || directory !== currentHandle) return false;
          if (name.toLocaleLowerCase().includes(term)) {
            let size = 0;
            let modified = 0;
            if (handle.kind === "file") {
              const file = await handle.getFile();
              if (request !== listingGeneration || directory !== currentHandle) return false;
              size = file.size;
              modified = file.lastModified;
            }
            entries.push({ name, handle, kind: handle.kind, size, modified, parent: directory });
          }
        }
        if (request !== listingGeneration || directory !== currentHandle) return false;
        entries.sort((a, b) => a.kind === b.kind
          ? a.name.localeCompare(b.name, undefined, { numeric: true, sensitivity: "base" })
          : a.kind === "directory" ? -1 : 1);
        entries.forEach(entry => rows.append(makeRow(entry)));
        storage.textContent = `${entries.length} item${entries.length === 1 ? "" : "s"} in this folder · capacity unavailable`;
        setStatus(`${entries.length} item${entries.length === 1 ? "" : "s"} shown.`);
        return true;
      } catch (error) {
        setStatus(`Could not read the selected folder: ${error.message}`, true);
        return false;
      }
    }

    async function enterDirectory(entry) {
      if (entry.nativePath && nativeMode && !currentHandle) {
        selectedEntry = null;
        clearPreview();
        await loadNativeDirectory(entry.nativePath);
        return;
      }
      const prevHandle = currentHandle;
      const prevPath = path;
      try {
        currentHandle = entry.handle;
        path = [...path, { name: entry.name, handle: entry.handle }];
        selectedEntry = null;
        clearPreview();
        drawBreadcrumbs();
        const ok = await drawEntries();
        if (!ok) {
          currentHandle = prevHandle;
          path = prevPath;
          drawBreadcrumbs();
        }
      } catch (error) {
        currentHandle = prevHandle;
        path = prevPath;
        drawBreadcrumbs();
        setStatus(`Could not open this folder: ${error.message}`, true);
      }
    }

    async function ensureWritePermission() {
      if (!rootHandle) throw new Error("Choose a folder before making changes.");
      if (typeof rootHandle.queryPermission === "function" &&
          await rootHandle.queryPermission({ mode: "readwrite" }) === "granted") return;
      if (typeof rootHandle.requestPermission !== "function") {
        throw new Error("This browser cannot request write access for the selected folder.");
      }
      const permission = await rootHandle.requestPermission({ mode: "readwrite" });
      if (permission !== "granted") throw new Error("Write access was not granted.");
    }

    async function existsIn(directory, name) {
      for (const kind of ["file", "directory"]) {
        try {
          if (kind === "file") await directory.getFileHandle(name);
          else await directory.getDirectoryHandle(name);
          return true;
        } catch (error) {
          if (error.name !== "NotFoundError" && error.name !== "TypeMismatchError") throw error;
        }
      }
      return false;
    }

    async function copyEntry(source, destination, name, counter) {
      if (++counter.count > 5000) throw new Error("This folder contains more than 5,000 items; copy it in smaller parts.");
      if (await existsIn(destination, name)) throw new Error(`“${name}” already exists here.`);
      if (source.kind === "file") {
        const file = await source.handle.getFile();
        const target = await destination.getFileHandle(name, { create: true });
        try {
          const writable = await target.createWritable();
          await writable.write(file);
          await writable.close();
        } catch (error) {
          try {
            await destination.removeEntry(name);
          } catch (cleanupError) {
            throw new Error(`${error.message} A partial copy could not be removed: ${cleanupError.message}`);
          }
          throw error;
        }
        return;
      }
      const target = await destination.getDirectoryHandle(name, { create: true });
      try {
        for await (const [childName, child] of source.handle.entries()) {
          await copyEntry({ handle: child, kind: child.kind }, target, childName, counter);
        }
      } catch (error) {
        try {
          await destination.removeEntry(name, { recursive: true });
        } catch (cleanupError) {
          throw new Error(`${error.message} A partial folder copy could not be removed: ${cleanupError.message}`);
        }
        throw error;
      }
    }

    function reportError(error) {
      setStatus(error.message || "The file operation could not be completed.", true);
    }

    chooseFolder.addEventListener("click", async () => {
      try {
        const folder = await window.showDirectoryPicker({ mode: "readwrite" });
        rootHandle = folder;
        currentHandle = folder;
        path = [{ name: folder.name, handle: folder }];
        clipboard = null;
        openedFiles = [];
        openInput.value = "";
        clearPreview();
        drawBreadcrumbs();
        await drawEntries();
      } catch (error) {
        if (error.name !== "AbortError") reportError(error);
      }
    });

    openInput.addEventListener("change", async () => {
      openedFiles = Array.from(openInput.files || []);
      rootHandle = null;
      currentHandle = null;
      path = [];
      clipboard = null;
      selectedEntry = null;
      clearPreview();
      drawBreadcrumbs();
      await drawEntries();
      if (!chooseFolder.disabled) setStatus("Opened files are read-only. Choose a folder to create or manage files.");
    });

    $("#filesNewFolder").addEventListener("click", async () => {
      const name = window.prompt("New folder name");
      if (name === null) return;
      if (!validName(name)) {
        setStatus("Enter a valid folder name without / or \\ (cannot be . or ..).", true);
        return;
      }
      if (nativeMode && !currentHandle) {
        try {
          await window.NexusNativeServices.call("files", "mkdir", nativeCurrentPath, name.trim());
          setStatus(`Created folder “${name.trim()}”.`);
          await loadNativeDirectory(nativeCurrentPath);
        } catch (error) { reportError(error); }
        return;
      }
      try {
        await ensureWritePermission();
        if (await existsIn(currentHandle, name.trim())) throw new Error(`“${name.trim()}” already exists here.`);
        await currentHandle.getDirectoryHandle(name.trim(), { create: true });
        setStatus(`Created folder “${name.trim()}”.`);
        await drawEntries();
      } catch (error) { reportError(error); }
    });

    $("#filesNewFile").addEventListener("click", async () => {
      const name = window.prompt("New text file name", "Untitled.txt");
      if (name === null) return;
      if (!validName(name)) {
        setStatus("Enter a valid file name without / or \\ (cannot be . or ..).", true);
        return;
      }
      if (nativeMode && !currentHandle) {
        try {
          await window.NexusNativeServices.call("files", "touch", nativeCurrentPath, name.trim());
          setStatus(`Created file “${name.trim()}”.`);
          await loadNativeDirectory(nativeCurrentPath);
        } catch (error) { reportError(error); }
        return;
      }
      try {
        await ensureWritePermission();
        if (await existsIn(currentHandle, name.trim())) throw new Error(`“${name.trim()}” already exists here.`);
        const file = await currentHandle.getFileHandle(name.trim(), { create: true });
        const writable = await file.createWritable();
        await writable.write("");
        await writable.close();
        setStatus(`Created file “${name.trim()}”.`);
        await drawEntries();
      } catch (error) { reportError(error); }
    });

    $("#filesRename").addEventListener("click", async () => {
      if (nativeMode && !currentHandle && selectedEntry?.nativePath) {
        const entry = selectedEntry;
        const name = window.prompt("Rename to", entry.name);
        if (name === null) return;
        if (!validName(name)) {
          setStatus("Enter a valid name without / or \\ (cannot be . or ..).", true);
          return;
        }
        if (name.trim() === entry.name) return;
        try {
          await window.NexusNativeServices.call("files", "rename", entry.nativePath, name.trim());
          setStatus(`Renamed to “${name.trim()}”.`);
          await loadNativeDirectory(nativeCurrentPath);
        } catch (error) { reportError(error); }
        return;
      }
      if (!selectedEntry?.handle || typeof selectedEntry.handle.move !== "function") return;
      const entry = selectedEntry;
      const name = window.prompt("Rename to", entry.name);
      if (name === null) return;
      if (!validName(name)) {
        setStatus("Enter a valid name without / or \\ (cannot be . or ..).", true);
        return;
      }
      if (name.trim() === entry.name) return;
      try {
        await ensureWritePermission();
        if (await existsIn(currentHandle, name.trim())) throw new Error(`“${name.trim()}” already exists here.`);
        await entry.handle.move(name.trim());
        if (clipboard?.entry) {
          const sameEntry = typeof clipboard.entry.handle?.isSameEntry === "function"
            ? await clipboard.entry.handle.isSameEntry(entry.handle)
            : clipboard.entry.handle === entry.handle;
          if (sameEntry) clipboard = null;
        }
        setStatus(`Renamed to “${name.trim()}”.`);
        await drawEntries();
      } catch (error) { reportError(error); }
    });

    $("#filesCopy").addEventListener("click", () => {
      if (!selectedEntry?.handle) return;
      clipboard = { entry: selectedEntry, cut: false };
      setStatus(`Copied “${selectedEntry.name}” to the file manager clipboard.`);
      updateActions();
    });

    $("#filesCut").addEventListener("click", () => {
      if (!selectedEntry?.handle) return;
      clipboard = { entry: selectedEntry, cut: true };
      setStatus(`“${selectedEntry.name}” is ready to move.`);
      updateActions();
    });

    $("#filesPaste").addEventListener("click", async () => {
      if (!clipboard || !currentHandle) return;
      const source = clipboard.entry;
      try {
        await ensureWritePermission();
        const sameFolder = source.parent && await source.parent.isSameEntry(currentHandle);
        if (sameFolder) throw new Error("Choose a different folder before pasting.");
        if (source.kind === "directory") {
          for (const segment of path) {
            const isSame = typeof segment.handle?.isSameEntry === "function"
              ? await segment.handle.isSameEntry(source.handle)
              : segment.handle === source.handle;
            if (isSame) throw new Error("A folder cannot be copied or moved inside itself.");
          }
        }
        const counter = { count: 0 };
        await copyEntry(source, currentHandle, source.name, counter);
        if (clipboard.cut) {
          try {
            await source.parent.removeEntry(source.name, { recursive: source.kind === "directory" });
          } catch (error) {
            clipboard = null;
            setStatus(`Copied “${source.name}”, but the original could not be removed: ${error.message}`, true);
            await drawEntries();
            return;
          }
        }
        clipboard = clipboard.cut ? null : clipboard;
        setStatus(`${clipboard ? "Copied" : "Moved"} “${source.name}”.`);
        await drawEntries();
      } catch (error) { reportError(error); }
      updateActions();
    });

    $("#filesDelete").addEventListener("click", async () => {
      if (nativeMode && !currentHandle && selectedEntry?.nativePath) {
        const entry = selectedEntry;
        if (!window.confirm(`Delete “${entry.name}”${entry.kind === "directory" ? " and its contents" : ""}?`)) return;
        try {
          await window.NexusNativeServices.call("files", "remove", entry.nativePath);
          clearPreview();
          setStatus(`Deleted “${entry.name}”.`);
          await loadNativeDirectory(nativeCurrentPath);
        } catch (error) { reportError(error); }
        return;
      }
      if (!selectedEntry?.handle) return;
      const entry = selectedEntry;
      if (!window.confirm(`Delete “${entry.name}”${entry.kind === "directory" ? " and its contents" : ""}?`)) return;
      try {
        await ensureWritePermission();
        await currentHandle.removeEntry(entry.name, { recursive: entry.kind === "directory" });
        if (clipboard?.entry) {
          const sameEntry = typeof clipboard.entry.handle?.isSameEntry === "function"
            ? await clipboard.entry.handle.isSameEntry(entry.handle)
            : clipboard.entry.handle === entry.handle;
          if (sameEntry) clipboard = null;
        }
        clearPreview();
        setStatus(`Deleted “${entry.name}”.`);
        await drawEntries();
      } catch (error) { reportError(error); }
    });

    search.addEventListener("input", drawEntries);
    $("#filesHomeLocation").addEventListener("click", () => {
      if (nativeMode && !currentHandle) {
        loadNativeDirectory(nativeHome || "");
        return;
      }
      if (!rootHandle) return;
      currentHandle = rootHandle;
      path = [{ name: rootHandle.name, handle: rootHandle }];
      selectedEntry = null;
      clearPreview();
      drawBreadcrumbs();
      drawEntries();
    });
    root.querySelectorAll("[data-native-loc]").forEach(btn => {
      btn.addEventListener("click", () => {
        if (nativeMode) {
          rootHandle = null;
          currentHandle = null;
          loadNativeDirectory(btn.dataset.nativeLoc);
        }
      });
    });
    $("#filesOpenNative")?.addEventListener("click", () => {
      Promise.resolve(window.NexusNativeServices.call("files", "openControl"))
        .then(res => setStatus(res?.message || "Opened native file manager.", res?.ok === false))
        .catch(err => setStatus(err?.message || "Could not open native file manager.", true));
    });
    updateActions();
    clearPreview();
    if (nativeMode) {
      loadNativeDirectory("");
    }
    return () => {
      previewGeneration += 1;
      listingGeneration += 1;
      if (previewUrl) URL.revokeObjectURL(previewUrl);
      previewUrl = null;
    };
  }

  window.NexusFilesHelpers = Object.freeze({ isValidEntryName: validName });
  window.NexusAppRegistry.register({ id: "files", name: "File Manager", render, mount });
})();
