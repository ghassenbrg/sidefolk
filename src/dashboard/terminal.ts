import { FitAddon } from "@xterm/addon-fit";
import { Terminal } from "@xterm/xterm";
import "@xterm/xterm/css/xterm.css";
import { icon } from "../icons";
import { invoke, listen } from "./api";
import type { App } from "./app";
import { button, h } from "./dom";
import { header } from "./ui";

// Sidefolk's own terminals (src-tauri/src/inside.rs), when "Inside Sidefolk" is the default
// terminal: sessions, commands and resumed sessions run here, one tab each. Each terminal's
// xterm lives outside the page, so redraws and switching tabs keep it as it is.

type Info = { id: number; title: string; cwd: string; alive: boolean };
type Shown = { term: Terminal; fit: FitAddon; host: HTMLElement; end: number; ready: boolean; queue: { data: string; end: number }[] };

const shown = new Map<number, Shown>();
let list: Info[] = [];
let wired = false;
/** When the list was last read: a terminal opened since then is read once, without looping. */
let read = 0;

function css(name: string) {
  return getComputedStyle(document.documentElement).getPropertyValue(name).trim();
}

function wire(app: App) {
  if (wired) return;
  wired = true;
  listen<{ id: number; data: string; end: number }>("pty-data", ({ id, data, end }) => {
    const s = shown.get(id);
    if (!s) return;
    if (!s.ready) s.queue.push({ data, end });
    else if (end > s.end) {
      s.term.write(data);
      s.end = end;
    }
  });
  listen<number>("pty-exit", (id) => {
    shown.get(id)?.term.write("\r\n\x1b[2m[This session ended. Close the tab when you're done.]\x1b[0m\r\n");
    void refresh(app);
  });
}

async function refresh(app: App) {
  read = Date.now();
  list = await invoke<Info[]>("pty_list").catch(() => []);
  // Forced: xterm keeps focus in its own text field, which a normal redraw waits out.
  app.redraw(true);
}

/** The terminal's xterm, made on first view and attached to what it showed so far. */
function shownFor(id: number): Shown {
  const existing = shown.get(id);
  if (existing) return existing;
  const host = h("div", { class: "term-host" });
  const term = new Terminal({
    fontFamily: css("--font-mono") || "Menlo, monospace",
    fontSize: 13,
    cursorBlink: true,
    scrollback: 5000,
    macOptionIsMeta: true,
    theme: { background: css("--surface"), foreground: css("--ink"), cursor: css("--ink"), selectionBackground: css("--mint-soft") },
  });
  const fit = new FitAddon();
  term.loadAddon(fit);
  const s: Shown = { term, fit, host, end: 0, ready: false, queue: [] };
  shown.set(id, s);
  term.onData((data) => void invoke("pty_write", { id, data }).catch(() => {}));
  term.onResize(({ cols, rows }) => void invoke("pty_resize", { id, cols, rows }).catch(() => {}));
  new ResizeObserver(() => host.isConnected && host.clientWidth && fit.fit()).observe(host);
  void invoke<{ data: string; end: number }>("pty_attach", { id }).then(
    (a) => {
      term.write(a.data);
      s.end = a.end;
      s.ready = true;
      for (const q of s.queue) if (q.end > s.end) {
        term.write(q.data);
        s.end = q.end;
      }
      s.queue = [];
    },
    () => term.write("This terminal is closed.\r\n"),
  );
  return s;
}

export function renderTerminal(app: App, arg: string) {
  wire(app);
  const id = Number(arg) || list[list.length - 1]?.id;
  if ((!list.length || (id && !list.some((t) => t.id === id))) && Date.now() - read > 1000) void refresh(app);
  const view = h("div", { class: "view terminals" });
  const tabs = h("div", { class: "term-tabs", role: "tablist", "aria-label": "Terminals" });
  for (const t of list) {
    const tab = button([icon("terminal"), h("span", { text: t.title })], () => app.go("terminal", String(t.id)), `term-tab${t.alive ? "" : " ended"}`, {
      role: "tab",
      "aria-selected": String(t.id === id),
      title: t.cwd,
    });
    tabs.append(tab);
  }
  tabs.append(button([icon("plus"), "New terminal"], () => void invoke("pty_open", {}).then(() => refresh(app)), "small"));
  view.append(h("div", { class: "page-heading" }, h("div", {}, ...header("Terminal", "Sessions and commands that run inside Sidefolk."))), tabs);

  const current = list.find((t) => t.id === id);
  if (!current) {
    view.append(h("p", { class: "muted", text: "No terminal yet. Choose “Inside Sidefolk” as the default terminal in Settings → AI tools, and sessions and commands open here." }));
    return view;
  }
  const s = shownFor(current.id);
  const close = button("Close", () =>
    app.toast(current.alive ? "Close this terminal? What runs in it stops." : "Close this terminal?", {
      label: "Close",
      run: () =>
        void invoke("pty_close", { id: current.id }).then(() => {
          s.term.dispose();
          shown.delete(current.id);
          void refresh(app).then(() => app.go("terminal"));
        }),
    }),
  "small");
  view.append(h("div", { class: "term-bar" }, h("span", { class: "meta", text: current.cwd }), close), s.host);
  // xterm measures its cell size once it's in the page.
  requestAnimationFrame(() => {
    if (!s.term.element) s.term.open(s.host);
    s.fit.fit();
    s.term.focus();
  });
  return view;
}
