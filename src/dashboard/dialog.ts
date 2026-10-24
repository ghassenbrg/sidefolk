import { button, h } from "./dom";

/** Native dialog supplies focus trapping, Escape and an inert background in WebKit. */
export function sheet(title: string, content: HTMLElement, onClose?: () => void) {
  const previous = document.activeElement instanceof HTMLElement ? document.activeElement : null;
  const dialog = h("dialog", { class: "sheet", "aria-labelledby": "sheet-title" });
  const close = () => dialog.close();
  dialog.append(
    h("div", { class: "sheet-heading" }, h("h2", { id: "sheet-title", text: title }), button("×", close, "icon-button", { "aria-label": "Close" })),
    content,
  );
  dialog.addEventListener("close", () => {
    dialog.remove();
    onClose?.();
    if (previous?.isConnected) previous.focus();
    else document.querySelector<HTMLElement>("main h1")?.focus();
  }, { once: true });
  document.body.append(dialog);
  dialog.showModal();
  return { dialog, close };
}
