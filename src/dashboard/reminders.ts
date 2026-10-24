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
  const textError = h("p", { class: "field-error", id: `${prefix}-text-error`, role: "alert" });
  const whenError = h("p", { class: "field-error", id: `${prefix}-when-error`, role: "alert" });
  const resolved = h("p", { class: "hint", "aria-live": "polite" });
  let typedWhen = !!initial;
  const update = () => {
    // A time typed in the title fills the fields, unless they were set by hand.
    const parsed = parseReminder(text.value);
    if (parsed && !typedWhen) {
      date.value = dateValue(parsed.due);
      time.value = timeValue(parsed.due);
    }
    const when = fromFields(date.value, time.value);
    resolved.textContent = when ? `Reminds you ${longDate(when)} (${timeZone()}).` : `Times are in your time zone, ${timeZone()}.`;
  };
  text.addEventListener("input", update);
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
    h("div", { class: "wide" }, whenError, resolved),
  );
  /** Checks the fields; returns what to save, or null with errors shown next to the fields. */
  const read = (): { text: string; due: Date; repeat?: Repeat } | null => {
    const parsed = parseReminder(text.value);
    const what = (parsed && !typedWhen ? parsed.what : text.value).trim();
    const when = fromFields(date.value, time.value);
    textError.textContent = what ? "" : "Enter what to remember.";
    whenError.textContent = !when ? "Choose a date and a time." : when.getTime() <= Date.now() && !initial ? "That time has passed. Choose a later one." : "";
    // "every weekday at 9 to…" typed in the title keeps its repeat, even with the time changed by hand.
    return what && when && !whenError.textContent ? { text: what, due: when, repeat: parsed?.repeat } : null;
  };
  return { node, read, focus: () => text.focus() };
}

let editing: string | null = null;

export function renderReminders(app: App, arg = "") {
  const view = h("div", { class: "view" }, ...header("Reminders", "Small things, remembered."));
  const add = fields("new");
  const form = h("form", { class: "card", "aria-label": "Add a reminder" }, add.node, h("div", { class: "actions" }, h("button", { type: "submit", class: "primary", text: "Add reminder" })));
  form.addEventListener("submit", async (event) => {
    event.preventDefault();
    const value = add.read();
    if (!value) return;
    try {
      const added = await invoke<Reminder>("add_reminder", { text: value.text, due: value.due.getTime(), project: null, repeat: value.repeat ?? null });
      app.toast(`Reminder set for ${longDate(value.due)}${value.repeat ? `, then ${describeRepeat(value.repeat, value.due)}` : ""}.`, {
        label: "Undo",
        run: () => void invoke("remove_reminder", { id: added.id }).then(() => app.refresh()),
      });
      (document.activeElement as HTMLElement | null)?.blur();
      await app.refresh();
      app.redraw(true);
    } catch (error) {
      app.toast(`Not saved: ${error}`, undefined, true);
    }
  });
  view.append(form);

  const list = h("section", { "aria-label": "Your reminders" });
  const fill = () => list.replaceChildren(...rows(app));
  fill();
  // Live updates refresh the list and leave a half-typed reminder alone.
  app.live(() => {
    if (!editing) fill();
  });
  view.append(list);
  // File → New Reminder (⌘N) lands here with the title field ready.
  if (arg === "new") requestAnimationFrame(() => add.node.querySelector<HTMLInputElement>("#new-text")?.focus());
  return view;
}

function rows(app: App): HTMLElement[] {
  const all = app.state.reminders;
  const open = all.filter((r) => !r.done).sort((a, b) => a.due - b.due);
  const done = all.filter((r) => r.done).sort((a, b) => b.due - a.due).slice(0, 5);
  const nodes: HTMLElement[] = [h("h2", { class: "section-title", text: "Coming up" })];
  if (!open.length) nodes.push(h("section", { class: "card empty" }, h("strong", { text: "A little space for later." }), h("p", { text: "Your reminders will appear here. Add one above, or type “remind me…” to a companion." })));
  for (const r of open) nodes.push(editing === r.id ? editRow(app, r) : row(app, r));
  if (done.length) {
    nodes.push(h("h2", { class: "section-title", text: "Completed" }));
    for (const r of done) nodes.push(h("article", { class: "card reminder done" }, h("div", { class: "row" }, h("div", {}, h("strong", { text: r.text }), h("p", { class: "meta", text: longDate(new Date(r.due)) })), badge("done"))));
  }
  return nodes;
}

function row(app: App, r: Reminder) {
  const due = new Date(r.due);
  const missed = r.due < Date.now();
  const by = r.from === "you" ? "" : ` · set by ${agentShort(r.from)}`;
  const where = r.project ? ` · ${folder(r.project)}` : "";
  const update = async (change: Record<string, unknown>, done: string) => {
    try {
      await invoke("update_reminder", { id: r.id, change });
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
      h("div", {}, h("strong", { text: r.text }), h("p", { class: "meta", text: `${missed ? "Was due " : ""}${longDate(due)}${r.repeat ? `, then ${describeRepeat(r.repeat, due)}` : ""}${where}${by}` })),
      h(
        "div",
        { class: "actions" },
        button("Edit", () => {
          editing = r.id;
          app.redraw(true);
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
        button([icon("done"), "Mark complete"], () => void update({ done: true }, "Marked complete."), ""),
      ),
    ),
  );
}

function editRow(app: App, r: Reminder) {
  const edit = fields(`edit-${r.id}`, r);
  const form = h(
    "form",
    { class: "card reminder editing", "aria-label": `Edit ${r.text}` },
    edit.node,
    h("div", { class: "actions" }, button("Cancel", () => ((editing = null), app.redraw(true))), h("button", { type: "submit", class: "primary", text: "Save changes" })),
  );
  form.addEventListener("submit", async (event) => {
    event.preventDefault();
    const value = edit.read();
    if (!value) return;
    try {
      await invoke("update_reminder", { id: r.id, change: { text: value.text, due: value.due.getTime() } });
      editing = null;
      app.toast(`Saved for ${longDate(value.due)}.`);
      await app.refresh();
      app.redraw(true);
    } catch (error) {
      app.toast(`Not saved: ${error}`, undefined, true);
    }
  });
  requestAnimationFrame(edit.focus);
  return form;
}
