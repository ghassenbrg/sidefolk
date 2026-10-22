import {
  app,
  BrowserWindow,
  ipcMain,
  Menu,
  Tray,
  nativeImage,
  Notification,
  dialog,
  powerMonitor,
  screen,
} from "electron";
import { join, dirname, basename } from "node:path";
import { fileURLToPath } from "node:url";
import { mkdirSync, readFileSync, realpathSync } from "node:fs";
import { randomUUID } from "node:crypto";
import { spawn, type ChildProcessWithoutNullStreams } from "node:child_process";
import { z } from "zod";
import { Store } from "./store.js";
import { interpret } from "../shared/intents.js";
import {
  settingsSchema,
  skillSchema,
  type Snapshot,
  type Project,
  type Job,
  type AgentRun,
  type AgentSession,
} from "../shared/types.js";
import { tickReminders } from "./reminders.js";
import {
  agentEnv,
  executable,
  launchAgent,
  terminate,
  extractMemories,
  agentPrompt,
} from "./agents.js";

const root = join(dirname(fileURLToPath(import.meta.url)), "../..");
if (process.env.SIDEFOLK_DATA_DIR)
  app.setPath("userData", process.env.SIDEFOLK_DATA_DIR);
app.setName("Sidefolk");
let home: BrowserWindow | null = null,
  pet: BrowserWindow | null = null,
  tray: Tray;
let store: Store,
  project: Project | null = null,
  job: Job | null = null,
  agent: AgentRun | null = null;
let jobChild: ChildProcessWithoutNullStreams | null = null,
  agentChild: ChildProcessWithoutNullStreams | null = null;
let quitting = false,
  stoppedAgent = false;
const snapshot = (): Snapshot => ({
  ...store.state,
  project,
  job,
  agent,
  storageWarning: store.warning,
});
function publish(persist = true) {
  if (persist) store.save();
  for (const window of [home, pet])
    if (window && !window.isDestroyed())
      window.webContents.send("state:changed", snapshot());
}
function loadWindow(window: BrowserWindow, mode = "") {
  window.webContents.setWindowOpenHandler(() => ({ action: "deny" }));
  window.webContents.on("will-navigate", (e) => e.preventDefault());
  if (process.env.SIDEFOLK_DEV_URL) {
    const url = new URL(process.env.SIDEFOLK_DEV_URL);
    if (url.origin !== "http://127.0.0.1:5173")
      throw new Error("Untrusted development URL");
    url.hash = mode;
    void window.loadURL(url.href);
  } else void window.loadFile(join(root, "dist/index.html"), { hash: mode });
}
function showHome() {
  if (home && !home.isDestroyed()) {
    home.show();
    home.focus();
    return;
  }
  home = new BrowserWindow({
    title: "Sidefolk",
    width: 1280,
    height: 850,
    minWidth: 980,
    minHeight: 700,
    backgroundColor: "#f7f8f5",
    titleBarStyle: "hiddenInset",
    trafficLightPosition: { x: 20, y: 20 },
    webPreferences: {
      preload: join(root, "dist-electron/electron/preload.cjs"),
      contextIsolation: true,
      nodeIntegration: false,
      sandbox: true,
    },
  });
  home.webContents.session.setPermissionRequestHandler(
    (_wc, _permission, callback) => callback(false),
  );
  home.on("close", (event) => {
    if (!quitting) {
      event.preventDefault();
      home?.hide();
    }
  });
  loadWindow(home);
}
function updatePet() {
  if (!store.state.settings.petVisible) {
    pet?.destroy();
    pet = null;
    return;
  }
  if (pet && !pet.isDestroyed()) return;
  const { x, y, width, height } = screen.getPrimaryDisplay().workArea;
  pet = new BrowserWindow({
    x: x + width - 310,
    y: y + height - 350,
    width: 290,
    height: 330,
    transparent: true,
    frame: false,
    resizable: false,
    hasShadow: false,
    alwaysOnTop: true,
    skipTaskbar: true,
    backgroundColor: "#00000000",
    webPreferences: {
      preload: join(root, "dist-electron/electron/preload.cjs"),
      contextIsolation: true,
      nodeIntegration: false,
      sandbox: true,
      backgroundThrottling: true,
    },
  });
  pet.setVisibleOnAllWorkspaces(true, { visibleOnFullScreen: true });
  pet.setIgnoreMouseEvents(true, { forward: true });
  loadWindow(pet, "pet");
}
function newSession(workspace = project?.path ?? ""): AgentSession {
  if (agent)
    throw new Error(
      "Stop or finish the current agent turn before changing sessions.",
    );
  const session: AgentSession = {
    id: randomUUID(),
    title: "A new adventure",
    provider: store.state.settings.provider,
    workspace,
    remoteId: null,
    messages: [],
    contextHash: "",
    toolsEnabled: !!project && workspace === project.path,
    reportedUsage: { input: 0, cached: 0, output: 0 },
    createdAt: Date.now(),
  };
  store.state.sessions.unshift(session);
  store.state.activeSessionId = session.id;
  store.state.pendingReminder = null;
  return session;
}
function currentSession() {
  return store.state.sessions.find(
    (s) => s.id === store.state.activeSessionId,
  )!;
}
function tick() {
  const result = tickReminders(
    store.state.items,
    Date.now(),
    store.state.settings.focus,
  );
  for (const item of result.notify) {
    if (Notification.isSupported()) {
      const notification = new Notification({
        title: `${store.state.settings.petName} has a little reminder`,
        body: item.title,
      });
      notification.on("click", showHome);
      notification.show();
    }
  }
  if (result.changed) publish();
}
async function sendChat(text: string) {
  if (agent)
    throw new Error(
      "Your companion is working. Stop the current turn or wait for it to finish.",
    );
  let session = currentSession();
  if (
    session.provider !== store.state.settings.provider ||
    (project && session.workspace !== project.path)
  )
    session = newSession();
  store.addMessage("user", text);
  if (session.messages.filter((m) => m.role === "user").length === 1)
    session.title = text.slice(0, 44);
  const intent = interpret(
    text,
    new Date(),
    store.state.pendingReminder?.title,
  );
  if (intent.type === "todo" || intent.type === "reminder") {
    store.state.items.unshift({
      id: randomUUID(),
      title: intent.title,
      kind: intent.type,
      createdAt: Date.now(),
      dueAt: intent.type === "reminder" ? intent.dueAt : null,
      status: "pending",
      notifiedAt: null,
    });
    store.state.pendingReminder = null;
    store.addMessage(
      "assistant",
      intent.type === "todo"
        ? `On your list: ${intent.title}. One less thing to keep in your head.`
        : `I’ll remind you ${new Date(intent.dueAt).toLocaleString([], { dateStyle: "medium", timeStyle: "short" })}: ${intent.title}.`,
    );
  } else if (intent.type === "clarify") {
    store.state.pendingReminder = { title: intent.title };
    store.addMessage(
      "assistant",
      `Got it: ${intent.title}. When should I remind you? Try “in an hour,” “tomorrow at 9,” or “next Friday at 3pm.”`,
    );
  } else if (intent.type === "memory") {
    store.state.memories.unshift({
      id: randomUUID(),
      text: intent.text.slice(0, 1200),
      source: "you",
      createdAt: Date.now(),
    });
    store.addMessage(
      "assistant",
      `I’ll remember: ${intent.text}. You can edit what I know in Memory.`,
    );
  } else if (intent.type === "list") {
    const items = store.state.items.filter((i) => i.status !== "done");
    store.addMessage(
      "assistant",
      items.length
        ? `Here’s what’s waiting:\n${items.map((i) => `• ${i.title}${i.dueAt ? ` — ${new Date(i.dueAt).toLocaleString()}` : ""}`).join("\n")}`
        : "Nothing unfinished. A suspiciously peaceful moment.",
    );
  } else if (intent.type === "project") {
    store.addMessage(
      "assistant",
      project
        ? `${project.name} is connected. Open Workshop to choose and run a project script, or ask me to explore the code.`
        : "Open Workshop and choose a folder. I can explore it with your agent, and run its npm scripts.",
    );
  } else if (
    /^(?:what (?:do you (?:know|remember)|have you learned)|show (?:my |your )?memory)/i.test(
      text,
    )
  ) {
    const notes = store.state.memories.filter((m) => m.source === "you");
    store.addMessage(
      "assistant",
      notes.length
        ? notes.map((m) => `• ${m.text}`).join("\n")
        : "Teach me something with “remember that I prefer…” and I’ll keep it across sessions.",
    );
  } else if (store.state.settings.provider === "local") {
    store.addMessage(
      "assistant",
      "I’m in local mode: reminders, todos, and memory work without tokens. Choose Codex or Claude in Settings for a conversation or agent work.",
    );
  } else {
    if (!session.workspace) {
      session.workspace = join(app.getPath("userData"), "workspace");
      mkdirSync(session.workspace, { recursive: true });
    }
    const provider = store.state.settings.provider;
    agent = {
      provider,
      status: "thinking",
      activity: "Connecting to your agent…",
      text: "",
      startedAt: Date.now(),
    };
    const contextHash = agentPrompt(store.state, session, text).contextHash;
    stoppedAgent = false;
    publish();
    try {
      agentChild = launchAgent(
        provider,
        session,
        store.state,
        text,
        (event) => {
          if (!agent) return;
          if (event.sessionId) {
            session.remoteId = event.sessionId;
            store.save();
          }
          if (event.text) agent.text = event.text;
          if (event.activity) {
            agent.activity = event.activity.slice(0, 220);
            agent.status = "working";
          }
          if (event.usage) {
            store.state.usage.turns++;
            // Codex reports cumulative native-session usage even on resume.
            const previous =
              session.provider === "codex"
                ? session.reportedUsage
                : { input: 0, cached: 0, output: 0 };
            store.state.usage.input += Math.max(
              0,
              event.usage.input - previous.input,
            );
            store.state.usage.cached += Math.max(
              0,
              event.usage.cached - previous.cached,
            );
            store.state.usage.output += Math.max(
              0,
              event.usage.output - previous.output,
            );
            session.reportedUsage = event.usage;
          }
          publish(false);
        },
        (error) => {
          const result = extractMemories(agent?.text ?? "");
          if (result.text) store.addMessage("assistant", result.text);
          if (error || stoppedAgent)
            store.addMessage(
              "assistant",
              stoppedAgent
                ? "Stopped. We can pick this up again whenever you’re ready."
                : `The agent hit a snag: ${error}`,
            );
          if (!error && !stoppedAgent) {
            session.contextHash = contextHash;
            if (!result.text)
              store.addMessage(
                "assistant",
                "The agent finished without a text response. Try a more specific request.",
              );
            for (const text of result.memories)
              if (
                !store.state.memories.some(
                  (m) => m.text.toLowerCase() === text.toLowerCase(),
                )
              )
                store.state.memories.unshift({
                  id: randomUUID(),
                  text,
                  source: "suggested",
                  createdAt: Date.now(),
                });
          }
          agent = null;
          agentChild = null;
          publish();
        },
      );
    } catch (error) {
      agent = null;
      store.addMessage("assistant", (error as Error).message);
    }
  }
  publish();
}

// Only these two app-owned renderer windows can call privileged operations.
function handle(channel: string, fn: (...args: any[]) => unknown) {
  ipcMain.handle(channel, (event, ...args) => {
    if (
      ![home?.webContents.id, pet?.webContents.id].includes(event.sender.id) ||
      event.senderFrame !== event.sender.mainFrame
    )
      throw new Error("Untrusted renderer");
    return fn(...args);
  });
}
function setupIPC() {
  handle("state:get", snapshot);
  handle("chat:send", (value) =>
    sendChat(z.string().trim().min(1).max(12_000).parse(value)),
  );
  handle("settings:set", (value) => {
    if (agent)
      throw new Error(
        "Finish or stop the current turn before changing agent settings.",
      );
    store.state.settings = settingsSchema.parse(value);
    updatePet();
    publish();
    tick();
  });
  handle("window:home", showHome);
  handle("pet:interactive", (value) => {
    pet?.setIgnoreMouseEvents(!z.boolean().parse(value), { forward: true });
  });
  handle("item:action", (id, action) => {
    z.string().parse(id);
    z.enum(["done", "reopen", "snooze", "delete"]).parse(action);
    const item = store.state.items.find((i) => i.id === id);
    if (!item) throw new Error("Task not found");
    if (action === "delete")
      store.state.items = store.state.items.filter((i) => i.id !== id);
    else if (action === "done") item.status = "done";
    else if (action === "snooze") {
      if (item.kind !== "reminder")
        throw new Error("Only reminders can be snoozed");
      item.dueAt = Date.now() + 30 * 60_000;
      item.status = "pending";
      item.notifiedAt = null;
    } else {
      item.status = "pending";
      item.notifiedAt = null;
    }
    publish();
    tick();
  });
  handle("memory:add", (value, id) => {
    const text = z.string().trim().min(1).max(1200).parse(value);
    if (id !== undefined) {
      z.string().parse(id);
      const note = store.state.memories.find((m) => m.id === id);
      if (!note) throw new Error("Memory not found.");
      note.text = text;
      note.source = "you";
    } else
      store.state.memories.unshift({
        id: randomUUID(),
        text,
        source: "you",
        createdAt: Date.now(),
      });
    publish();
  });
  handle("memory:action", (id, action) => {
    z.string().parse(id);
    z.enum(["accept", "delete"]).parse(action);
    if (action === "delete")
      store.state.memories = store.state.memories.filter((m) => m.id !== id);
    else {
      const memory = store.state.memories.find((m) => m.id === id);
      if (memory) memory.source = "you";
    }
    publish();
  });
  handle("skill:save", (value) => {
    const skill = skillSchema.parse(value);
    const next = [
      ...store.state.skills.filter((s) => s.id !== skill.id),
      skill,
    ];
    if (
      next
        .filter((s) => s.enabled)
        .map((s) => `## ${s.name}\n${s.instructions}`)
        .join("\n\n").length > 3000
    )
      throw new Error(
        "Enabled skills have a shared 3,000 character budget. Shorten a skill or disable another to keep context light.",
      );
    const index = store.state.skills.findIndex((s) => s.id === skill.id);
    if (index < 0) store.state.skills.push(skill);
    else store.state.skills[index] = skill;
    publish();
  });
  handle("skill:delete", (id) => {
    z.string().parse(id);
    store.state.skills = store.state.skills.filter((s) => s.id !== id);
    publish();
  });
  handle("session:new", () => {
    newSession();
    publish();
  });
  handle("session:switch", (id) => {
    if (agent) throw new Error("Finish or stop the current turn first.");
    const session = store.state.sessions.find(
      (s) => s.id === z.string().parse(id),
    );
    if (!session) throw new Error("Session not found");
    store.state.activeSessionId = session.id;
    store.state.settings.provider = session.provider;
    store.state.pendingReminder = null;
    // Restoring a conversation does not grant fresh project execution permissions.
    if (project?.path !== session.workspace) project = null;
    publish();
  });
  handle("agents:check", () =>
    Object.fromEntries(
      ["codex", "claude"].map((name) => {
        try {
          return [name, executable(name)];
        } catch {
          return [name, "Not installed"];
        }
      }),
    ),
  );
  handle("agents:stop", () => {
    if (agentChild) {
      stoppedAgent = true;
      terminate(agentChild);
    }
  });
  handle("project:choose", async () => {
    if (agent || jobChild)
      throw new Error("Finish the running work before switching folders.");
    const selected = await dialog.showOpenDialog(home!, {
      properties: ["openDirectory"],
      title: "Choose a project for your companion",
    });
    if (selected.canceled || !selected.filePaths[0]) return;
    const path = realpathSync(selected.filePaths[0]);
    let name = basename(path),
      scripts: Record<string, string> = {};
    try {
      const pkg = JSON.parse(readFileSync(join(path, "package.json"), "utf8"));
      name = typeof pkg.name === "string" ? pkg.name : name;
      scripts = z.record(z.string(), z.string()).parse(pkg.scripts ?? {});
    } catch {
      /* non-Node projects are still valid agent workspaces */
    }
    project = { path, name, scripts };
    newSession(path);
    publish();
  });
  handle("project:run", (name) => {
    z.string()
      .regex(/^[a-zA-Z0-9][\w:.-]{0,79}$/)
      .parse(name);
    if (!project || !Object.hasOwn(project.scripts, name))
      throw new Error("Choose a script from the connected project.");
    if (jobChild)
      throw new Error("A project script is already running. Stop it first.");
    const pkg = JSON.parse(
      readFileSync(join(project.path, "package.json"), "utf8"),
    );
    if (pkg.scripts?.[name] !== project.scripts[name])
      throw new Error(
        "This script changed. Reconnect the folder to review it.",
      );
    job = {
      id: randomUUID(),
      script: name,
      status: "running",
      output: `$ npm run ${name}\n${project.scripts[name]}\n\n`,
      startedAt: Date.now(),
    };
    const child = spawn(executable("npm"), ["run", name], {
      cwd: project.path,
      shell: false,
      env: agentEnv(),
      detached: process.platform !== "win32",
      stdio: "pipe",
    });
    jobChild = child;
    let throttle: NodeJS.Timeout | undefined;
    const output = (chunk: Buffer) => {
      if (!job) return;
      job.output = (job.output + chunk.toString()).slice(-60_000);
      if (!throttle)
        throttle = setTimeout(() => {
          throttle = undefined;
          publish(false);
        }, 100);
    };
    child.stdout.on("data", output);
    child.stderr.on("data", output);
    child.on("error", (e) => {
      if (job) {
        job.status = "error";
        job.output += "\n" + e.message;
      }
      jobChild = null;
      publish(false);
    });
    child.on("close", (code) => {
      if (job) {
        if (job.status !== "stopped")
          job.status = code === 0 ? "done" : "error";
        job.output += `\nProcess exited (${code ?? "signal"}).`;
      }
      jobChild = null;
      publish(false);
    });
    publish(false);
  });
  handle("project:stop", () => {
    if (jobChild) {
      if (job) job.status = "stopped";
      terminate(jobChild);
      publish(false);
    }
  });
}

if (!app.requestSingleInstanceLock()) app.quit();
else {
  app.on("second-instance", showHome);
  app.whenReady().then(() => {
    store = new Store(join(app.getPath("userData"), "sidefolk.json"));
    setupIPC();
    showHome();
    updatePet();
    const image = nativeImage.createFromPath(join(root, "assets/tray.png"));
    image.setTemplateImage(true);
    tray = new Tray(image);
    tray.setToolTip("Sidefolk");
    tray.setContextMenu(
      Menu.buildFromTemplate([
        { label: "Open Sidefolk", click: showHome },
        {
          label: "Show / hide companion",
          click: () => {
            store.state.settings.petVisible = !store.state.settings.petVisible;
            updatePet();
            publish();
          },
        },
        { type: "separator" },
        { label: "Quit Sidefolk", click: () => app.quit() },
      ]),
    );
    tray.on("click", showHome);
    Menu.setApplicationMenu(
      Menu.buildFromTemplate([
        {
          label: "Sidefolk",
          submenu: [
            { role: "about" },
            { type: "separator" },
            { role: "hide" },
            { role: "quit" },
          ],
        },
        { role: "editMenu" },
        { role: "viewMenu" },
        { role: "windowMenu" },
      ]),
    );
    setInterval(tick, 1000).unref();
    powerMonitor.on("resume", tick);
    tick();
  });
  app.on("activate", showHome);
  app.on("window-all-closed", () => {
    /* tray owns the background reminder lifecycle */
  });
  app.on("before-quit", () => {
    quitting = true;
    if (jobChild) terminate(jobChild);
    if (agentChild) terminate(agentChild);
  });
}
