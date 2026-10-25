import { area } from "./frame";
import { icon } from "./icons";

// A pet's speech bubble: short lines, cards with answer buttons (permission questions,
// offers, briefings, reminders) and a one-line prompt. Agent text is untrusted, so
// everything is inserted with textContent.
//
// Card anatomy (creative-design/DESIGN-SYSTEM.md, "Permission card"): who (pet · project) →
// context (tool · work session) → the question → the exact action → explicit choices.

export type Choice = {
  label: string;
  value: string;
  /** Mint button. Never focused or preselected: a choice is always an explicit click. */
  primary?: boolean;
  /** A text button under the others ("Answer in terminal"). */
  quiet?: boolean;
};

/** A labelled exact value (command, folder, file), shown whole in monospace. */
export type Fact = { label: string; value: string };

export type Card = {
  id: string;
  /** Who is asking, always as text ("Pip · sidefolk"), never by color alone. */
  who: string;
  /** Which tool and work session ("Codex · Work session 3f2a"). */
  context?: string;
  title: string;
  lines?: string[];
  facts?: Fact[];
  /** The facts are shown at full height, never in a scrolling box: what Allow answers is all on screen. */
  wholeFacts?: boolean;
  /** A short instruction above the choices ("Review the command before allowing it."). */
  note?: string;
  choices: Choice[];
  /** Choices as a full-width list (a pet's menu) instead of a row of buttons. */
  menu?: boolean;
  /** Requests jump the queue. Like every card they close with ×; the companion keeps the request. */
  urgent?: boolean;
  /** What the dashboard needs to show this card as a request (kind, source, session, …). */
  meta?: Record<string, string>;
  onChoose: (value: string) => void;
  /** Closed with × without choosing. */
  onClose?: () => void;
};

export type PromptOptions = {
  who: string;
  placeholder: string;
  value?: string;
  /** Says what Enter will do with the current text, so nothing (or no quota) is a surprise. */
  preview?: (text: string) => string;
  /** One-tap starters shown under an empty field. */
  suggestions?: string[];
  /** The work sessions, above the field ("api · needs you"); a tap opens one (docs/V1.md V1-D11). */
  sessions?: { label: string; state: string; open: () => void }[];
  /** Resolves to what the pet says afterwards. */
  submit: (text: string) => Promise<string | void>;
};

type Tone = "info" | "done" | "fail";

/** Card exit time; matches --motion-card in tokens.css. */
const EXIT_MS = 200;

function el<K extends keyof HTMLElementTagNameMap>(tag: K, className: string, text?: string) {
  const node = document.createElement(tag);
  node.className = className;
  if (text !== undefined) node.textContent = text;
  return node;
}

const reducedMotion = () =>
  document.body.classList.contains("reduce-motion") || matchMedia("(prefers-reduced-motion: reduce)").matches;

export class Bubble {
  private cards: Card[] = [];
  private line: { text: string; tone: Tone; until: number } | null = null;
  private prompting: PromptOptions | null = null;
  private rendered = "";
  private leaving = 0;
  /** Called when the prompt opens or closes, so the window can take or give up focus. */
  onTyping: (typing: boolean) => void = () => {};
  /** Called when a new line or card appears, so the pet can voice it. */
  onShow: (text: string, urgent: boolean) => void = () => {};

  constructor(readonly root: HTMLElement) {
    root.classList.add("bubble");
    root.hidden = true;
    // Lines are announced by screen readers; cards and the prompt are labelled dialogs.
    root.setAttribute("aria-live", "polite");
  }

  get typing() {
    return this.prompting !== null;
  }

  /** Something the user should answer or read is open. */
  get busy() {
    return this.cards.length > 0 || this.prompting !== null;
  }

  get asking() {
    return this.cards.some((c) => c.urgent);
  }

  /** Open cards, oldest first (for the dashboard). */
  get open(): readonly Card[] {
    return this.cards;
  }

  has(id: string) {
    return this.cards.some((c) => c.id === id);
  }

  show(card: Card) {
    if (this.has(card.id)) this.cards = this.cards.map((c) => (c.id === card.id ? card : c));
    else if (card.urgent) this.cards.splice(this.cards.filter((c) => c.urgent).length, 0, card);
    else this.cards.push(card);
    this.rendered = "";
    this.render();
  }

  close(id: string) {
    this.cards = this.cards.filter((c) => c.id !== id);
    this.render();
  }

  say(text: string, seconds = 5, tone: Tone = "info") {
    this.line = { text, tone, until: performance.now() + seconds * 1000 };
    this.render();
  }

  prompt(options: PromptOptions) {
    this.prompting = options;
    this.onTyping(true);
    this.rendered = "";
    this.render();
  }

  dismissPrompt() {
    if (this.prompting) this.endPrompt();
  }

  private endPrompt() {
    this.prompting = null;
    this.onTyping(false);
    this.render();
  }

  tick(now: number) {
    if (this.line && now > this.line.until) {
      this.line = null;
      this.render();
    }
  }

  /** Anchors the bubble's bottom-center above a point given in overlay CSS pixels. */
  place(x: number, bottom: number) {
    if (this.root.hidden) return;
    const width = this.root.offsetWidth;
    const left = Math.min(area.width - width - 8, Math.max(8, x - width / 2));
    this.root.style.transform = `translate(${Math.round(left)}px, ${Math.round(area.height - bottom - this.root.offsetHeight)}px)`;
  }

  contains(x: number, y: number) {
    if (this.root.hidden) return false;
    const r = this.root.getBoundingClientRect();
    return x >= r.left - 6 && x <= r.right + 6 && y >= r.top - 6 && y <= r.bottom + 6;
  }

  private render() {
    const card = this.cards[0];
    const key = this.prompting
      ? "prompt"
      : card
        ? `card:${card.id}:${this.cards.length}`
        : this.line
          ? `line:${this.line.tone}:${this.line.text}`
          : "";
    if (key === this.rendered) return;
    const wasShowing = this.rendered !== "";
    this.rendered = key;
    clearTimeout(this.leaving);
    // Nothing left to show: fade out, then hide (immediately with reduced motion).
    if (key === "") {
      if (!wasShowing || reducedMotion()) return this.clear();
      this.root.classList.add("leaving");
      this.leaving = window.setTimeout(() => this.clear(), EXIT_MS);
      return;
    }
    this.clear();
    this.root.hidden = false;
    if (!wasShowing) this.root.classList.add("entering");
    if (this.prompting) return this.renderPrompt(this.prompting);
    if (card) {
      this.onShow(card.title, !!card.urgent);
      return this.renderCard(card);
    }
    if (this.line) {
      this.onShow(this.line.text, false);
      this.root.classList.add(`tone-${this.line.tone}`);
      this.root.append(el("p", "line", this.line.text));
    }
  }

  private clear() {
    this.root.replaceChildren();
    this.root.className = "bubble";
    this.root.removeAttribute("role");
    this.root.removeAttribute("aria-label");
    this.root.hidden = this.rendered === "";
  }

  private renderCard(card: Card) {
    this.root.classList.add("ask");
    this.root.setAttribute("role", "dialog");
    this.root.setAttribute("aria-label", `${card.who}: ${card.title}`);
    if (card.urgent) this.root.classList.add("urgent");
    if (card.menu) this.root.classList.add("menu");
    const head = el("div", "who");
    head.append(el("span", "name", card.who));
    // More waiting behind this one: the count stays visible.
    if (this.cards.length > 1) head.append(el("span", "count", `${this.cards.length - 1} more`));
    // Every card closes. A request closed here stays answerable in the Sidefolk window.
    const close = el("button", "close");
    close.type = "button";
    close.title = card.urgent ? "Close (still in Sidefolk → Requests)" : "Close";
    close.setAttribute("aria-label", close.title);
    close.append(icon("failed", "icon"));
    close.addEventListener("click", () => {
      this.close(card.id);
      card.onClose?.();
    });
    head.append(close);
    this.root.append(head);
    if (card.context) this.root.append(el("p", "context", card.context));
    this.root.append(el("p", "title", card.title));
    for (const line of card.lines ?? []) this.root.append(el("p", "info", line));
    if (card.facts?.length) {
      const box = el("div", card.wholeFacts ? "facts whole" : "facts");
      for (const fact of card.facts) box.append(el("span", "label", fact.label), el("code", "value", fact.value));
      this.root.append(box);
    }
    if (card.note) this.root.append(el("p", "note", card.note));
    const main = card.choices.filter((c) => !c.quiet);
    const quiet = card.choices.filter((c) => c.quiet);
    const button = (choice: Choice, className: string) => {
      const b = el("button", className, choice.label);
      b.type = "button";
      b.addEventListener("click", () => {
        this.close(card.id);
        card.onChoose(choice.value);
      });
      return b;
    };
    if (main.length) {
      const buttons = el("div", card.menu ? "actions list" : "actions");
      for (const choice of main) buttons.append(button(choice, choice.primary ? "primary" : ""));
      this.root.append(buttons);
    }
    if (quiet.length) {
      const links = el("div", "actions quiet");
      for (const choice of quiet) links.append(button(choice, "quiet"));
      this.root.append(links);
    }
  }

  private renderPrompt(options: PromptOptions) {
    this.root.classList.add("prompt");
    this.root.setAttribute("role", "dialog");
    this.root.setAttribute("aria-label", options.who);
    const input = el("input", "");
    input.placeholder = options.placeholder;
    input.value = options.value ?? "";
    input.maxLength = 2000;
    input.setAttribute("aria-label", options.placeholder);
    const preview = el("p", "hint", "Enter to send · Esc to close");
    const chips = el("div", "chips");
    for (const suggestion of options.suggestions ?? []) {
      const chip = el("button", "chip", suggestion);
      chip.type = "button";
      // Keep the field focused, or its blur would close the prompt first.
      chip.addEventListener("mousedown", (e) => e.preventDefault());
      chip.addEventListener("click", () => {
        input.value = suggestion.replace(/…$/, "");
        input.dispatchEvent(new Event("input"));
        input.focus();
      });
      chips.append(chip);
    }
    const update = () => {
      const text = input.value.trim();
      chips.hidden = text.length > 0 || !options.suggestions?.length;
      preview.textContent = text && options.preview ? `↵ ${options.preview(text)}` : "Enter to send · Esc to close";
    };
    input.addEventListener("input", update);
    input.addEventListener("keydown", async (event) => {
      if (event.key === "Escape") return this.endPrompt();
      if (event.key !== "Enter" || !input.value.trim()) return;
      const text = input.value.trim();
      input.disabled = true;
      this.endPrompt();
      try {
        const reply = await options.submit(text);
        if (reply) this.say(reply, 6);
      } catch (error) {
        this.say(error instanceof Error ? error.message : String(error), 7, "fail");
      }
    });
    input.addEventListener("blur", () => setTimeout(() => this.prompting && !input.disabled && this.endPrompt(), 150));
    const head = el("div", "who");
    head.append(el("span", "name", options.who));
    const sessions = el("div", "sessions");
    sessions.setAttribute("aria-label", "Work sessions");
    for (const s of options.sessions ?? []) {
      const row = el("button", "session-row");
      row.type = "button";
      row.append(el("span", "session-label", s.label), el("span", "session-state", s.state));
      row.addEventListener("mousedown", (e) => e.preventDefault());
      row.addEventListener("click", () => {
        this.endPrompt();
        s.open();
      });
      sessions.append(row);
    }
    sessions.hidden = !options.sessions?.length;
    this.root.append(head, sessions, input, chips, preview);
    update();
    requestAnimationFrame(() => input.focus());
  }
}
