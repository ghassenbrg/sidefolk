import { icon, mark, type IconName } from "../icons";
import { badge, stateOf, type State } from "../states";
import { invoke, type PetStatus, type SessionInfo, type Status, type Waiting } from "./api";
import type { App } from "./app";
import { agentShort, button, folder, h } from "./dom";

/** A page's heading: an h1 that takes focus after navigation, and a plain-language lead. */
export function header(title: string, lead?: string, eyebrow?: string): HTMLElement[] {
  const nodes: HTMLElement[] = [];
  if (eyebrow) nodes.push(h("p", { class: "eyebrow", text: eyebrow }));
  nodes.push(h("h1", { text: title, tabindex: "-1" }));
  if (lead) nodes.push(h("p", { class: "lead", text: lead }));
  return nodes;
}

export function back(label: string, run: () => void) {
  return button([icon("back"), label], run, "back");
}

/** The companion's mark + "Name · project" + a second line ("Codex · Work session 04c1"). */
export function identity(name: string, project: string | null, second?: string) {
  const text = h("div", { class: "identity-text" }, h("strong", {}, name, project ? h("span", { class: "project", text: ` · ${folder(project)}` }) : null));
  if (second) text.append(h("span", { class: "meta", text: second }));
  return h("div", { class: "identity" }, h("span", { class: "avatar" }, mark(30, "")), text);
}

/** "Work session 04c1": the short form people can tell apart; the full ID is in details. */
export const sessionLabel = (id?: string) => (id ? `Work session ${id.replace(/[^a-z0-9]/gi, "").slice(0, 4)}` : "Work session");

/** What a pet is doing, as one status from the shared vocabulary. */
export function petState(pet: PetStatus, waiting: Waiting[], now = Date.now()): State {
  if (waiting.some((w) => w.pet === pet.id)) return "alert";
  const top = pet.sessions[0];
  if (top) return stateOf(top.state);
  if (pet.clip === "sleep") return "sleep";
  const last = pet.outcomes[0];
  if (last && now - last.at < 10 * 60_000) return last.kind === "done" ? "done" : "failed";
  return "idle";
}

/** One factual sentence about a pet ("Claude is editing launch-notes.md."). */
export function petLine(pet: PetStatus, now = Date.now()) {
  const top = pet.sessions[0];
  if (top) return `${agentShort(top.source)} is ${top.verb === "needs you" ? "waiting for your answer" : top.verb}${top.detail && top.state !== "waiting" ? ` ${top.detail}` : ""}.`;
  const last = pet.outcomes[0];
  if (last) {
    const m = Math.round((now - last.at) / 60_000);
    const when = m < 1 ? "just now" : m < 60 ? `${m} min ago` : m < 1440 ? `${Math.round(m / 60)} h ago` : `${Math.round(m / 1440)} d ago`;
    return `${agentShort(last.source)} ${last.kind === "done" ? "finished" : "stopped with a problem"} ${when}${last.detail ? `: ${last.detail}` : "."}`;
  }
  return "Nothing running right now.";
}

/** The session "Open session" would open: the live one first, else the last that ended. */
export function sessionOf(pet: PetStatus): { source: string; session: string; cwd: string; live: boolean } | null {
  const live = pet.sessions.find((s) => s.id);
  if (live) return { source: live.source, session: live.id, cwd: live.cwd || live.project, live: true };
  const last = pet.outcomes.find((o) => o.session);
  return last ? { source: last.source, session: last.session!, cwd: last.cwd || last.project, live: false } : null;
}

export function statusBadge(state: State) {
  return badge(state);
}

/** A request in plain words ("Codex wants to run a command."). */
export function requestTitle(w: Waiting) {
  const agent = agentShort(w.meta.source ?? "");
  switch (w.meta.kind) {
    case "permission": {
      const action = { command: "run a command", file: "change a file", web: "open a web page", tool: "use a tool" }[w.meta.action] ?? "do something";
      return `${agent} wants to ${action}.`;
    }
    case "question":
      return `${agent} has a question.`;
    case "offer":
      return w.title;
    case "reminder":
      return `Reminder: ${w.meta.text ?? w.title}`;
    default:
      return w.title;
  }
}

export function petOf(status: Status, id: string) {
  return status.pets.find((p) => p.id === id) ?? null;
}

export function empty(title: string, text: string, ...actions: HTMLElement[]) {
  return h("section", { class: "card empty" }, h("strong", { text: title }), h("p", { text }), actions.length ? h("div", { class: "actions" }, ...actions) : null);
}

export function navIcon(name: IconName) {
  return icon(name);
}

/** A live work session: tool · project, what it's doing, its permission mode and Open. */
export function sessionRow(app: App, s: SessionInfo, compact = false) {
  return h(
    "div",
    { class: "row line" },
    h("div", { class: "identity-text" }, h("strong", { text: `${agentShort(s.source)} · ${folder(s.project || s.cwd)}` }), h("span", { class: "meta", text: `${sessionLabel(s.id)} · ${s.verb}${s.detail && s.state !== "waiting" ? ` ${s.detail}` : ""}` })),
    h(
      "div",
      { class: "inline" },
      badge(stateOf(s.state)),
      // Off by default; the current mode is always shown, never changed silently.
      s.id && !compact
        ? button(s.fullAccess ? "Full access" : "Asks first", () => void app.petAction({ action: "full-access", source: s.source, session: s.id, on: !s.fullAccess }, s.fullAccess ? "This session asks again." : "Full access on. Risky commands still ask."), `small access${s.fullAccess ? " on" : ""}`, {
            "aria-pressed": String(!!s.fullAccess),
            title: s.fullAccess ? "Requests from this session are allowed without asking, except risky ones. Click to ask again." : "This session asks before running commands or changing files. Click to give it full access.",
          })
        : null,
      s.id ? button([icon("open"), s.state === "waiting" ? "Review" : "Open"], () => {
        const request = app.state.status.waiting.find((w) => w.meta.session === s.id && w.meta.source === s.source);
        if (request && s.state === "waiting") app.go("review", request.id);
        else void app.openSession({ source: s.source, session: s.id, cwd: s.cwd || s.project });
      }, "small") : null,
    ),
  );
}


export function folderPicker(app: App, input: HTMLInputElement) {
  return h("div", { class: "inline folder-picker" }, input, button([icon("folder"), "Browse…"], async () => {
    try {
      const path = await invoke<string | null>("choose_project_folder");
      if (path) { input.value = path; input.dispatchEvent(new Event("input", { bubbles: true })); }
      input.focus();
    } catch (error) { app.toast(String(error), undefined, true); }
  }));
}
