// Global shortcuts are stored as Tauri accelerators ("CommandOrControl+Shift+Space"). People
// see them as macOS symbols and record them by pressing the keys.

const SYMBOLS: Record<string, string> = {
  CommandOrControl: "⌘",
  Command: "⌘",
  Super: "⌘",
  Control: "⌃",
  Shift: "⇧",
  Alt: "⌥",
  Option: "⌥",
};

/** "CommandOrControl+Shift+Space" → "⌘⇧Space". */
export function shortcutLabel(accelerator: string): string {
  const parts = accelerator.split("+");
  const key = parts.pop() ?? "";
  return parts.map((p) => SYMBOLS[p] ?? `${p}+`).join("") + (key.length === 1 ? key.toUpperCase() : key);
}

/**
 * A pressed key combination as an accelerator, or null while only modifiers are held or no
 * modifier is held (a global shortcut without one would steal ordinary typing).
 */
export function acceleratorFrom(e: Pick<KeyboardEvent, "metaKey" | "ctrlKey" | "altKey" | "shiftKey" | "code">): string | null {
  const key = keyName(e.code);
  if (!key || !(e.metaKey || e.ctrlKey || e.altKey)) return null;
  return [e.metaKey && "CommandOrControl", e.ctrlKey && "Control", e.altKey && "Alt", e.shiftKey && "Shift", key]
    .filter(Boolean)
    .join("+");
}

function keyName(code: string): string | null {
  if (/^Key[A-Z]$/.test(code)) return code.slice(3);
  if (/^Digit\d$/.test(code)) return code.slice(5);
  if (/^F\d{1,2}$/.test(code)) return code;
  const named: Record<string, string> = {
    Space: "Space",
    Enter: "Enter",
    Backquote: "`",
    Minus: "-",
    Equal: "=",
    Comma: ",",
    Period: ".",
    Slash: "/",
    Semicolon: ";",
    Quote: "'",
    BracketLeft: "[",
    BracketRight: "]",
    Backslash: "\\",
    ArrowUp: "Up",
    ArrowDown: "Down",
    ArrowLeft: "Left",
    ArrowRight: "Right",
  };
  return named[code] ?? null;
}
