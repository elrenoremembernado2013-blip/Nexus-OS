(() => {
  const storageKey = "nexus-note";

  function render() {
    return `
      <h2 class="content-title">Notes</h2>
      <p class="content-sub">Your notes are saved locally in this browser.</p>
      <textarea class="note-area" id="notesText" placeholder="Write something…"></textarea>
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
    } catch (error) {
      status.textContent = `Could not load saved notes: ${error.message}`;
    }

    textarea.addEventListener("input", () => {
      try {
        window.localStorage.setItem(storageKey, textarea.value);
        status.textContent = "Saved locally";
      } catch (error) {
        status.textContent = `Could not save note: ${error.message}`;
      }
    });

    clear.addEventListener("click", () => {
      textarea.value = "";
      try {
        window.localStorage.removeItem(storageKey);
        status.textContent = "Cleared";
      } catch (error) {
        status.textContent = `Could not clear saved note: ${error.message}`;
      }
    });
  }

  window.NexusAppRegistry.register({ id: "notes", name: "Notes", render, mount });
})();
