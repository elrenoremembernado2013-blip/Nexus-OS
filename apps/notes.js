(() => {
  const storageKey = "nexus-note";

  function render() {
    return `
      <h2 class="content-title">Notes</h2>
      <p class="content-sub">Your notes are saved locally in this browser.</p>
      <textarea class="note-area" id="notesText" aria-label="Notes editor" placeholder="Write something…"></textarea>
      <div style="display:flex;justify-content:space-between;margin-top:10px">
        <small class="content-sub" id="notesStatus">Autosave ready</small>
        <button class="action-button" id="clearNotes" type="button">Clear note</button>
      </div>`;
  }

  function mount(root) {
    const textarea = root.querySelector("#notesText");
    const status = root.querySelector("#notesStatus");
    const clear = root.querySelector("#clearNotes");

    try {
      textarea.value = window.localStorage.getItem(storageKey) || "";
      status.classList.remove("error");
    } catch (error) {
      status.textContent = `Could not load saved notes: ${error.message}`;
      status.classList.add("error");
    }

    const saveNow = () => {
      try {
        window.localStorage.setItem(storageKey, textarea.value);
        status.textContent = "Saved locally";
        status.classList.remove("error");
      } catch (error) {
        status.textContent = `Could not save note: ${error.message}`;
        status.classList.add("error");
      }
    };

    const onKeyDown = event => {
      if ((event.ctrlKey || event.metaKey) && event.key.toLowerCase() === "s") {
        event.preventDefault();
        saveNow();
      }
    };

    const onClear = () => {
      textarea.value = "";
      try {
        window.localStorage.removeItem(storageKey);
        status.textContent = "Cleared";
        status.classList.remove("error");
      } catch (error) {
        status.textContent = `Could not clear saved note: ${error.message}`;
        status.classList.add("error");
      }
    };

    textarea.addEventListener("input", saveNow);
    textarea.addEventListener("keydown", onKeyDown);
    clear.addEventListener("click", onClear);

    return () => {
      textarea.removeEventListener("input", saveNow);
      textarea.removeEventListener("keydown", onKeyDown);
      clear.removeEventListener("click", onClear);
    };
  }

  window.NexusAppRegistry.register({ id: "notes", name: "Notes", render, mount });
})();
