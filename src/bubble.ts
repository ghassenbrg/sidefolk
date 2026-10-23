// A pet's speech bubble: short lines, cards with answer buttons (permission questions,
// offers, briefings, reminders) and a one-line prompt. Agent text is untrusted, so
// everything is inserted with textContent.

export type Choice = { label: string; value: string; primary?: boolean };

/** A row of chips that keeps the card open when picked (the customizer). */
export type Row = {
  label: string;
  options: { label: string; value: string; swatch?: string }[];
  selected: string;
  onPick: (value: string) => void;
};

export type Card = {
  id: string;
  /** Header: who is asking, always as text ("Pip · sidefolk"), never by color alone. */
  who: string;
  title: string;
  detail?: string;
  lines?: string[];
  rows?: Row[];
  choices: Choice[];
  /** Choices as a full-width list (a pet's menu) instead of a row of buttons. */
  menu?: boolean;
  /** Permission questions jump the queue and cannot be dismissed with ×. */
  urgent?: boolean;
  onChoose: (value: string) => void;
};

export type PromptOptions = {
  who: string;
  placeholder: string;
  /** Says what Enter will do with the current text, so nothing (or no quota) is a surprise. */
  preview?: (text: string) => string;
  /** One-tap starters shown under an empty field. */
  suggestions?: string[];
  /** Resolves to what the pet says afterwards. */
  submit: (text: string) => Promise<string | void>;
};

type Tone = "info" | "done" | "fail";

function el<K extends keyof HTMLElementTagNameMap>(tag: K, className: string, text?: string) {
  const node = document.createElement(tag);
  node.className = className;
  if (text !== undefined) node.textContent = text;
  return node;
}

export class Bubble {
  private cards: Card[] = [];
  private line: { text: string; tone: Tone; until: number } | null = null;
  private prompting: PromptOptions | null = null;
  private rendered = "";
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

  /** Answers a card as if its button were clicked (from the dashboard). */
  choose(id: string, value: string): boolean {
    const card = this.cards.find((c) => c.id === id);
    if (!card || !card.choices.some((c) => c.value === value)) return false;
    this.close(id);
    card.onChoose(value);
    return true;
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
    const left = Math.min(innerWidth - width - 8, Math.max(8, x - width / 2));
    this.root.style.transform = `translate(${Math.round(left)}px, ${Math.round(innerHeight - bottom - this.root.offsetHeight)}px)`;
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
    this.rendered = key;
    this.root.replaceChildren();
    this.root.className = "bubble";
    this.root.removeAttribute("role");
    this.root.removeAttribute("aria-label");
    this.root.hidden = key === "";
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

  private renderCard(card: Card) {
    this.root.classList.add("ask");
    this.root.setAttribute("role", "dialog");
    this.root.setAttribute("aria-label", `${card.who}: ${card.title}`);
    if (card.urgent) this.root.classList.add("urgent");
    if (card.menu) this.root.classList.add("menu");
    const head = el("div", "who", card.who);
    if (this.cards.length > 1) head.append(el("span", "count", `+${this.cards.length - 1}`));
    if (!card.urgent) {
      const close = el("button", "close", "×");
      close.type = "button";
      close.title = "Close";
      close.setAttribute("aria-label", "Close");
      close.addEventListener("click", () => this.close(card.id));
      head.append(close);
    }
    this.root.append(head, el("p", "title", card.title));
    for (const line of card.lines ?? []) this.root.append(el("p", "info", line));
    if (card.detail) this.root.append(el("code", "detail", card.detail));
    for (const row of card.rows ?? []) {
      const chips = el("div", "chips");
      chips.setAttribute("role", "radiogroup");
      chips.setAttribute("aria-label", row.label);
      chips.append(el("span", "chips-label", row.label));
      for (const option of row.options) {
        const chip = el("button", `chip${option.value === row.selected ? " selected" : ""}`, option.swatch ? "" : option.label);
        chip.type = "button";
        chip.title = option.label;
        chip.setAttribute("role", "radio");
        chip.setAttribute("aria-checked", String(option.value === row.selected));
        if (option.swatch) {
          chip.classList.add("swatch");
          chip.setAttribute("aria-label", option.label);
          chip.style.background = option.swatch;
        }
        chip.addEventListener("click", () => {
          row.selected = option.value;
          row.onPick(option.value);
          this.rendered = "";
          this.render();
        });
        chips.append(chip);
      }
      this.root.append(chips);
    }
    const buttons = el("div", card.menu ? "actions list" : "actions");
    for (const choice of card.choices) {
      const b = el("button", choice.primary ? "primary" : "", choice.label);
      b.type = "button";
      b.addEventListener("click", () => {
        this.close(card.id);
        card.onChoose(choice.value);
      });
      buttons.append(b);
    }
    if (card.choices.length) this.root.append(buttons);
  }

  private renderPrompt(options: PromptOptions) {
    this.root.classList.add("prompt");
    this.root.setAttribute("role", "dialog");
    this.root.setAttribute("aria-label", options.who);
    const input = el("input", "");
    input.placeholder = options.placeholder;
    input.maxLength = 2000;
    input.setAttribute("aria-label", options.placeholder);
    const preview = el("p", "hint", "Enter to send · Esc to close");
    const chips = el("div", "chips suggestions");
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
    this.root.append(el("div", "who", options.who), input, chips, preview);
    update();
    requestAnimationFrame(() => input.focus());
  }
}
