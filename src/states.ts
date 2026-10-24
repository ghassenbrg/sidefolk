import { icon, type IconName } from "./icons";

// One status vocabulary everywhere (the companion's badge, Home, Requests): a shape and a word for
// each state. The orb's colors only decorate the shape; the word carries the meaning.

export type State = "idle" | "think" | "work" | "alert" | "done" | "failed" | "sleep";

export const STATES: Record<State, { word: string; glyph: IconName }> = {
  idle: { word: "Idle", glyph: "idle" },
  think: { word: "Thinking", glyph: "think" },
  work: { word: "Working", glyph: "work" },
  alert: { word: "Needs you", glyph: "alert" },
  done: { word: "Done", glyph: "done" },
  failed: { word: "Failed", glyph: "failed" },
  sleep: { word: "Asleep", glyph: "sleep" },
};

/** An agent session's busy state (agents.ts) as a status. */
export function stateOf(busy: string): State {
  if (busy === "waiting") return "alert";
  if (busy === "think") return "think";
  return "work";
}

/** A badge: glyph + word, with optional text after the word ("Working · Claude"). */
export function badge(state: State, text?: string): HTMLElement {
  const node = document.createElement("span");
  node.className = "badge";
  node.dataset.state = state;
  const glyph = document.createElement("span");
  glyph.className = "glyph";
  glyph.append(icon(STATES[state].glyph, ""));
  const word = document.createElement("span");
  word.textContent = text ? `${STATES[state].word} · ${text}` : STATES[state].word;
  node.append(glyph, word);
  return node;
}
