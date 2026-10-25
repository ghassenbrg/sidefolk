import { problem } from "../voice";
import { overflow } from "./kit";
import { sheet } from "./dialog";
import { icon } from "../icons";
import { badge } from "../states";
import { dateValue, timeValue, fromFields, nextDue, describeRepeat, parseReminder, parseEventReminder, type Repeat } from "../when";
export { fromFields } from "../when";
import { snoozeUntil, pickSnooze } from "../reminders";
import { invoke, type Reminder } from "./api";
import type { App } from "./app";
import { agentShort, button, folder, h, timeZone } from "./dom";
import { header } from "./ui";
import { EVENT_TTL_MS, eventDescription, isScheduledReminder, resolveEventProject } from "../event-reminders";

// Reminders: a labelled title and explicit date and time fields. Typing a time in the title
// ("tomorrow at 10") fills them in; the resolved date and time zone show before saving.

export const longDate = (d: Date) =>
  d.toLocaleString([], { weekday: "long", day: "numeric", month: "long", hour: "2-digit", minute: "2-digit" });

/** A new reminder's starting time: the next full hour, or 09:00 tomorrow outside 07:00–21:59.
 * The fields always hold a real value, never a placeholder that looks like one (V1-R14). */
export function defaultDue(now = new Date()): Date {
  const d = new Date(now);
  d.setMinutes(0, 0, 0);
  d.setHours(d.getHours() + 1);
  if (d.getHours() < 7 || d.getHours() > 21 || d.getDate() !== now.getDate()) {
    d.setTime(now.getTime());
    d.setDate(d.getDate() + (now.getHours() >= 7 ? 1 : 0));
    d.setHours(9, 0, 0, 0);
  }
  return d;
}

/** The form fields; reused for adding and for editing one reminder. `text` prefills a new one. */
function fields(prefix: string, initial?: Reminder, text0 = "") {
  const due = initial ? new Date(initial.due) : defaultDue();
  const anchor = initial ? new Date(initial.anchor || initial.due) : due;
  const text = h("input", { type: "text", id: `${prefix}-text`, maxlength: 300, autocomplete: "off", value: initial?.text ?? text0, placeholder: "Review launch notes", "aria-describedby": `${prefix}-text-error` });
  const dateLabel = h("label", { for: `${prefix}-date`, text: "Date" });
  const date = h("input", { type: "date", id: `${prefix}-date`, value: due ? dateValue(due) : "", "aria-describedby": `${prefix}-when-error` });
  const time = h("input", { type: "time", id: `${prefix}-time`, value: due ? timeValue(due) : "", "aria-describedby": `${prefix}-when-error` });
  const repeat = h("select", { id: `${prefix}-repeat` });
  for (const [value, label] of [["", "Does not repeat"], ["day", "Every day"], ["weekday", "Weekdays"], ["week", "Weekly"], ["month", "Monthly"], ["year", "Yearly"]])
    repeat.append(h("option", { value, text: label }));
  repeat.value = initial?.repeat?.every ?? "";
  const interval = h("input", { type: "number", id: `${prefix}-interval`, min: 1, max: 52, step: 1, value: String(initial?.repeat?.n ?? 1) });
  const intervalField = h("div", { class: "field" }, h("label", { for: interval.id, text: "Every how many?" }), interval);
  let typedRepeat = !!initial;
  const weekdayFields = h("fieldset", { class: "field wide" }, h("legend", { text: "Repeat on" }));
  const weekdays = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"];
  const dayInputs = weekdays.map((name, day) => {
    const input = h("input", { type: "checkbox", value: String(day), checked: (initial?.repeat?.days?.length ? initial.repeat.days : [anchor.getDay()]).includes(day) });
    weekdayFields.append(h("label", {}, input, name));
    input.addEventListener("change", () => { typedRepeat = true; update(); });
    return input;
  });
  const days = () => dayInputs.flatMap((input, day) => input.checked ? [day] : []);
  const selectedRepeat = (): Repeat | undefined =>
    repeat.value ? { every: repeat.value as Repeat["every"], n: repeat.value === "weekday" ? 1 : Number(interval.value), ...(repeat.value === "week" ? { days: days() } : {}) } : undefined;
  const sameRepeat = (recurrence?: Repeat) => {
    const original = initial?.repeat;
    const originalDays = original?.every === "week" ? original.days?.length ? original.days : [anchor.getDay()] : [];
    return original?.every === recurrence?.every && original?.n === recurrence?.n
      && JSON.stringify([...originalDays].sort()) === JSON.stringify([...(recurrence?.days ?? [])].sort());
  };
  const firstDue = (when: Date, recurrence?: Repeat) => {
    const unchanged = initial && date.value === dateValue(due) && time.value === timeValue(due) && sameRepeat(recurrence);
    const namedDays = recurrence?.every === "weekday" || recurrence?.every === "week" && recurrence.days?.length;
    return !repeat.disabled && recurrence && namedDays && !unchanged
      ? nextDue(when, recurrence, new Date(when.getTime() - 1)) : when;
  };
  const textError = h("p", { class: "field-error", id: `${prefix}-text-error`, role: "alert" });
  const whenError = h("p", { class: "field-error", id: `${prefix}-when-error`, role: "alert" });
  const resolved = h("p", { class: "hint", "aria-live": "polite" });
  const leap = h("input", { type: "checkbox" });
  const leapPolicy = h("label", { class: "field wide" }, leap, "Use February 28 in non-leap years (February 29 in leap years).");
  let typedWhen = !!initial;
  let changedText = false;
  const update = () => {
    // A time typed in the title fills the fields, unless they were set by hand.
    const parsed = parseReminder(text.value);
    if (parsed && !typedWhen) {
      date.value = dateValue(parsed.due);
      time.value = timeValue(parsed.due);
    }
    if (!typedRepeat) {
      repeat.value = parsed?.repeat?.every ?? "";
      interval.value = String(parsed?.repeat?.n ?? 1);
      for (const [day, input] of dayInputs.entries()) input.checked = (parsed?.repeat?.days ?? [(parsed?.due ?? due).getDay()]).includes(day);
    }
    intervalField.hidden = !repeat.value || repeat.value === "weekday";
    weekdayFields.hidden = repeat.value !== "week";
    dateLabel.textContent = repeat.disabled ? "Date (this occurrence)" : repeat.value === "year" ? "Anchor date (month and day)" : repeat.value ? "Anchor date" : "Date";
    if (repeat.value === "weekday") interval.value = "1";
    const when = fromFields(date.value, time.value);
    const recurrence = selectedRepeat();
    const ruleDate = initial && date.value === dateValue(due) ? anchor : when;
    leapPolicy.hidden = !(recurrence?.every === "year" && ruleDate?.getMonth() === 1 && ruleDate.getDate() === 29);
    resolved.textContent = when ? `Reminds you ${longDate(firstDue(when, recurrence))} (${timeZone()})${recurrence ? `, then ${describeRepeat(recurrence, ruleDate ?? when)}` : ""}.` : `Times are in your time zone, ${timeZone()}.`;
  };
  for (const control of [repeat, interval]) control.addEventListener("change", () => { typedRepeat = true; update(); });
  text.addEventListener("input", () => { changedText = true; update(); });
  for (const f of [date, time])
    f.addEventListener("input", () => {
      typedWhen = true;
      whenError.textContent = "";
      update();
    });
  text.addEventListener("input", () => (textError.textContent = ""));
  update();
  const node = h(
    "div",
    { class: "form-grid" },
    h("div", { class: "field wide" }, h("label", { for: text.id, text: "What would you like to remember?" }), text, textError),
    h("div", { class: "field" }, dateLabel, date),
    h("div", { class: "field" }, h("label", { for: time.id, text: "Time" }), time),
    h("div", { class: "field" }, h("label", { for: repeat.id, text: "Repeat" }), repeat),
    intervalField, weekdayFields, leapPolicy,
    h("div", { class: "wide" }, whenError, resolved, h("p", { class: "hint", text: "Reminders appear on this Mac." })),
  );
  /** Checks the fields; returns what to save, or null with errors shown next to the fields. */
  const read = (): { text: string; due: Date; repeat?: Repeat; repeatChanged: boolean } | null => {
    const parsed = parseReminder(text.value);
    const what = (parsed && (!initial || changedText) ? parsed.what : text.value).trim();
    const unchangedTime = initial && date.value === dateValue(due) && time.value === timeValue(due);
    const when = unchangedTime ? due : fromFields(date.value, time.value);
    textError.textContent = /^(?:remind me\s+)?when\b/i.test(text.value.trim()) ? "Use Quick add to save a project completion condition." : what ? "" : "Enter what to remember.";
    whenError.textContent = !when ? "Choose a date and a time." : when.getTime() <= Date.now() && (!initial || when.getTime() !== initial.due) ? "That time has passed. Choose a later one." : "";
    const recurrence = selectedRepeat();
    if (recurrence && (!Number.isInteger(recurrence.n) || recurrence.n < 1 || recurrence.n > 52)) whenError.textContent = "Choose a repeat interval from 1 to 52.";
    if (recurrence?.every === "week" && !recurrence.days?.length) whenError.textContent = "Choose at least one weekday.";
    if (!leapPolicy.hidden && !leap.checked && !repeat.disabled) whenError.textContent = "Confirm the February 28 policy for non-leap years.";
    return what && when && !textError.textContent && !whenError.textContent ? { text: what, due: firstDue(when, recurrence), repeat: recurrence, repeatChanged: !sameRepeat(recurrence) } : null;
  };
  const reach = h("p", { class: "hint", "aria-live": "polite" });
  node.append(reach);
  void invoke<{ permission: string }>("notification_status").then((status) => {
    if (status.permission === "denied") reach.textContent = "Reminders show only while Sidefolk is running.";
  }).catch(() => {});
  return { node, read, focus: () => text.focus(),
    scope: (one: boolean) => {
      if (one) {
        repeat.value = initial?.repeat?.every ?? "";
        interval.value = String(initial?.repeat?.n ?? 1);
        for (const [day, input] of dayInputs.entries()) input.checked = (initial?.repeat?.days?.length ? initial.repeat.days : [anchor.getDay()]).includes(day);
      }
      repeat.disabled = one; interval.disabled = one; for (const input of dayInputs) input.disabled = one;
      update();
    },
  };
}

let filter = "upcoming";

export function renderReminders(app: App, arg = "") {
  if (arg && arg !== "new") {
    const r = app.state.reminders.find((r) => r.id === arg);
    const view = h("div", { class: "view" }, button("Back to Reminders", () => app.go("reminders")), ...header(r?.text ?? "Reminder no longer exists", "Reminder details"));
    if (!r) return view;
    view.append(r.done ? h("p", { text: "Completed" }) : reminderRow(app, r, true));
    view.append(h("h2", { text: "History" }), h("ol", {}, ...(r.history?.length ? r.history : [{ at: r.created, action: "Created", due: r.due }]).map((entry) => h("li", {}, `${longDate(new Date(entry.at))} · ${entry.action}${entry.text ? ` · ${entry.text}` : ""}${entry.due ? ` · due ${longDate(new Date(entry.due))}` : ""}`))));
    return view;
  }
  const view = h("div", { class: "view reminders" }, h("div", { class: "page-heading" }, h("div", {}, ...header("Reminders", "Small things, remembered.")), button([icon("plus"), "Add reminder"], () => addReminder(app), "primary")));
  const filters = h("div", { class: "segmented", role: "group", "aria-label": "Filter reminders" });
  for (const [value, label] of [["upcoming", "Upcoming"], ["repeating", "Repeating"], ["completed", "Completed"]]) filters.append(button(label, () => { filter = value; app.redraw(true); }, "", { "aria-pressed": String(filter === value) }));
  const list = h("section", { class: "reminder-list", "aria-label": "Your reminders" });
  const fill = () => list.replaceChildren(...rows(app));
  fill();
  app.live(fill);
  view.append(filters, list);
  if (arg === "new") requestAnimationFrame(() => { app.go("reminders"); addReminder(app); });
  return view;
}

/** The Add reminder sheet; `text` comes from Quick add when it had no time to go on. */
export function addReminder(app: App, text = "", onSaved?: () => void) {
  if (parseEventReminder(text)) { void addEventReminder(app, text, onSaved); return; }
  const add = fields("new", undefined, text);
  const error = h("p", { class: "field-error", role: "alert" });
  const submit = h("button", { type: "submit", class: "primary", text: "Save reminder" });
  const form = h("form", { "aria-label": "Add a reminder" }, add.node, error);
  const editor = sheet("Add reminder", form);
  form.append(h("div", { class: "actions sheet-actions" }, button("Cancel", editor.close), submit));
  form.addEventListener("submit", async (event) => {
    event.preventDefault();
    if (submit.disabled) return;
    const value = add.read();
    if (!value) return;
    submit.disabled = true;
    try {
      const added = await invoke<Reminder>("add_reminder", { text: value.text, due: value.due.getTime(), project: null, repeat: value.repeat ?? null });
      onSaved?.();
      filter = "upcoming";
      editor.close();
      await app.refresh();
      app.redraw(true);
      app.toast(`Reminder set for ${longDate(value.due)}.`, { label: "Undo", run: async () => { await invoke("remove_reminder", { id: added.id }); await app.refresh(); } });
    } catch (reason) { error.textContent = problem(reason); submit.disabled = false; }
  });
  requestAnimationFrame(add.focus);
}

/** Shared window confirmation for Quick add's existing remind intent (before date parsing). */
export async function addEventReminder(app: App, text: string, onSaved?: () => void) {
  const draft = parseEventReminder(text);
  if (!draft) return;
  let project;
  try {
    const projects = app.state.status.pets.flatMap((pet) => [...pet.sessions, ...pet.outcomes].map((item) => item.project));
    project = await resolveEventProject(draft.project, projects, async (wanted) => {
      const folder = await invoke<{ path: string; label: string }>("resolve_folder", { folder: wanted });
      const path = await invoke<string>("resolve_event_project", { path: folder.path });
      return { path, label: path };
    });
  } catch (reason) { app.toast(problem(reason), undefined, true); return; }
  const preview = h("p", { class: "hint", text: `When ${project.path} next finishes · Expires 24 hours after saving (about ${longDate(new Date(Date.now() + EVENT_TTL_MS))}, ${timeZone()}).` });
  const error = h("p", { class: "field-error", role: "alert" });
  const submit = h("button", { type: "submit", class: "primary", text: "Save reminder" });
  const form = h("form", { "aria-label": "Project completion reminder" }, h("p", { text: draft.what }), preview, error);
  const editor = sheet("New reminder", form);
  form.append(h("div", { class: "actions sheet-actions" }, button("Cancel", editor.close), submit));
  form.addEventListener("submit", async (event) => {
    event.preventDefault();
    if (submit.disabled) return;
    submit.disabled = true;
    try {
      const reminder = await invoke<Reminder>("add_event_reminder", { text: draft.what, project: project.path });
      onSaved?.(); editor.close(); await app.refresh(); app.redraw(true);
      app.toast(eventDescription(reminder), { label: "Undo", run: async () => { await invoke("remove_reminder", { id: reminder.id }); await app.refresh(); } });
    } catch (reason) { error.textContent = problem(reason); submit.disabled = false; }
  });
  requestAnimationFrame(() => submit.focus());
}

function rows(app: App): HTMLElement[] {
  const all = app.state.reminders;
  const open = all.filter((r) => !r.done).sort((a, b) => a.due - b.due);
  const done = all.flatMap((r) => {
    const completed = r.history?.filter((entry) => entry.action === "Completed") ?? [];
    return completed.length ? completed.map((entry) => ({ ...r, done: true, due: entry.due, text: entry.text ?? r.text })) : r.done ? [r] : [];
  }).sort((a, b) => b.due - a.due);
  const nodes: HTMLElement[] = [];
  const items = filter === "completed" ? done : filter === "repeating" ? open.filter((r) => r.repeat) : open;
  if (!items.length) nodes.push(h("section", { class: "card empty" }, h("strong", { text: filter === "completed" ? "Nothing completed yet." : "A little space for later." }), h("p", { text: filter === "repeating" ? "Repeating reminders will appear here." : "Add a reminder, or tell your companion what to remember." })));
  let group = "";
  const midnight = new Date(); midnight.setHours(0, 0, 0, 0);
  const tomorrow = new Date(midnight); tomorrow.setDate(tomorrow.getDate() + 1);
  const later = new Date(tomorrow); later.setDate(later.getDate() + 1);
  for (const r of items) {
    const title = filter === "completed" ? "Completed" : r.event?.expiredAt != null ? "Expired conditions" : r.event && !isScheduledReminder(r) ? "Waiting for project completion" : r.due < Date.now() ? "Overdue" : r.due < tomorrow.getTime() ? "Today" : r.due < later.getTime() ? "Tomorrow" : "Later";
    if (title !== group) { nodes.push(h("h2", { class: "section-title", text: title })); group = title; }
    if (r.done) nodes.push(h("article", { class: "card reminder done" }, button(r.text, () => app.go("reminders", r.id), "text-button"), h("p", { class: "meta", text: longDate(new Date(r.due)) }), badge("done")));
    else nodes.push(reminderRow(app, r));
  }
  return nodes;
}

export function reminderRow(app: App, r: Reminder, detail = false, compact = false) {
  const due = new Date(r.due);
  const missed = r.due < Date.now();
  const by = r.from === "you" ? "" : ` · set by ${agentShort(r.from)}`;
  const where = r.project ? ` · ${folder(r.project)}` : "";
  // Done, Skip and Snooze go through the series engine (src-tauri/src/reminders.rs).
  let busy = false;
  const update = async (answer: Record<string, unknown>, done: string) => {
    if (busy) return;
    busy = true;
    try {
      await invoke("answer_reminder", { id: r.id, ...answer });
      app.toast(done);
      await app.refresh();
    } catch (error) {
      app.toast(problem(error), undefined, true);
    } finally { busy = false; }
  };
  const edit = () => {
    let close = () => {};
    const editor = sheet("Edit reminder", editRow(app, r, () => close()));
    close = editor.close;
  };
  const remove = async () => {
    try {
      const removed = await invoke<Reminder | null>("remove_reminder", { id: r.id });
      await app.refresh();
      app.redraw(true);
      if (removed) app.toast("Reminder deleted.", { label: "Undo", run: async () => {
        await invoke("restore_reminder", { reminder: removed });
        await app.refresh();
        app.redraw(true);
      } });
    } catch (error) { app.toast(problem(error), undefined, true); }
  };
  const confirmDelete = () => {
    const content = h("div", {}, h("p", { text: r.repeat ? "Skip this occurrence and keep the series, or delete the entire series and its history?" : `Delete “${r.text}”?` }));
    const editor = sheet(r.repeat ? "Delete repeating reminder" : "Delete reminder", content);
    content.append(h("div", { class: "actions sheet-actions" }, button("Cancel", editor.close),
      r.repeat ? button("Skip this occurrence", () => { editor.close(); void update({ action: "skip" }, "Skipped. The next one is scheduled."); }) : null,
      button(r.repeat ? "Delete entire series" : "Delete reminder", () => { editor.close(); void remove(); }, "danger")));
  };
  if (r.event && !isScheduledReminder(r) && !r.done) {
    return h("article", { class: "card reminder" }, h("div", { class: "row" },
      h("div", { class: "identity-text" }, detail ? h("strong", { text: r.text }) : button(r.text, () => app.go("reminders", r.id), "text-button"),
        h("p", { class: "meta", text: eventDescription(r) })),
      overflow(r.text, [{ label: "Delete reminder…", run: confirmDelete, destructive: true }])));
  }
  const snooze = (choice: string) => {
    const due = snoozeUntil(choice);
    void update({ action: "snooze", until: due.getTime() }, `Snoozed until ${longDate(due)}.`);
  };
  const menu = [
    ...[["10", "Snooze 10 min"], ["60", "Snooze 1 hour"], ["evening", new Date().getHours() < 18 ? "This evening 18:00" : "Tomorrow 18:00"], ["tomorrow", "Tomorrow 9:00"]].map(([value, label]) => ({ label, run: () => snooze(value) })),
    ...([10, 60].includes(app.state.settings.snooze_mins) ? [] : [{ label: `Snooze ${app.state.settings.snooze_mins} min (default)`, run: () => snooze(String(app.state.settings.snooze_mins)) }]),
    { label: "Pick snooze time…", run: () => pickSnooze(r.text, async (due) => { await invoke("answer_reminder", { id: r.id, action: "snooze", until: due.getTime() }); await app.refresh(); app.toast(`Snoozed until ${longDate(due)}.`); }) },
    ...(r.repeat ? [{ label: "Skip this one", run: () => void update({ action: "skip" }, "Skipped. The next one is scheduled.") }] : []),
    { label: "Edit", run: edit },
    { label: r.repeat ? "Delete…" : "Delete reminder…", run: confirmDelete, destructive: true },
  ];
  return h("article", { class: "card reminder" }, h("div", { class: "row" },
    compact ? h("time", { class: "reminder-time", datetime: due.toISOString(), text: due.toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" }) }) : null,
    h("div", { class: "identity-text" },
      detail ? h("strong", { text: r.text }) : button(r.text, () => app.go("reminders", r.id), "text-button"),
      h("p", { class: "meta", text: `${missed ? "Was due " : ""}${longDate(due)}${r.repeat ? `, then ${describeRepeat(r.repeat, new Date(r.anchor || r.due))}` : ""}${where}${by}` })),
    h("div", { class: "inline" },
      button(icon("done"), () => void update({ action: "done" }, r.repeat ? "Next repeat scheduled." : "Marked complete."), "icon-button", { "aria-label": `Mark ${r.text} complete` }),
      overflow(r.text, menu))));
}

function editRow(app: App, r: Reminder, close: () => void) {
  const edit = fields(`edit-${r.id}`, r);
  let scope: "this_one" | "all_future" | undefined;
  const scopes = h("fieldset", { class: "field wide" }, h("legend", { text: "Change" }));
  if (r.repeat) for (const [value, label] of [["this_one", "This one"], ["all_future", "All future"]] as const) {
    const radio = h("input", { type: "radio", name: `scope-${r.id}`, value, required: true });
    radio.addEventListener("change", () => { scope = value; edit.scope(value === "this_one"); });
    scopes.append(h("label", {}, radio, label));
  }
  const error = h("p", { class: "field-error", role: "alert" });
  const form = h(
    "form",
    { class: "card reminder editing", "aria-label": `Edit ${r.text}` },
    r.repeat ? scopes : null, edit.node, error,
    h("div", { class: "actions" }, button("Cancel", close), h("button", { type: "submit", class: "primary", text: "Save changes" })),
  );
  form.addEventListener("submit", async (event) => {
    event.preventDefault();
    const value = edit.read();
    if (!value) return;
    if (r.repeat && !scope) { error.textContent = "Choose This one or All future."; return; }
    const submit = form.querySelector<HTMLButtonElement>("button[type=submit]")!;
    if (submit.disabled) return;
    submit.disabled = true;
    try {
      await invoke("update_reminder", { id: r.id, change: { text: value.text, ...(value.due.getTime() !== r.due ? { due: value.due.getTime() } : {}), scope: scope ?? "all_future", expected_occurrence: r.occurrence || r.due, ...(scope === "this_one" || !value.repeatChanged ? {} : { repeat: value.repeat ?? null, clear_repeat: !value.repeat }) } });
      close();
      app.toast(`Saved for ${longDate(value.due)}.`);
      await app.refresh();
      app.redraw(true);
    } catch (reason) {
      error.textContent = problem(reason);
      submit.disabled = false;
    }
  });
  requestAnimationFrame(edit.focus);
  return form;
}
