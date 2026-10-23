import type { JournalEntry } from "./away";

// The dashboard's Activity: the journal as a timeline, newest first, grouped by day.

const MARKS: Record<string, string> = {
  start: "▶︎",
  prompt: "✎",
  waiting: "…",
  ask: "?",
  answer: "↩︎",
  done: "✓",
  failed: "!",
  end: "■",
};

/** One line per journal entry, in words. */
export function describeEntry(e: JournalEntry): { title: string; detail: string } {
  const who = e.source === "codex" ? "Codex" : e.source === "claude" ? "Claude" : "An agent";
  switch (e.kind) {
    case "start":
      return { title: `${who} started a session`, detail: "" };
    case "prompt":
      return { title: `You asked ${who}`, detail: e.detail };
    case "waiting":
      return { title: `${who} waited for you`, detail: e.detail };
    case "ask":
      return { title: `${who} asked`, detail: e.detail };
    case "answer":
      return { title: `Answer: ${e.detail}`, detail: "" };
    case "done":
      return { title: `${who} finished`, detail: e.detail };
    case "failed":
      return { title: `${who} hit a problem`, detail: e.detail };
    case "end":
      return { title: `${who} session ended`, detail: e.detail };
    default:
      return { title: `${who}: ${e.kind}`, detail: e.detail };
  }
}

const folder = (path: string) => path.split("/").filter(Boolean).pop() ?? "";

export function projects(entries: JournalEntry[]): string[] {
  return [...new Set(entries.map((e) => e.project).filter(Boolean))].sort((a, b) => folder(a).localeCompare(folder(b)));
}

export function renderActivity(root: HTMLElement, entries: JournalEntry[], project: string) {
  const shown = entries.filter((e) => !project || e.project === project).sort((a, b) => b.at - a.at).slice(0, 400);
  if (!shown.length) {
    const empty = document.createElement("p");
    empty.className = "empty";
    empty.textContent = "Nothing recorded for this period. Connect Claude Code (Agents) to start the journal.";
    return root.replaceChildren(empty);
  }
  const nodes: HTMLElement[] = [];
  let day = "";
  for (const e of shown) {
    const date = new Date(e.at);
    const label = date.toLocaleDateString([], { weekday: "long", day: "numeric", month: "long" });
    if (label !== day) {
      day = label;
      const heading = document.createElement("div");
      heading.className = "day";
      heading.textContent = label;
      nodes.push(heading);
    }
    const { title, detail } = describeEntry(e);
    const row = document.createElement("div");
    row.className = "event";
    const time = document.createElement("time");
    time.textContent = date.toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" });
    const mark = document.createElement("span");
    mark.className = "mark";
    mark.textContent = MARKS[e.kind] ?? "·";
    const body = document.createElement("div");
    const strong = document.createElement("strong");
    strong.textContent = e.project ? `${folder(e.project)} · ${title}` : title;
    body.append(strong);
    if (detail) {
      const p = document.createElement("p");
      p.textContent = detail;
      body.append(p);
    }
    row.append(time, mark, body);
    nodes.push(row);
  }
  root.replaceChildren(...nodes);
}
