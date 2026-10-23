// The speech bubble is the pet's only UI surface in Phase 0: short lines, permission
// questions with answer buttons, and a one-line prompt. Agent text is untrusted, so
// everything is inserted with textContent.

export type Ask = {
  id: string;
  source: "claude" | "codex";
  session: string;
  title: string;
  detail: string;
  cwd: string;
  canDefer: boolean;
};

export type Decision = "allow" | "deny" | "defer";
type Tone = "info" | "done" | "fail";

const folder = (path: string) => path.split("/").filter(Boolean).pop() ?? path;
const AGENT_NAMES = { claude: "Claude", codex: "Codex" } as const;

function el<K extends keyof HTMLElementTagNameMap>(tag: K, className: string, text?: string) {
  const node = document.createElement(tag);
  node.className = className;
  if (text !== undefined) node.textContent = text;
  return node;
}

export class Bubble {
  private asks: Ask[] = [];
  private line: { text: string; tone: Tone; until: number } | null = null;
  private prompting = false;
  private rendered = "";
  onDecision: (id: string, decision: Decision) => void = () => {};
  onPrompt: (text: string) => Promise<void> = async () => {};
  /** Called when the prompt opens or closes, so the window can take or give up focus. */
  onTyping: (typing: boolean) => void = () => {};

  constructor(private readonly root: HTMLElement) {}

  get typing() {
    return this.prompting;
  }

  get busy() {
    return this.asks.length > 0 || this.prompting;
  }

  ask(ask: Ask) {
    if (!this.asks.some((a) => a.id === ask.id)) this.asks.push(ask);
    this.render();
  }

  close(id: string) {
    this.asks = this.asks.filter((a) => a.id !== id);
    this.render();
  }

  say(text: string, seconds = 5, tone: Tone = "info") {
    this.line = { text, tone, until: performance.now() + seconds * 1000 };
    this.render();
  }

  prompt() {
    this.prompting = true;
    this.onTyping(true);
    this.render();
  }

  dismissPrompt() {
    if (this.prompting) this.endPrompt();
  }

  private endPrompt() {
    this.prompting = false;
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
    const key = this.prompting
      ? "prompt"
      : this.asks[0]
        ? `ask:${this.asks[0].id}:${this.asks.length}`
        : this.line
          ? `line:${this.line.tone}:${this.line.text}`
          : "";
    if (key === this.rendered) return;
    this.rendered = key;
    this.root.replaceChildren();
    this.root.className = "";
    this.root.hidden = key === "";
    if (this.asks[0] && !this.prompting) return this.renderAsk(this.asks[0]);
    if (this.prompting) return this.renderPrompt();
    if (this.line) {
      this.root.classList.add(`tone-${this.line.tone}`);
      this.root.append(el("p", "line", this.line.text));
    }
  }

  private renderAsk(ask: Ask) {
    this.root.classList.add("ask");
    const head = el("div", "who", `${AGENT_NAMES[ask.source]} · ${folder(ask.cwd)}`);
    if (this.asks.length > 1) head.append(el("span", "count", `+${this.asks.length - 1}`));
    const buttons = el("div", "actions");
    const button = (label: string, decision: Decision, primary = false) => {
      const b = el("button", primary ? "primary" : "", label);
      b.addEventListener("click", () => {
        this.close(ask.id);
        this.onDecision(ask.id, decision);
      });
      buttons.append(b);
    };
    button("Allow", "allow", true);
    button("Deny", "deny");
    if (ask.canDefer) button("In terminal", "defer");
    this.root.append(head, el("p", "title", ask.title), el("code", "detail", ask.detail), buttons);
  }

  private renderPrompt() {
    this.root.classList.add("prompt");
    const input = el("input", "");
    input.placeholder = "Ask Codex to do something…";
    input.maxLength = 2000;
    input.addEventListener("keydown", async (event) => {
      if (event.key === "Escape") return this.endPrompt();
      if (event.key !== "Enter" || !input.value.trim()) return;
      const text = input.value.trim();
      input.disabled = true;
      this.endPrompt();
      try {
        await this.onPrompt(text);
        this.say("On it. I'll tell you when Codex is done.", 4);
      } catch (error) {
        this.say(String(error), 6, "fail");
      }
    });
    input.addEventListener("blur", () => setTimeout(() => this.prompting && !input.disabled && this.endPrompt(), 150));
    this.root.append(el("div", "who", "Codex · playground"), input, el("p", "hint", "Enter to send · Esc to close"));
    requestAnimationFrame(() => input.focus());
  }
}
