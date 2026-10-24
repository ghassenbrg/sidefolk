// A small element builder. Strings become text nodes, so agent and user text never becomes markup.

type Child = Node | string | null | undefined | false;
type Props = {
  class?: string;
  text?: string;
  onClick?: (event: MouseEvent) => void;
  [attribute: string]: unknown;
};

export function h<K extends keyof HTMLElementTagNameMap>(tag: K, props: Props = {}, ...children: Child[]): HTMLElementTagNameMap[K] {
  const node = document.createElement(tag);
  for (const [key, value] of Object.entries(props)) {
    if (value === undefined || value === null || value === false) continue;
    if (key === "class") node.className = String(value);
    else if (key === "text") node.textContent = String(value);
    else if (key === "onClick") node.addEventListener("click", value as (e: Event) => void);
    else if (key in node && typeof value !== "string") (node as unknown as Record<string, unknown>)[key] = value;
    else node.setAttribute(key, value === true ? "" : String(value));
  }
  for (const child of children) if (child) node.append(child);
  return node;
}

/** A button; `type="button"` so it never submits a form by accident. */
export function button(label: Child | Child[], onClick: (event: MouseEvent) => void, className = "", props: Props = {}) {
  const b = h("button", { type: "button", class: className, onClick, ...props });
  for (const part of Array.isArray(label) ? label : [label]) if (part) b.append(part);
  return b;
}

export const folder = (path: string) => path.split("/").filter(Boolean).pop() ?? path;

export const agentName = (source: string) => (source === "codex" ? "Codex" : source === "claude" ? "Claude Code" : "An AI tool");
/** Short form for running text ("Claude is editing…"). */
export const agentShort = (source: string) => (source === "codex" ? "Codex" : source === "claude" ? "Claude" : "An AI tool");

export function ago(at: number, now = Date.now()) {
  const m = Math.round((now - at) / 60_000);
  return m < 1 ? "just now" : m < 60 ? `${m} min ago` : m < 1440 ? `${Math.round(m / 60)} h ago` : `${Math.round(m / 1440)} d ago`;
}

/** The time zone shown next to reminder times, e.g. "Europe/Paris". */
export const timeZone = () => Intl.DateTimeFormat().resolvedOptions().timeZone;

/** The terminals Sidefolk can open things in (sessions.rs), by their setting key. */
export const TERMINAL_LABELS: Record<string, string> = { terminal: "Terminal", iterm: "iTerm", ghostty: "Ghostty", wezterm: "WezTerm", kitty: "kitty", alacritty: "Alacritty", sidefolk: "Inside Sidefolk" };
