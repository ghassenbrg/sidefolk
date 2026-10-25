import { sheet } from "./dialog";
import { explain, HELP, parse, type Command } from "../commands";
import { icon } from "../icons";
import { LOG, matchNotebook, today, type NoteEntry, type Notebook } from "../notes";
import type { Reminder } from "../reminders";
import { describeDue, describeRepeat, parseReminder } from "../when";
import { invoke } from "./api";
import type { App } from "./app";
import { agentShort, button, folder, h } from "./dom";
import { addReminder } from "./reminders";

// Quick add in the window: the companion's field and the same grammar (commands.ts), and the
// task finishes here, not on the desktop (docs/V1.md V1-Q1), so the window works with the
// companion hidden. Only what is about the companion itself (rename, hide) goes to it.

export function tellBar(app: App) {
  const input = h("input", {
    type: "text",
    class: "tell-input",
    placeholder: `Tell ${app.state.crew.main.name}…`,
    "aria-label": "Tell your companion",
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
    input.value = "";
    update();
    await finish(app, parse(text), text);
  });
  const examples = h("details", { class: "tell-examples" }, h("summary", { text: "Examples" }));
  const options = h("div", { class: "example-options" });
  for (const text of ["remind me tomorrow at 9 to check the results", "note for Ideas: try a quieter morning", "open Sidefolk", "help"]) options.append(button(text, () => { input.value = text; examples.open = false; input.focus(); update(); }));
  examples.append(options);
  return h("form", { class: "tell", onsubmit: (e: Event) => e.preventDefault() }, h("div", { class: "tell-row" }, h("span", { class: "tell-icon" }, icon("requests")), input, examples), preview);
}

/** What Enter does in the window, for each kind of Quick add. */
async function finish(app: App, command: Command, text: string) {
  switch (command.kind) {
    case "run":
      if (!app.state.settings.labs_commands) return app.toast("Commands are off. Turn them on in Settings → General → Labs.");
      return confirmRun(app, command.command, command.folder);
    case "start":
      if (!app.state.settings.labs_sessions) return app.toast("Starting sessions is off. Turn it on in Settings → General → Labs.");
      return confirmStart(app, command.agent, command.folder, command.full);
    case "remind":
      return remind(app, command.text);
    case "note":
      return note(app, command.notebook, command.text);
    case "notebook":
      try {
        const book = await invoke<Notebook>("create_notebook", { name: command.name });
        return app.go("notes", book.id);
      } catch (error) {
        return app.toast(String(error), undefined, true);
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
        (error) => app.toast(String(error), undefined, true),
      );
    case "chat":
      return app.toast(command.reply);
    case "unknown":
      return offerNote(app, command.text);
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
async function remind(app: App, text: string) {
  const parsed = parseReminder(text);
  // No time to go on: the Add reminder sheet, with the words filled in.
  if (!parsed) return addReminder(app, text);
  const save = async (due: Date) => {
    try {
      const added = await invoke<Reminder>("add_reminder", { text: parsed.what, due: due.getTime(), project: null, repeat: parsed.repeat ?? null });
      await app.refresh();
      app.toast(`Got it. ${describeDue(due)}: ${parsed.what}`, {
        label: "Undo",
        run: () => void invoke("remove_reminder", { id: added.id }).then(() => app.refresh()),
      });
    } catch (error) {
      app.toast(`Not saved: ${error}`, undefined, true);
    }
  };
  const alternative = parsed.alternative;
  const body = h(
    "div",
    {},
    h("p", { class: "note-text", text: parsed.what }),
    h("p", { class: "muted", text: alternative ? "Which one do you mean?" : `${describeDue(parsed.due)}${parsed.repeat ? `, then ${describeRepeat(parsed.repeat, parsed.due)}` : ""}` }),
  );
  const editor = sheet("New reminder", body);
  const choose = (due: Date) => () => {
    editor.close();
    void save(due);
  };
  body.append(
    h(
      "div",
      { class: "actions sheet-actions" },
      button("Change…", () => { editor.close(); addReminder(app, text); }),
      ...(alternative ? [button(describeDue(alternative), choose(alternative)), button(describeDue(parsed.due), choose(parsed.due), "primary")] : [button("Save", choose(parsed.due), "primary")]),
    ),
  );
}

/** "note: …" to the Log; "note for X: …" to X when the name is exact, else a choice (V1-L3). */
async function note(app: App, wanted: string | null, text: string) {
  const write = async (notebook: string, create = false) => {
    try {
      const [book, entry] = await invoke<[Notebook, NoteEntry]>("add_note", { notebook, text, date: today(), project: null, create });
      app.toast(`Noted in ${book.name}.`, { label: "Undo", run: () => void invoke("remove_note", { id: book.id, entry }) });
    } catch (error) {
      app.toast(String(error), undefined, true);
    }
  };
  if (!wanted) return write(LOG, true);
  const { exact, near } = matchNotebook(await invoke<Notebook[]>("list_notebooks").catch(() => [] as Notebook[]), wanted);
  if (exact) return write(exact.id);
  const body = h("div", {}, h("p", { class: "note-text", text }), h("p", { class: "muted", text: near.length ? "Which notebook?" : `There's no notebook called ${wanted}.` }));
  const editor = sheet(near.length === 1 ? `Add to ${near[0].name}?` : "Where should it go?", body);
  const pick = (notebook: string, create = false) => () => {
    editor.close();
    void write(notebook, create);
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
function offerNote(app: App, text: string) {
  const body = h("div", {}, h("p", { class: "note-text", text }), h("p", { class: "muted", text: "I don't have a rule for that. Save it as a note in your Log?" }));
  const editor = sheet("Save as a note?", body);
  body.append(
    h(
      "div",
      { class: "actions sheet-actions" },
      button("Not now", editor.close),
      button(`Save to ${LOG}`, () => {
        editor.close();
        void note(app, null, text);
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
async function confirmRun(app: App, command: string, wanted: string | null) {
  try {
    const folder = await invoke<{ path: string; label: string }>("resolve_folder", { folder: sessionFolder(app, wanted) ?? wanted });
    review(app, "Run in your terminal?", command, folder.path, "Run in terminal", () => invoke<string>("run_command", { command, cwd: folder.path }));
  } catch (error) {
    app.toast(String(error), undefined, true);
  }
}

async function confirmStart(app: App, agent: "claude" | "codex", wanted: string | null, full: boolean) {
  try {
    const folder = await invoke<{ path: string; label: string }>("resolve_folder", { folder: sessionFolder(app, wanted) ?? wanted });
    const name = agent === "codex" ? "Codex" : "Claude Code";
    review(app, `Start ${name}?`, `${name} · ${full ? (agent === "codex" ? "without approvals" : "auto mode") : "asks you first"}`, folder.path, `Start ${name}`, () => invoke<string>("start_session", { agent, cwd: folder.path, fullAccess: full }));
  } catch (error) {
    app.toast(String(error), undefined, true);
  }
}

function review(app: App, title: string, action: string, path: string, label: string, run: () => Promise<string>) {
  const error = h("p", { class: "field-error", role: "alert" });
  const content = h("div", {}, h("div", { class: "facts" }, h("span", { class: "fact-label", text: "Action" }), h("code", { text: action }), h("span", { class: "fact-label", text: "Folder" }), h("code", { text: path })), h("p", { class: "muted", text: "Opens in your configured terminal so you can see the output." }), error);
  const editor = sheet(title, content);
  const submit = button(label, async () => {
    submit.disabled = true;
    try { const done = await run(); editor.close(); app.toast(done); }
    catch (reason) { error.textContent = String(reason); submit.disabled = false; }
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
