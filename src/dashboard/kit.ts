import { icon } from "../icons";
import { button, h } from "./dom";

export type MenuAction = { label: string; run: () => void; destructive?: boolean };

/** A real popup: Tab stays native, arrows move through its actions, Escape returns to the
 * opener. Popovers close when clicked away and sit above scroll containers. */
export function overflow(name: string, actions: MenuAction[]) {
  const menu = h("div", { class: "overflow-menu", popover: "auto", role: "menu", "aria-label": name });
  const trigger = button(icon("more"), () => menu.togglePopover(), "icon-button", { "aria-label": `More actions for ${name}`, "aria-haspopup": "menu", "aria-expanded": "false" });
  const items = actions.map((a) => button(a.label, () => { menu.hidePopover(); a.run(); }, a.destructive ? "danger" : "", { role: "menuitem", "aria-label": `${a.label} ${name}` }));
  menu.append(...items);
  menu.addEventListener("toggle", (event) => {
    const open = (event as ToggleEvent).newState === "open";
    trigger.setAttribute("aria-expanded", String(open));
    if (open) {
      const rect = trigger.getBoundingClientRect();
      menu.style.top = `${Math.max(8, Math.min(rect.bottom + 4, innerHeight - menu.offsetHeight - 8))}px`;
      menu.style.left = `${Math.max(8, Math.min(rect.right - menu.offsetWidth, innerWidth - menu.offsetWidth - 8))}px`;
      items[0]?.focus();
    } else if (trigger.isConnected && (document.activeElement === document.body || menu.contains(document.activeElement))) trigger.focus();
  });
  menu.addEventListener("keydown", (event) => {
    if (event.key === "Escape") { event.preventDefault(); menu.hidePopover(); trigger.focus(); }
    const at = items.indexOf(document.activeElement as HTMLButtonElement);
    if (["ArrowDown", "ArrowUp", "Home", "End"].includes(event.key)) {
      event.preventDefault();
      const next = event.key === "Home" ? 0 : event.key === "End" ? items.length - 1 : (at + (event.key === "ArrowDown" ? 1 : -1) + items.length) % items.length;
      items[next]?.focus();
    }
  });
  return h("span", { class: "overflow" }, trigger, menu);
}

/** A failure is different from an empty list: show why it couldn't load and how to retry. */
export function dataState(title: string, detail: string, retry?: () => void) {
  const heading = h("h2", { text: title, tabindex: -1 });
  const view = h("section", { class: "card data-state", role: retry ? "alert" : "status" }, heading, h("p", { class: "muted", text: detail }), retry ? button("Retry", retry) : null);
  requestAnimationFrame(() => { if (view.isConnected && document.activeElement === document.body) heading.focus(); });
  return view;
}
