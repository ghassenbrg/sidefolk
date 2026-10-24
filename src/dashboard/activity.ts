import type { JournalEntry } from "../away";
import { icon, type IconName } from "../icons";
import { invoke } from "./api";
import type { App } from "./app";
import { agentShort, button, folder, h } from "./dom";
import { back, header } from "./ui";

// Activity: what the AI tools did, from the journal kept on this Mac (30 days), newest first
// and grouped by day. A work session that ended can be continued from here.

const MARKS: Record<string, IconName> = {
  start: "next",
  prompt: "requests",
  waiting: "alert",
  ask: "alert",
  answer: "done",
  done: "done",
  failed: "failed",
  end: "idle",
};

/** One line per journal entry, in words. */
export function describeEntry(e: JournalEntry): { title: string; detail: string } {
  const who = agentShort(e.source);
  switch (e.kind) {
    case "start":
      return { title: `${who} started a work session`, detail: "" };
    case "prompt":
      return { title: `You asked ${who}`, detail: e.detail };
    case "waiting":
      return { title: `${who} waited for your answer`, detail: e.detail };
    case "ask":
      return { title: `${who} asked`, detail: e.detail };
    case "answer":
      return { title: e.detail === "denied" ? "You declined" : e.detail === "allowed" ? "You allowed it once" : `Answer: ${e.detail}`, detail: "" };
    case "done":
      return { title: `${who} finished`, detail: e.detail };
    case "failed":
      return { title: `${who} stopped with a problem`, detail: e.detail };
    case "end":
      return { title: `${who}'s work session ended`, detail: e.detail };
    default:
      return { title: `${who}: ${e.kind}`, detail: e.detail };
  }
}

export function projects(entries: JournalEntry[]): string[] {
  return [...new Set(entries.map((e) => e.project).filter(Boolean))].sort((a, b) => folder(a).localeCompare(folder(b)));
}

let period = 1;
let project = "";
let entries: JournalEntry[] | null = null;
let loadedFor = 0;

export function renderActivity(app: App) {
  if (loadedFor !== period) {
    loadedFor = period;
    entries = null;
    void invoke<JournalEntry[]>("journal_since", { since: Date.now() - period * 86_400_000 })
      .then((list) => ((entries = list), app.redraw(true)))
      .catch(() => ((entries = []), app.redraw(true)));
  }
  app.live(() => {});
  const view = h("div", { class: "view" }, back("Back to Home", () => app.go("home")), ...header("Recent activity", "What your AI tools did, from the journal kept on this Mac for 30 days."));
  const periods = h("div", { class: "segmented", role: "radiogroup", "aria-label": "Period" });
  for (const [days, label] of [
    [1, "Today"],
    [7, "7 days"],
    [30, "30 days"],
  ] as const)
    periods.append(button(label, () => ((period = days), app.redraw(true)), "", { role: "radio", "aria-checked": String(period === days) }));
  const select = h("select", { id: "activity-project", "aria-label": "Project" }, h("option", { value: "", text: "All projects" }));
  for (const p of projects(entries ?? [])) select.append(h("option", { value: p, text: folder(p) }));
  select.value = project;
  select.addEventListener("change", () => {
    project = select.value;
    select.blur();
    app.redraw(true);
  });
  view.append(h("div", { class: "toolbar" }, periods, select));

  const list = h("section", { class: "card timeline" });
  const shown = (entries ?? []).filter((e) => !project || e.project === project).sort((a, b) => b.at - a.at).slice(0, 400);
  if (entries === null) list.append(h("p", { class: "muted", text: "Loading…" }));
  else if (!shown.length) list.append(h("p", { class: "muted", text: "Nothing recorded for this period. Connect Claude Code in Settings to start the journal." }));
  let day = "";
  for (const e of shown) {
    const date = new Date(e.at);
    const label = date.toLocaleDateString([], { weekday: "long", day: "numeric", month: "long" });
    if (label !== day) list.append(h("h3", { class: "day", text: (day = label) }));
    const { title, detail } = describeEntry(e);
    const body = h("div", {}, h("strong", { text: e.project ? `${folder(e.project)} · ${title}` : title }), detail ? h("p", { class: "muted", text: detail }) : null);
    const ended = (e.kind === "done" || e.kind === "failed" || e.kind === "end") && e.session && (e.source === "claude" || e.source === "codex");
    list.append(
      h(
        "div",
        { class: "event" },
        h("time", { text: date.toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" }) }),
        h("span", { class: "mark" }, icon(MARKS[e.kind] ?? "idle")),
        body,
        ended ? button([icon("terminal"), "Continue"], () => void app.openSession({ source: e.source, session: e.session, cwd: e.project }, true), "small", { title: "Continue this work session in a terminal" }) : h("span"),
      ),
    );
  }
  view.append(list);
  return view;
}
