(() => {
  const storageKey = "nexus-calendar-events-v1";

  function localDateKey(date) {
    const year = date.getFullYear();
    const month = String(date.getMonth() + 1).padStart(2, "0");
    const day = String(date.getDate()).padStart(2, "0");
    return `${year}-${month}-${day}`;
  }

  function parseDateKey(value) {
    const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(value);
    if (!match) return null;
    const date = new Date(Number(match[1]), Number(match[2]) - 1, Number(match[3]));
    return localDateKey(date) === value ? date : null;
  }

  function render() {
    return `
      <section class="nexus-calendar" aria-labelledby="calendarTitle">
        <header class="calendar-heading">
          <div>
            <h2 class="content-title" id="calendarTitle">Calendar</h2>
            <p class="content-sub">Your events are stored only in this browser.</p>
          </div>
          <span class="integration-status">Local events · no reminders</span>
        </header>
        <div class="calendar-layout">
          <section class="calendar-month" aria-label="Calendar month">
            <div class="calendar-month-heading">
              <button type="button" class="calendar-month-nav" id="calendarPrevious" aria-label="Previous month">‹</button>
              <h3 id="calendarMonthLabel"></h3>
              <button type="button" class="calendar-month-nav" id="calendarNext" aria-label="Next month">›</button>
            </div>
            <div class="calendar-grid" id="calendarGrid" role="grid" aria-label="Days of the month"></div>
          </section>
          <section class="calendar-agenda" aria-labelledby="calendarAgendaTitle">
            <div class="calendar-agenda-heading">
              <div>
                <h3 id="calendarAgendaTitle">Selected day</h3>
                <p id="calendarSelectedDate"></p>
              </div>
            </div>
            <form class="calendar-event-form" id="calendarEventForm">
              <label for="calendarEventTitle">Event name</label>
              <input id="calendarEventTitle" name="title" maxlength="80" required placeholder="Add an event">
              <button class="action-button" type="submit">Add event</button>
            </form>
            <p class="calendar-status" id="calendarStatus" role="status" aria-live="polite"></p>
            <ul class="calendar-event-list" id="calendarEventList"></ul>
          </section>
        </div>
        <p class="integration-note">Events stay in this browser profile. Calendar sync, accounts and system reminders need native services.</p>
      </section>`;
  }

  function mount(root) {
    const now = new Date();
    let month = new Date(now.getFullYear(), now.getMonth(), 1);
    let selectedDate = localDateKey(now);
    let events = [];
    const grid = root.querySelector("#calendarGrid");
    const monthLabel = root.querySelector("#calendarMonthLabel");
    const agendaTitle = root.querySelector("#calendarAgendaTitle");
    const selectedDateLabel = root.querySelector("#calendarSelectedDate");
    const status = root.querySelector("#calendarStatus");
    const eventList = root.querySelector("#calendarEventList");
    const eventTitle = root.querySelector("#calendarEventTitle");
    const form = root.querySelector("#calendarEventForm");

    try {
      const saved = window.localStorage.getItem(storageKey);
      if (saved) {
        const parsed = JSON.parse(saved);
        if (!Array.isArray(parsed) || parsed.some(event =>
          !event || typeof event.title !== "string" || !event.title.trim() || !parseDateKey(event.date)
        )) throw new Error("Saved events have an unsupported format.");
        events = parsed;
      }
      status.textContent = "";
    } catch (error) {
      status.textContent = `Could not load saved events: ${error.message}`;
      status.classList.add("error");
      form.querySelector("button").disabled = true;
    }

    function eventsOn(dateKey) {
      return events.filter(event => event.date === dateKey);
    }

    function drawAgenda() {
      const date = parseDateKey(selectedDate);
      const label = date.toLocaleDateString(undefined, { weekday: "long", month: "long", day: "numeric", year: "numeric" });
      agendaTitle.textContent = date.toLocaleDateString(undefined, { month: "long", day: "numeric" });
      selectedDateLabel.textContent = label;
      eventList.replaceChildren();
      const selectedEvents = eventsOn(selectedDate);
      if (!selectedEvents.length) {
        const empty = document.createElement("li");
        empty.className = "calendar-empty";
        empty.textContent = "No events for this day.";
        eventList.append(empty);
        return;
      }
      selectedEvents.forEach(event => {
        const item = document.createElement("li");
        item.className = "calendar-event";
        const title = document.createElement("span");
        title.textContent = event.title;
        const remove = document.createElement("button");
        remove.type = "button";
        remove.className = "calendar-event-remove";
        remove.textContent = "Remove";
        remove.setAttribute("aria-label", `Remove event ${event.title}`);
        remove.addEventListener("click", () => {
          const nextEvents = events.filter(candidate => candidate.id !== event.id);
          try {
            window.localStorage.setItem(storageKey, JSON.stringify(nextEvents));
            events = nextEvents;
            status.textContent = "Event removed.";
            status.classList.remove("error");
            drawMonth();
            drawAgenda();
          } catch (error) {
            status.textContent = `Could not remove event: ${error.message}`;
            status.classList.add("error");
          }
        });
        item.append(title, remove);
        eventList.append(item);
      });
    }

    function drawMonth() {
      monthLabel.textContent = month.toLocaleDateString(undefined, { month: "long", year: "numeric" });
      grid.replaceChildren();
      ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"].forEach(day => {
        const heading = document.createElement("span");
        heading.className = "calendar-weekday";
        heading.setAttribute("role", "columnheader");
        heading.textContent = day;
        grid.append(heading);
      });
      const firstDay = new Date(month.getFullYear(), month.getMonth(), 1);
      const offset = (firstDay.getDay() + 6) % 7;
      const daysInMonth = new Date(month.getFullYear(), month.getMonth() + 1, 0).getDate();
      for (let blank = 0; blank < offset; blank++) {
        const spacer = document.createElement("span");
        spacer.className = "calendar-day-spacer";
        spacer.setAttribute("aria-hidden", "true");
        grid.append(spacer);
      }
      for (let day = 1; day <= daysInMonth; day++) {
        const date = new Date(month.getFullYear(), month.getMonth(), day);
        const dateKey = localDateKey(date);
        const button = document.createElement("button");
        button.type = "button";
        button.className = "calendar-day";
        button.setAttribute("role", "gridcell");
        button.setAttribute("aria-label", date.toLocaleDateString(undefined, { weekday: "long", month: "long", day: "numeric", year: "numeric" }));
        button.setAttribute("aria-pressed", String(dateKey === selectedDate));
        if (dateKey === localDateKey(now)) button.classList.add("today");
        button.textContent = String(day);
        if (eventsOn(dateKey).length) {
          const marker = document.createElement("span");
          marker.className = "calendar-event-marker";
          marker.setAttribute("aria-hidden", "true");
          button.append(marker);
        }
        button.addEventListener("click", () => {
          selectedDate = dateKey;
          drawMonth();
          drawAgenda();
        });
        grid.append(button);
      }
    }

    root.querySelector("#calendarPrevious").addEventListener("click", () => {
      month = new Date(month.getFullYear(), month.getMonth() - 1, 1);
      drawMonth();
    });
    root.querySelector("#calendarNext").addEventListener("click", () => {
      month = new Date(month.getFullYear(), month.getMonth() + 1, 1);
      drawMonth();
    });
    form.addEventListener("submit", event => {
      event.preventDefault();
      const title = eventTitle.value.trim();
      if (!title) {
        status.textContent = "Enter an event name first.";
        status.classList.add("error");
        eventTitle.focus();
        return;
      }
      const nextEvents = [...events, { id: `${Date.now()}-${Math.random().toString(36).slice(2)}`, date: selectedDate, title }];
      try {
        window.localStorage.setItem(storageKey, JSON.stringify(nextEvents));
        events = nextEvents;
        eventTitle.value = "";
        status.textContent = "Event saved in this browser.";
        status.classList.remove("error");
        drawMonth();
        drawAgenda();
        eventTitle.focus();
      } catch (error) {
        status.textContent = `Could not save event: ${error.message}`;
        status.classList.add("error");
      }
    });

    drawMonth();
    drawAgenda();
  }

  window.NexusAppRegistry.register({ id: "calendar", name: "Calendar", render, mount });
})();
