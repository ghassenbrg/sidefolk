import { problem } from "../voice";
import { sheet } from "./dialog";
import { explain, HELP, parse, type Command } from "../commands";
import { icon } from "../icons";
import { LOG, matchNotebook, today, type NoteEntry, type Notebook } from "../notes";
import type { Reminder } from "../reminders";
import { describeDue, describeRepeat, parseReminder, parseEventReminder } from "../when";
import { invoke } from "./api";
import type { App } from "./app";
import { agentShort, button, folder, h, timeZone } from "./dom";
import { addReminder } from "./reminders";

// Quick add in the window: the companion's field and the same grammar (commands.ts), and the
// task finishes here, not on the desktop (docs/V1.md V1-Q1), so the window works with the
// companion hidden. Only what is about the companion itself (rename, hide) goes to it.

export function tellBar(app: App) {
  const input = h("input", {
    type: "text",
    class: "tell-input",
    placeholder: "Quick add…",
    "aria-label": "Quick add",
    autocomplete: "off",
    spellcheck: false,
  });
  const preview = h("p", { class: "tell-preview", "aria-live": "polite" });
  const update = () => {
    const text = input.value.trim();
    preview.textContent = text ? `↵ ${explain(text, context(app))}` : "";
  };
  input.addEventListener("input", update);
  input.addEventListener("keydown", async (event) => {
    if (event.key === "Escape") {
      input.value = "";
      update();
      return input.blur();
    }
    if (event.key !== "Enter" || !input.value.trim()) return;
    event.preventDefault();
    const text = input.value.trim();
    const command = parse(text);
    const clear = () => { if (input.value.trim() === text) { input.value = ""; update(); } };
    input.disabled = true;
    try {
      await finish(app, command, text, clear);
      if (!["remind", "note", "notebook", "unknown", "run", "start"].includes(command.kind)) clear();
    } catch (error) { app.toast(problem(error), undefined, true); }
    finally { input.disabled = false; }
  });
  const examples = h("details", { class: "tell-examples" }, h("summary", { text: "Examples" }));
  const options = h("div", { class: "example-options" });
  for (const text of ["remind me tomorrow at 9 to check the results", "note for Ideas: try a quieter morning", "open Sidefolk", "help"]) options.append(button(text, () => { input.value = text; examples.open = false; input.focus(); update(); }));
  examples.append(options);
  return h("form", { class: "tell", onsubmit: (e: Event) => e.preventDefault() }, h("div", { class: "tell-row" }, h("span", { class: "tell-icon" }, icon("requests")), input, examples), preview);
}

/** What Enter does in the window, for each kind of Quick add. */
async function finish(app: App, command: Command, text: string, onSaved: () => void) {
  switch (command.kind) {
    case "run":
      if (!app.state.settings.labs_commands) return app.toast("Commands are off. Turn them on in Settings → General → Labs.");
      return confirmRun(app, command.command, command.folder, onSaved);
    case "start":
      if (!app.state.settings.labs_sessions) return app.toast("Starting sessions is off. Turn it on in Settings → General → Labs.");
      return confirmStart(app, command.agent, command.folder, command.full, onSaved);
    case "remind":
      return remind(app, command.text, onSaved);
    case "note":
      return note(app, command.notebook, command.text, onSaved);
    case "notebook":
      try {
        const book = await invoke<Notebook>("create_notebook", { name: command.name });
        onSaved();
        return app.go("notes", book.id);
      } catch (error) {
        return app.toast(problem(error), undefined, true);
      }
    case "notes":
      return app.go("notes");
    case "reminders":
      return app.go("reminders");
    case "sidefolk":
      return app.go("today");
    case "help":
      return help();
    case "open": {
      const target = sessionTarget(app, command.project);
      if (!target) return app.toast(command.project ? `There's no work session in ${command.project} yet.` : "There's no work session to open yet.");
      return app.openSession(target, !target.live);
    }
    case "open-thing":
      return invoke<string>("open_target", { target: command.target, app: command.app }).then(
        (done) => app.toast(done),
        (error) => app.toast(problem(error), undefined, true),
      );
    case "chat":
      return app.toast(command.reply);
    case "unknown":
      return offerNote(app, command.text, onSaved);
    // About the companion itself: it answers.
    case "rename":
    case "hide": {
      const reply = await app.tell(text);
      if (reply) app.toast(reply);
      return void app.refresh();
    }
  }
}

/** A reminder as understood, saved from the window; both readings when a time is ambiguous. */
async function remind(app: App, text: string, onSaved: () => void) {
  if (parseEventReminder(text)) return addReminder(app, text, onSaved);
  const parsed = parseReminder(text);
  // No time to go on: the Add reminder sheet, with the words filled in.
  if (!parsed) return addReminder(app, text, onSaved);
  const save = async (due: Date) => {
    try {
      const added = await invoke<Reminder>("add_reminder", { text: parsed.what, due: due.getTime(), project: null, repeat: parsed.repeat ?? null });
      onSaved();
      await app.refresh();
      app.toast(`Got it. ${describeDue(due)}: ${parsed.what}`, {
        label: "Undo",
        run: async () => { await invoke("remove_reminder", { id: added.id }); await app.refresh(); },
      });
      return true;
    } catch (error) {
      app.toast(problem(error), undefined, true);
      return false;
    }
  };
  const alternative = parsed.alternative;
  const body = h(
    "div",
    {},
    h("p", { class: "note-text", text: parsed.what }),
    h("p", { class: "muted", text: alternative ? "Which one do you mean?" : `${describeDue(parsed.due)} (${timeZone()})${parsed.repeat ? `, then ${describeRepeat(parsed.repeat, parsed.due)}` : ""}` }),
  );
  const editor = sheet("New reminder", body);
  const choose = (due: Date) => async () => {
    for (const button of body.querySelectorAll("button")) button.disabled = true;
    if (await save(due)) editor.close();
    else for (const button of body.querySelectorAll("button")) button.disabled = false;
  };
  body.append(
    h(
      "div",
      { class: "actions sheet-actions" },
      button("Change…", () => { editor.close(); addReminder(app, text, onSaved); }),
      ...(alternative ? [button(describeDue(alternative), choose(alternative)), button(describeDue(parsed.due), choose(parsed.due), "primary")] : [button("Save", choose(parsed.due), "primary")]),
    ),
  );
}

/** "note: …" to the Log; "note for X: …" to X when the name is exact, else a choice (V1-L3). */
async function note(app: App, wanted: string | null, text: string, onSaved: () => void) {
  const write = async (notebook: string, create = false) => {
    try {
      const [book, entry] = await invoke<[Notebook, NoteEntry]>("add_note", { notebook, text, date: today(), project: null, create });
      onSaved();
      app.toast(`Noted in ${book.name}.`, { label: "Undo", run: async () => { await invoke("remove_note", { id: book.id, entry }); } });
      return true;
    } catch (error) {
      app.toast(problem(error), undefined, true);
      return false;
    }
  };
  if (!wanted) return write(LOG, true);
  const { exact, near } = matchNotebook(await invoke<Notebook[]>("list_notebooks"), wanted);
  if (exact) return write(exact.id);
  const body = h("div", {}, h("p", { class: "note-text", text }), h("p", { class: "muted", text: near.length ? "Which notebook?" : `There's no notebook called ${wanted}.` }));
  const editor = sheet(near.length === 1 ? `Add to ${near[0].name}?` : "Where should it go?", body);
  const pick = (notebook: string, create = false) => async () => {
    for (const button of body.querySelectorAll("button")) button.disabled = true;
    if (await write(notebook, create)) editor.close();
    else for (const button of body.querySelectorAll("button")) button.disabled = false;
  };
  body.append(
    h(
      "div",
      { class: "actions sheet-actions" },
      button(`Save to ${LOG}`, pick(LOG, true)),
      ...(near.length ? near.slice(0, 4).map((b, i) => button(b.name, pick(b.id), i === 0 ? "primary" : "")) : [button(`New notebook “${wanted}”`, pick(wanted, true), "primary")]),
    ),
  );
}

/** Text with no rule is never a dead end: it can become a note in the Log. */
function offerNote(app: App, text: string, onSaved: () => void) {
  const body = h("div", {}, h("p", { class: "note-text", text }), h("p", { class: "muted", text: "I don't have a rule for that. Save it as a note in your Log?" }));
  const editor = sheet("Save as a note?", body);
  body.append(
    h(
      "div",
      { class: "actions sheet-actions" },
      button("Discard", () => { onSaved(); editor.close(); }),
      button("Make it a reminder", () => { editor.close(); addReminder(app, text, onSaved); }),
      button(`Save to ${LOG}`, () => {
        editor.close();
        void note(app, null, text, onSaved);
      }, "primary"),
    ),
  );
}

function help() {
  sheet("Things I understand", h("ul", { class: "help-list" }, ...HELP.map((line) => h("li", { text: line }))));
}

/** The session "open session" goes to: a live one (in a project, if named), else the last that ended. */
function sessionTarget(app: App, project: string | null) {
  const want = project?.toLowerCase();
  const matches = (p: string) => !want || folder(p).toLowerCase() === want;
  const pet = app.state.status.pets[0];
  const live = pet?.sessions.find((s) => s.id && matches(s.project));
  if (live) return { source: live.source, session: live.id, cwd: live.cwd || live.project, live: true };
  const last = pet?.outcomes.find((o) => o.session && matches(o.project));
  return last ? { source: last.source, session: last.session!, cwd: last.cwd || last.project, live: false } : null;
}

/** Same rule as on the companion: the exact command and folder first, then it runs where you can watch. */
async function confirmRun(app: App, command: string, wanted: string | null, onSaved: () => void) {
  try {
    const folder = await invoke<{ path: string; label: string }>("resolve_folder", { folder: sessionFolder(app, wanted) ?? wanted });
    review(app, "Run in your terminal?", command, folder.path, "Run in terminal", () => invoke<string>("run_command", { command, cwd: folder.path }), onSaved);
  } catch (error) {
    app.toast(problem(error), undefined, true);
  }
}

async function confirmStart(app: App, agent: "claude" | "codex", wanted: string | null, full: boolean, onSaved: () => void) {
  if (agent !== "claude") return app.toast("Starting Codex sessions is not available yet.");
  try {
    const folder = await invoke<{ path: string; label: string }>("resolve_folder", { folder: sessionFolder(app, wanted) ?? wanted });
    const name = "Claude Code";
    review(app, `Start ${name}?`, `${name} · ${full ? "auto mode" : "asks you first"}`, folder.path, `Start ${name}`, () => invoke<string>("start_session", { agent, cwd: folder.path, fullAccess: full }), onSaved);
  } catch (error) {
    app.toast(problem(error), undefined, true);
  }
}

function review(app: App, title: string, action: string, path: string, label: string, run: () => Promise<string>, onSaved: () => void) {
  const error = h("p", { class: "field-error", role: "alert" });
  const content = h("div", {}, h("div", { class: "facts" }, h("span", { class: "fact-label", text: "Action" }), h("code", { text: action }), h("span", { class: "fact-label", text: "Folder" }), h("code", { text: path })), h("p", { class: "muted", text: "Opens in your configured terminal so you can see the output." }), error);
  const editor = sheet(title, content);
  const submit = button(label, async () => {
    submit.disabled = true;
    try { const done = await run(); onSaved(); editor.close(); app.toast(done); }
    catch (reason) { error.textContent = problem(reason); submit.disabled = false; }
  }, "primary");
  content.append(h("div", { class: "actions sheet-actions" }, button("Cancel", editor.close), submit));
  // The dialog initially focuses its close control, never the action.
}

/** "run … in api": the folder of the api work session when there is one. */
function sessionFolder(app: App, project: string | null) {
  if (!project) return null;
  const pet = app.state.status.pets[0];
  const live = pet?.sessions.find((s) => folder(s.project).toLowerCase() === project.toLowerCase());
  return live ? live.cwd || live.project : null;
}

function context(app: App) {
  return {
    name: app.state.crew.main.name,
    sessionFor(project: string | null) {
      const pet = app.state.status.pets[0];
      if (!pet) return null;
      const want = project?.toLowerCase();
      const matches = (p: string) => !want || folder(p).toLowerCase() === want;
      const live = pet.sessions.find((s) => s.id && matches(s.project));
      if (live) return { agent: agentShort(live.source), live: true };
      const last = pet.outcomes.find((o) => o.session && matches(o.project));
      return last ? { agent: agentShort(last.source), live: false } : null;
    },
  };
}
