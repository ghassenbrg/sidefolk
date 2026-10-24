import { invoke } from "./api";
import type { App } from "./app";
import { button, h } from "./dom";

type Status = { permission: "allowed" | "denied" | "notRequested" | "unavailable"; error: string | null };

/** Shared by setup and Settings; permission is requested only on the user's click. */
export function notificationSetting(app: App) {
  const message = h("p", { class: "muted", text: "Checking macOS notification permission…", "aria-live": "polite" });
  const allow = button("Allow notifications…", async () => {
    allow.disabled = true;
    try { show(await invoke<Status>("request_notifications")); }
    catch (e) { app.toast(String(e), undefined, true); allow.disabled = false; }
  });
  const show = (status: Status) => {
    message.textContent = status.error ? `Reminders are saved, but macOS couldn't schedule notifications: ${status.error}`
      : status.permission === "allowed" ? "macOS can deliver the next reminder even when Sidefolk is quit. Repeats advance when you mark them done."
      : status.permission === "denied" ? "To receive reminders while Sidefolk is quit, allow Sidefolk in System Settings → Notifications."
      : status.permission === "unavailable" ? "Notifications work in the installed macOS app. Keep Sidefolk running for companion reminders."
      : "Allow macOS notifications so reminders can arrive even when Sidefolk is quit.";
    allow.hidden = status.permission === "allowed" || status.permission === "unavailable";
    allow.disabled = status.permission === "denied";
  };
  void invoke<Status>("notification_status").then(show).catch((e) => { message.textContent = `Couldn't check notifications: ${e}`; });
  return h("div", { class: "setting" }, h("div", { class: "setting-text" }, h("strong", { text: "Reminder notifications" }), message), allow);
}
