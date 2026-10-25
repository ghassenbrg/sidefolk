import { sheet } from "./dialog";
import { icon } from "../icons";
import { badge } from "../states";
import { describeRepeat, parseReminder, type Repeat } from "../when";
import { invoke, type Reminder } from "./api";
import type { App } from "./app";
import { agentShort, button, folder, h, timeZone } from "./dom";
import { header } from "./ui";

// Reminders: a labelled title and explicit date and time fields. Typing a time in the title
// ("tomorrow at 10") fills them in; the resolved date and time zone show before saving.

const pad = (n: number) => String(n).padStart(2, "0");
const dateValue = (d: Date) => `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
const timeValue = (d: Date) => `${pad(d.getHours())}:${pad(d.getMinutes())}`;

/** Local date + time fields to a moment; the Date constructor resolves daylight-saving gaps. */
export function fromFields(date: string, time: string): Date | null {
  const d = /^(\d{4})-(\d{2})-(\d{2})$/.exec(date);
  const t = /^(\d{1,2}):(\d{2})$/.exec(time);
  if (!d || !t) return null;
  const value = new Date(Number(d[1]), Number(d[2]) - 1, Number(d[3]), Number(t[1]), Number(t[2]));
  return Number.isNaN(value.getTime()) ? null : value;
}

export const longDate = (d: Date) =>
  d.toLocaleString([], { weekday: "long", day: "numeric", month: "long", hour: "2-digit", minute: "2-digit" });

/** The form fields; reused for adding and for editing one reminder. */
function fields(prefix: string, initial?: Reminder) {
  const due = initial ? new Date(initial.due) : null;
  const text = h("input", { type: "text", id: `${prefix}-text`, maxlength: 300, autocomplete: "off", value: initial?.text ?? "", placeholder: "Review launch notes", "aria-describedby": `${prefix}-text-error` });
  const date = h("input", { type: "date", id: `${prefix}-date`, value: due ? dateValue(due) : "", "aria-describedby": `${prefix}-when-error` });
  const time = h("input", { type: "time", id: `${prefix}-time`, value: due ? timeValue(due) : "", "aria-describedby": `${prefix}-when-error` });
  const repeat = h("select", { id: `${prefix}-repeat` });
  for (const [value, label] of [["", "None"], ["day", "Every day"], ["weekday", "Weekdays"], ["week", "Weekly"], ["month", "Monthly"]])
    repeat.append(h("option", { value, text: label }));
  repeat.value = initial?.repeat?.every ?? "";
  const interval = h("input", { type: "number", id: `${prefix}-interval`, min: 1, max: 52, step: 1, value: String(initial?.repeat?.n ?? 1) });
  const intervalField = h("div", { class: "field" }, h("label", { for: interval.id, text: "Every how many?" }), interval);
  let typedRepeat = !!initial;
  const selectedRepeat = (): Repeat | undefined => repeat.value ? { every: repeat.value as Repeat["every"], n: repeat.value === "weekday" ? 1 : Number(interval.value) } : undefined;
  const textError = h("p", { class: "field-error", id: `${prefix}-text-error`, role: "alert" });
  const whenError = h("p", { class: "field-error", id: `${prefix}-when-error`, role: "alert" });
  const resolved = h("p", { class: "hint", "aria-live": "polite" });
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
    }
    intervalField.hidden = !repeat.value || repeat.value === "weekday";
    const when = fromFields(date.value, time.value);
    const recurrence = selectedRepeat();
    resolved.textContent = when ? `Reminds you ${longDate(when)} (${timeZone()})${recurrence ? `, then ${describeRepeat(recurrence, when)}` : ""}.` : `Times are in your time zone, ${timeZone()}.`;
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
    h("div", { class: "field" }, h("label", { for: date.id, text: "Date" }), date),
    h("div", { class: "field" }, h("label", { for: time.id, text: "Time" }), time),
    h("div", { class: "field" }, h("label", { for: repeat.id, text: "Repeat" }), repeat),
    intervalField,
    h("div", { class: "wide" }, whenError, resolved),
  );
  /** Checks the fields; returns what to save, or null with errors shown next to the fields. */
  const read = (): { text: string; due: Date; repeat?: Repeat } | null => {
    const parsed = parseReminder(text.value);
    const what = (parsed && (!initial || changedText) ? parsed.what : text.value).trim();
    const when = fromFields(date.value, time.value);
    textError.textContent = what ? "" : "Enter what to remember.";
    whenError.textContent = !when ? "Choose a date and a time." : when.getTime() <= Date.now() && !initial ? "That time has passed. Choose a later one." : "";
    const recurrence = selectedRepeat();
    if (recurrence && (!Number.isInteger(recurrence.n) || recurrence.n < 1 || recurrence.n > 52)) whenError.textContent = "Choose a repeat interval from 1 to 52.";
    return what && when && !whenError.textContent ? { text: what, due: when, repeat: recurrence } : null;
  };
  return { node, read, focus: () => text.focus() };
}

let filter = "upcoming";

export function renderReminders(app: App, arg = "") {
  if (arg && arg !== "new") {
    const r = app.state.reminders.find((r) => r.id === arg);
    const view = h("div", { class: "view" }, button("Back to Reminders", () => app.go("reminders")), ...header(r?.text ?? "Reminder no longer exists", "Reminder details"));
    if (!r) return view;
    view.append(r.done ? h("p", { text: "Completed" }) : row(app, r, true));
    view.append(h("h2", { text: "History" }), h("ol", {}, ...(r.history?.length ? r.history : [{ at: r.created, action: "Created", due: r.due }]).map((entry) => h("li", {}, `${longDate(new Date(entry.at))} · ${entry.action} · due ${longDate(new Date(entry.due))}`))));
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

function addReminder(app: App) {
  const add = fields("new");
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
      filter = "upcoming";
      editor.close();
      await app.refresh();
      app.redraw(true);
      app.toast(`Reminder set for ${longDate(value.due)}.`, { label: "Undo", run: async () => { await invoke("remove_reminder", { id: added.id }); await app.refresh(); } });
    } catch (reason) { error.textContent = `Not saved: ${reason}`; submit.disabled = false; }
  });
  requestAnimationFrame(add.focus);
}

function rows(app: App): HTMLElement[] {
  const all = app.state.reminders;
  const open = all.filter((r) => !r.done).sort((a, b) => a.due - b.due);
  const done = all.filter((r) => r.done).sort((a, b) => b.due - a.due).slice(0, 5);
  const nodes: HTMLElement[] = [];
  const items = filter === "completed" ? done : filter === "repeating" ? open.filter((r) => r.repeat) : open;
  if (!items.length) nodes.push(h("section", { class: "card empty" }, h("strong", { text: filter === "completed" ? "Nothing completed yet." : "A little space for later." }), h("p", { text: filter === "repeating" ? "Repeating reminders will appear here." : "Add a reminder, or tell your companion what to remember." })));
  let group = "";
  const midnight = new Date(); midnight.setHours(0, 0, 0, 0);
  const tomorrow = new Date(midnight); tomorrow.setDate(tomorrow.getDate() + 1);
  const later = new Date(tomorrow); later.setDate(later.getDate() + 1);
  for (const r of items) {
    const title = filter === "completed" ? "Completed" : r.due < Date.now() ? "Overdue" : r.due < tomorrow.getTime() ? "Today" : r.due < later.getTime() ? "Tomorrow" : "Later";
    if (title !== group) { nodes.push(h("h2", { class: "section-title", text: title })); group = title; }
    if (r.done) nodes.push(h("article", { class: "card reminder done" }, h("strong", { text: r.text }), h("p", { class: "meta", text: longDate(new Date(r.due)) }), badge("done")));
    else nodes.push(row(app, r));
  }
  return nodes;
}

function row(app: App, r: Reminder, detail = false) {
  const due = new Date(r.due);
  const missed = r.due < Date.now();
  const by = r.from === "you" ? "" : ` · set by ${agentShort(r.from)}`;
  const where = r.project ? ` · ${folder(r.project)}` : "";
  // Done, Skip and Snooze go through the series engine (src-tauri/src/reminders.rs).
  const update = async (answer: Record<string, unknown>, done: string) => {
    try {
      await invoke("answer_reminder", { id: r.id, ...answer });
      app.toast(done);
      await app.refresh();
    } catch (error) {
      app.toast(`Not saved: ${error}`, undefined, true);
    }
  };
  return h(
    "article",
    { class: "card reminder" },
    h(
      "div",
      { class: "row" },
      h("div", {}, h("strong", { text: r.text }), h("p", { class: "meta", text: `${missed ? "Was due " : ""}${longDate(due)}${r.repeat ? `, then ${describeRepeat(r.repeat, new Date(r.anchor || r.due))}` : ""}${where}${by}` })),
      h(
        "div",
        { class: "actions" },
        !detail ? button("Open", () => app.go("reminders", r.id), "quiet") : null,
        button("Snooze 10 min", () => void update({ action: "snooze", until: Date.now() + 600_000 }, "Snoozed for 10 minutes."), "quiet", { "aria-label": `Snooze ${r.text} for 10 minutes` }),
        detail && r.repeat ? button("Skip this one", () => void update({ action: "skip" }, "Skipped. The next one is scheduled."), "quiet") : null,
        button("Edit", () => {
          let close = () => {};
          const editor = sheet("Edit reminder", editRow(app, r, () => close()));
          close = editor.close;
        }, "quiet"),
        button("Delete", async () => {
          try {
            const removed = await invoke<Reminder | null>("remove_reminder", { id: r.id });
            await app.refresh();
            app.redraw(true);
            if (removed)
              app.toast("Reminder deleted.", {
                label: "Undo",
                run: async () => {
                  await invoke("restore_reminder", { reminder: removed });
                  await app.refresh();
                  app.redraw(true);
                },
              });
          } catch (error) {
            app.toast(String(error), undefined, true);
          }
        }, "quiet"),
        button([icon("done"), "Mark complete"], () => void update({ action: "done" }, r.repeat ? "Next repeat scheduled." : "Marked complete."), "", { "aria-label": `Mark ${r.text} complete` }),
      ),
    ),
  );
}

function editRow(app: App, r: Reminder, close: () => void) {
  const edit = fields(`edit-${r.id}`, r);
  const form = h(
    "form",
    { class: "card reminder editing", "aria-label": `Edit ${r.text}` },
    edit.node,
    h("div", { class: "actions" }, button("Cancel", close), h("button", { type: "submit", class: "primary", text: "Save changes" })),
  );
  form.addEventListener("submit", async (event) => {
    event.preventDefault();
    const value = edit.read();
    if (!value) return;
    const submit = form.querySelector<HTMLButtonElement>("button[type=submit]")!;
    if (submit.disabled) return;
    submit.disabled = true;
    try {
      await invoke("update_reminder", { id: r.id, change: { text: value.text, due: value.due.getTime(), repeat: value.repeat ?? null, clear_repeat: !value.repeat } });
      close();
      app.toast(`Saved for ${longDate(value.due)}.`);
      await app.refresh();
      app.redraw(true);
    } catch (error) {
      app.toast(`Not saved: ${error}`, undefined, true);
      submit.disabled = false;
    }
  });
  requestAnimationFrame(edit.focus);
  return form;
}
