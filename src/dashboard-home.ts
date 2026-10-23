import { PALETTES, SPECIES, type PaletteName, type SpeciesName } from "./pet/look";
import type { Reminder } from "./reminders";
import { describeDue } from "./when";

// The dashboard's Home: what is waiting on you, every pet and its sessions, what is coming
// up and whether the agents are connected. Agent text is untrusted: textContent only.

/** Mirrors `status()` in crew.ts. */
export type Status = {
  pets: {
    id: string;
    name: string;
    label: string;
    main: boolean;
    project: string | null;
    look: { species: string; palette: string };
    out: boolean;
    clip: string;
    sessions: { source: string; verb: string; state: string; detail: string; at: number }[];
    outcomes: { kind: string; source: string; detail: string; at: number }[];
  }[];
  waiting: { id: string; pet: string; who: string; title: string; detail: string; choices: { label: string; value: string }[] }[];
};

export type HomeActions = {
  answer(id: string, value: string): void;
  call(id: string): void;
  customize(id: string): void;
  open(tab: string): void;
};

const el = <K extends keyof HTMLElementTagNameMap>(tag: K, text?: string, className = "") => {
  const node = document.createElement(tag);
  if (className) node.className = className;
  if (text !== undefined) node.textContent = text;
  return node;
};
const agent = (source: string) => (source === "codex" ? "Codex" : source === "claude" ? "Claude" : "An agent");
const ago = (at: number) => {
  const m = Math.round((Date.now() - at) / 60_000);
  return m < 1 ? "just now" : m < 60 ? `${m} min ago` : m < 1440 ? `${Math.round(m / 60)} h ago` : `${Math.round(m / 1440)} d ago`;
};

export function greeting(now = new Date()) {
  const h = now.getHours();
  return h < 5 ? "Working late" : h < 12 ? "Good morning" : h < 18 ? "Good afternoon" : "Good evening";
}

export function renderHome(status: Status, reminders: Reminder[], connections: Record<string, boolean>, actions: HomeActions) {
  const sessions = status.pets.reduce((n, p) => n + p.sessions.length, 0);
  const out = status.pets.filter((p) => p.out).length;
  document.querySelector("#greeting")!.textContent = greeting();
  document.querySelector("#summary")!.textContent = [
    `${status.pets.length} ${status.pets.length === 1 ? "pet" : "pets"}, ${out} on screen`,
    sessions ? `${sessions} agent ${sessions === 1 ? "session" : "sessions"} running` : "no agent sessions running",
    status.waiting.length ? `${status.waiting.length} waiting for you` : "nothing waiting for you",
  ].join(" · ");
  const badge = document.querySelector<HTMLElement>("#waiting-badge")!;
  badge.hidden = !status.waiting.length;
  badge.textContent = String(status.waiting.length);

  document.querySelector("#waiting")!.replaceChildren(
    ...status.waiting.map((w) => {
      const card = el("div", undefined, "waiting");
      card.append(el("div", w.who, "who"), el("p", w.title, "title"));
      if (w.detail) card.append(el("code", w.detail));
      const buttons = el("div", undefined, "actions");
      w.choices.forEach((choice, i) => {
        const b = el("button", choice.label, i === 0 ? "primary" : "");
        b.addEventListener("click", () => actions.answer(w.id, choice.value));
        buttons.append(b);
      });
      card.append(buttons);
      return card;
    }),
  );

  document.querySelector("#home-pets")!.replaceChildren(
    ...status.pets.map((p) => {
      const card = el("article", undefined, "pet-card");
      const head = el("header");
      const dot = el("span", undefined, "dot");
      dot.style.background = PALETTES[p.look.palette as PaletteName]?.body ?? PALETTES.snow.body;
      const who = el("div");
      who.append(el("strong", p.name));
      const species = SPECIES[p.look.species as SpeciesName]?.label ?? "Imported";
      who.append(el("p", p.main ? `${species} · main pet` : `${species} · ${p.label.split(" · ")[1] ?? "crew"}`));
      const top = p.sessions[0];
      const state = el("span", top?.state === "waiting" ? "needs you" : top ? "working" : p.out ? p.clip : "in the den", "state");
      if (top) state.classList.add(top.state === "waiting" ? "alert" : "busy");
      head.append(dot, who, state);
      card.append(head);
      const list = el("ul");
      for (const s of p.sessions.slice(0, 3)) list.append(el("li", `${agent(s.source)} · ${s.verb}${s.detail && s.state !== "waiting" ? ` ${s.detail}` : ""}`));
      for (const o of p.outcomes.slice(0, p.sessions.length ? 1 : 2))
        list.append(el("li", `${agent(o.source)} ${o.kind === "done" ? "finished" : "hit a problem"} ${ago(o.at)}${o.detail ? `: ${o.detail}` : ""}`, "quiet"));
      if (!list.children.length) list.append(el("li", "Nothing yet today.", "quiet"));
      card.append(list);
      const foot = el("footer");
      if (!p.main) {
        const call = el("button", p.out ? "Briefing" : "Call");
        call.addEventListener("click", () => actions.call(p.id));
        foot.append(call);
      }
      const look = el("button", "Customize");
      look.addEventListener("click", () => actions.customize(p.id));
      foot.append(look);
      card.append(foot);
      return card;
    }),
  );

  const next = reminders.filter((r) => !r.done).sort((a, b) => a.due - b.due).slice(0, 4);
  const upcoming = next.map((r) => {
    const row = el("div", undefined, "row");
    const text = el("div");
    text.append(el("strong", r.text), el("p", describeDue(new Date(r.due))));
    row.append(text);
    return row;
  });
  const all = el("button", next.length ? "All reminders" : "Add a reminder");
  all.addEventListener("click", () => actions.open("reminders"));
  const footer = el("div", undefined, "row");
  footer.append(el("span"), all);
  document.querySelector("#home-reminders")!.replaceChildren(...(next.length ? upcoming : [el("p", "Nothing coming up.", "empty")]), footer);

  const items: [string, string][] = [
    ["claude_hooks", "Claude Code activity"],
    ["claude_tools", "Pet tools in Claude Code"],
    ["codex_tools", "Pet tools in Codex"],
  ];
  const rows = items.map(([key, label]) => {
    const row = el("div", undefined, "row");
    row.append(el("span", label), el("span", connections[key] ? "Connected" : "Off", connections[key] ? "pill on" : "pill"));
    return row;
  });
  const manage = el("button", "Manage");
  manage.addEventListener("click", () => actions.open("agents"));
  const footer2 = el("div", undefined, "row");
  footer2.append(el("span"), manage);
  document.querySelector("#home-connections")!.replaceChildren(...rows, footer2);
}
