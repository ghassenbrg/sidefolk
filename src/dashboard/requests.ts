import { icon } from "../icons";
import type { Waiting } from "./api";
import type { App } from "./app";
import { agentName, agentShort, button, folder, h } from "./dom";
import { attentionCard } from "./home";
import { back, empty, header, identity, petOf, sessionLabel } from "./ui";

// Requests: everything waiting for you, grouped by project, and the review of one request
// with its exact action. Choices are explicit clicks: nothing is preselected or focused, Back
// is only navigation, and "Sent" shows only after the pet confirms it passed the answer on.

/** A choice in flight or made; keeps the request so its result still reads in full. */
type Phase = { phase: "sending" | "sent" | "failed"; value: string; label: string; request: Waiting };
const phases = new Map<string, Phase>();

export function renderRequests(app: App) {
  const waiting = app.state.status.waiting;
  const view = h(
    "div",
    { class: "view" },
    ...header(
      "Requests",
      waiting.length === 0 ? "No requests are waiting for you." : waiting.length === 1 ? "One thing is waiting for your answer." : `${waiting.length} things are waiting for your answer.`,
    ),
  );
  if (!waiting.length) {
    view.append(empty("You're all caught up.", "When an AI tool asks for something, it shows up here and on its companion.", button("Back to Home", () => app.go("home"))));
    return view;
  }
  // Grouped by project, so two similar requests are never confused.
  const groups = new Map<string, Waiting[]>();
  for (const w of waiting) {
    const project = w.meta.project || petOf(app.state.status, w.pet)?.project || "";
    groups.set(project, [...(groups.get(project) ?? []), w]);
  }
  for (const [project, items] of groups) {
    view.append(h("h2", { class: "section-title", text: project ? folder(project) : "Everything else" }));
    for (const w of items) view.append(attentionCard(app, w));
  }
  return view;
}

const ACTIONS: Record<string, [string, string]> = {
  command: ["run this command", "Command"],
  file: ["change this file", "File"],
  web: ["open this page", "Page"],
  tool: ["use this tool", "Input"],
};

function copyable(label: string, value: string) {
  const copy = button(icon("copy"), async () => {
    await navigator.clipboard.writeText(value).catch(() => {});
    copy.setAttribute("aria-label", `${label} copied`);
    copy.title = "Copied";
  }, "icon-button", { "aria-label": `Copy ${label.toLowerCase()}`, title: "Copy" });
  return [h("span", { class: "fact-label", text: label }), h("div", { class: "fact" }, h("code", { text: value }), copy)];
}

export function renderReview(app: App, id: string) {
  const live = app.state.status.waiting.find((x) => x.id === id);
  const phase = phases.get(id);
  const w = live ?? phase?.request;
  const view = h("div", { class: "view review" }, back("Back to requests", () => app.go("requests")), ...header("Review request", "A clear choice, for the right project.", "Request details"));
  if (!w && !phase) {
    view.append(
      empty(
        "This request is no longer waiting.",
        "It was answered on the companion or in the tool's own window, or the tool stopped waiting. Nothing was sent from here.",
        button("Back to requests", () => app.go("requests")),
      ),
    );
    return view;
  }
  const meta = w?.meta ?? {};
  const pet = w ? petOf(app.state.status, w.pet) : null;
  const source = meta.source ?? "";
  const agent = agentShort(source);
  if (w) view.append(identity(pet?.look ?? null, w.petName, meta.project || pet?.project || null, `${agentName(source)} · ${sessionLabel(meta.session)}`));

  const card = h("section", { class: "card" });
  view.append(card);
  const result = h("div", { class: "result", role: "status", "aria-live": "polite" });

  if (meta.kind === "permission") {
    const [action, label] = ACTIONS[meta.action] ?? ACTIONS.tool;
    const where = folder(meta.project || meta.cwd || "");
    card.append(
      h("h2", { class: "request-title", text: meta.title }),
      h("p", { text: `${agent} is asking to ${action}${where ? ` in ${where}` : ""}.` }),
      h("div", { class: "facts" }, ...copyable(label, meta.command ?? ""), ...(meta.cwd ? copyable("Working folder", meta.cwd) : [])),
    );
    const expires = Number(meta.expires);
    const countdown = h("span");
    const tick = () => {
      const left = Math.max(0, Math.round((expires - Date.now()) / 1000));
      countdown.textContent = left > 90 ? `${Math.round(left / 60)} minutes` : `${left} seconds`;
    };
    if (expires) {
      tick();
      const timer = setInterval(tick, 1000);
      app.onLeave(() => clearInterval(timer));
    }
    const details = h(
      "details",
      {},
      h("summary", { text: "Technical details" }),
      h(
        "dl",
        { class: "tech" },
        h("dt", { text: "Tool" }),
        h("dd", { text: agentName(source) }),
        h("dt", { text: "Work session" }),
        h("dd", { text: meta.session || "unknown" }),
        h("dt", { text: "Request" }),
        h("dd", { text: `${id} · ${meta.action === "command" ? "command execution" : meta.action}` }),
        ...(expires ? [h("dt", { text: "Waits for" }), h("dd", {}, countdown, " more, then the tool asks in its own window")] : []),
      ),
      meta.session
        ? button([icon("open"), "Open this work session"], () => void app.openSession({ source, session: meta.session, cwd: meta.cwd }), "", {
            title: "Bring the session's window forward without answering",
          })
        : null,
    );
    card.append(details, h("p", { class: "note", text: meta.action === "command" ? "Review the command before allowing it." : "Check it before allowing it." }));
  } else {
    card.append(h("h2", { class: "request-title", text: meta.question || w?.title || "" }));
    for (const line of w?.lines ?? []) card.append(h("p", { text: line }));
  }

  if (phase) {
    const sent = phase.phase === "sent";
    result.append(
      h("strong", {
        text:
          phase.phase === "sending"
            ? "Sending your answer…"
            : sent
              ? `${phase.label}. Sent to ${agent || "the tool"}.`
              : "Connection lost. Your answer hasn't been sent.",
      }),
    );
    if (phase.phase === "failed" && live)
      result.append(
        button("Retry", () => {
          phases.delete(id);
          void choose(app, live, phase.value, phase.label);
        }),
      );
    if (sent) result.append(button("Back to requests", () => app.go("requests")));
    result.classList.toggle("error", phase.phase === "failed");
    card.append(result);
    if (phase.phase !== "failed") return view;
  }
  if (!live) return view;

  const choices =
    meta.kind === "permission"
      ? [
          { label: "Decline", value: "deny", primary: false, quiet: false },
          { label: "Allow once", value: "allow", primary: true, quiet: false },
          ...(meta.canDefer === "true" ? [{ label: `Answer in ${agentName(source)}'s window`, value: "defer", primary: false, quiet: true }] : []),
        ]
      : live.choices.filter((c) => c.value !== "\u0000reply");
  const row = h("div", { class: "actions equal" });
  const quiet = h("div", { class: "actions" });
  for (const c of choices) (c.quiet ? quiet : row).append(button(c.label, () => void choose(app, live, c.value, c.label), c.quiet ? "quiet" : c.primary ? "primary" : ""));
  card.append(row);
  if (quiet.children.length) card.append(quiet);

  // A question without fixed choices takes a written answer.
  if (meta.kind === "question" && meta.free === "true") {
    const field = h("textarea", { id: "reply", rows: 3, maxlength: 2000 });
    const form = h(
      "form",
      { class: "field" },
      h("label", { for: "reply", text: "Your answer" }),
      field,
      h("div", { class: "actions" }, h("button", { type: "submit", class: "primary", text: "Send answer" })),
    );
    form.addEventListener("submit", (event) => {
      event.preventDefault();
      if (field.value.trim()) void choose(app, live, field.value.trim(), "Answered");
    });
    card.append(form);
  }
  return view;
}

async function choose(app: App, request: Waiting, value: string, label: string) {
  const id = request.id;
  // Both choices lock while one is sent; a second click can't answer twice.
  phases.set(id, { phase: "sending", value, label, request });
  app.hold = true;
  app.redraw(true);
  const answer = await app.answer(id, value);
  app.hold = false;
  if (answer === "gone") phases.delete(id);
  else {
    const done = value === "allow" ? "Allowed once" : value === "deny" ? "Declined" : value === "defer" ? "Left to the tool's own window" : label;
    phases.set(id, { phase: answer, value, label: done, request });
  }
  // A sent answer stays readable for a while, then the request is history.
  if (answer === "sent") setTimeout(() => phases.delete(id), 120_000);
  await app.refresh();
  app.redraw(true);
}
