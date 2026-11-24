(() => {
  function render() {
    return `
      <h2 class="content-title">Gaming Hub</h2>
      <p class="content-sub">Discover your games and tune the experience.</p>
      <div class="card-grid">
        <div class="content-card">
          <h3>Steam</h3>
          <p>Native Steam support is planned for the Linux Mint base. This browser demo cannot launch Steam.</p>
        </div>
        <div class="content-card">
          <h3>Performance</h3>
          <p>Lightweight mode and reduced effects are available in Settings.</p>
        </div>
        <div class="content-card">
          <h3>Controller</h3>
          <p>Controller setup is a planned system feature.</p>
        </div>
      </div>`;
  }

  function mount() {}

  window.NexusAppRegistry.register({ id: "gaming", name: "Gaming Hub", render, mount });
})();
