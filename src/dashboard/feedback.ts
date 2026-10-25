import { button, h } from "./dom";
import { problem } from "../voice";

export type UndoAction = { label: string; run: () => void | Promise<void> };
type Message = { text: string; error: boolean; action?: UndoAction };

/** Undo survives navigation and later messages. Actions leave the stack only after success or
 * an explicit dismissal; native text-editing Undo is handled by the field itself. */
export class Feedback {
  private readonly undo: Message[] = [];
  private message: Message | null = null;
  private busy = false;
  private timer = 0;
  constructor(private readonly root: HTMLElement) { root.tabIndex = -1; }

  show(text: string, action?: UndoAction, error = false) {
    clearTimeout(this.timer);
    const m = { text: error ? problem(text) : text, error, action };
    if (action) this.undo.push(m);
    this.message = m;
    this.draw();
    if (!action && !error) this.timer = window.setTimeout(() => { this.message = null; this.draw(); }, 4500);
  }

  async latest() {
    const m = this.undo.at(-1);
    if (!m?.action || this.busy) return;
    this.busy = true;
    this.draw();
    try {
      await m.action.run();
      const index = this.undo.indexOf(m);
      if (index >= 0) this.undo.splice(index, 1);
      this.message = null;
    } catch (error) {
      this.message = { text: problem(error), error: true };
    } finally {
      this.busy = false;
      this.draw();
    }
  }

  private draw() {
    const hadFocus = this.root.contains(document.activeElement);
    const m = this.message ?? this.undo.at(-1);
    this.root.replaceChildren();
    if (!m) {
      if (hadFocus) document.querySelector<HTMLElement>("main h1")?.focus();
      return;
    }
    this.root.classList.toggle("error", m.error);
    this.root.append(h("span", { text: m.text }));
    const last = this.undo.at(-1);
    if (last?.action) this.root.append(button(this.busy ? "Undoing…" : last.action.label, () => void this.latest(), "", { disabled: this.busy, title: last.text }));
    if (this.undo.length > 1) this.root.append(h("span", { class: "meta", text: `${this.undo.length} changes to undo` }));
    this.root.append(button("×", () => {
      if (m.action) this.undo.splice(this.undo.indexOf(m), 1);
      this.message = null;
      this.draw();
    }, "icon-button", { "aria-label": "Dismiss message", disabled: this.busy }));
    if (hadFocus) (this.root.querySelector<HTMLButtonElement>("button:not(:disabled)") ?? this.root).focus();
  }
}
