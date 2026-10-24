/** One preference for every app surface. Without an override CSS follows macOS live. */
export type Theme = "system" | "light" | "dark";
const KEY = "sidefolk-theme";

export function themeOf(value: unknown): Theme {
  return value === "light" || value === "dark" ? value : "system";
}

export function applyTheme(value: unknown) {
  const theme = themeOf(value);
  if (theme === "system") delete document.documentElement.dataset.theme;
  else document.documentElement.dataset.theme = theme;
  try { localStorage.setItem(KEY, theme); } catch { /* Native settings remain the source of truth. */ }
}

// Cache avoids a flash while native settings load and shares the browser preview's choice.
try { applyTheme(localStorage.getItem(KEY)); } catch { applyTheme("system"); }
addEventListener("storage", (event) => {
  if (event.key === KEY) applyTheme(event.newValue);
});
