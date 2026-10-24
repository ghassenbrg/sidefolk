// Full access per work session: "do it and come back when you're done" (docs/PLAN-V2.md, 6.3).
// Off by default for every session; turned on by the user for one session at a time. Even then,
// a few actions that are hard to undo still ask.

const KEY = "sidefolk.fullAccess";
const MAX = 50;

/** Commands that delete, rewrite history, gain root or pipe the internet into a shell. */
const RISKY = [
  /\brm\s+(-\w*\s+)*-\w*[rf]/i,
  /\bsudo\b/,
  /\bgit\s+push\b.*(--force\b|-f\b|--force-with-lease)/,
  /\bgit\s+(reset\s+--hard|clean\s+-\w*f|branch\s+-D)\b/,
  /\b(curl|wget)\b[^|]*\|\s*(sudo\s+)?(ba|z)?sh\b/,
  /\b(mkfs|diskutil\s+erase|dd\s+if=)/,
  /\bchmod\s+(-R\s+)?777\b/,
  /\bdrop\s+(table|database)\b/i,
  /\b(npm|pnpm|yarn)\s+publish\b/,
];

/** Why this still needs a yes with full access on, or null when it can go ahead. */
export function stillAsk(kind: string, detail: string): string | null {
  if (kind !== "command") return null;
  return RISKY.some((r) => r.test(detail)) ? "Full access is on, but this one is hard to undo, so I'm asking." : null;
}

export const sessionKey = (source: string, session: string) => `${source}:${session}`;

/** The sessions with full access, kept on this Mac across restarts (most recent last). */
export class FullAccess {
  private keys: string[];

  constructor(private readonly storage: Pick<Storage, "getItem" | "setItem"> | null = safeStorage()) {
    this.keys = this.read();
  }

  has(key: string) {
    return this.keys.includes(key);
  }

  list() {
    return [...this.keys];
  }

  set(key: string, on: boolean) {
    this.keys = this.keys.filter((k) => k !== key);
    if (on) this.keys.push(key);
    this.keys = this.keys.slice(-MAX);
    try {
      this.storage?.setItem(KEY, JSON.stringify(this.keys));
    } catch {
      // Kept for this run only.
    }
  }

  private read(): string[] {
    try {
      const value = JSON.parse(this.storage?.getItem(KEY) ?? "[]");
      return Array.isArray(value) ? value.filter((k) => typeof k === "string").slice(-MAX) : [];
    } catch {
      return [];
    }
  }
}

function safeStorage() {
  try {
    return globalThis.localStorage ?? null;
  } catch {
    return null;
  }
}
