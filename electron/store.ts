import {
  existsSync,
  mkdirSync,
  readFileSync,
  renameSync,
  writeFileSync,
} from "node:fs";
import { dirname } from "node:path";
import { randomUUID } from "node:crypto";
import { stateSchema, type AppState, type Message } from "../shared/types.js";
import { DEFAULT_PET_SHORTCUT } from "../shared/desktop.js";

export function initialState(): AppState {
  return {
    version: 1,
    settings: {
      petName: "Pip",
      color: "sage",
      focus: false,
      petVisible: true,
      petShortcut: DEFAULT_PET_SHORTCUT,
      provider: "codex",
      allowEdits: false,
      economy: true,
    },
    items: [],
    pendingReminder: null,
    petPosition: null,
    activeSessionId: "first",
    sessions: [
      {
        id: "first",
        title: "A little hello",
        provider: "codex",
        workspace: "",
        remoteId: null,
        contextHash: "",
        toolsEnabled: false,
        reportedUsage: { input: 0, cached: 0, output: 0 },
        createdAt: Date.now(),
        messages: [
          message(
            "assistant",
            "Hey, I’m Pip. Your little desktop companion, with a real agent behind the scenes. Give me a name, something to remember, or a project to work on.",
          ),
        ],
      },
    ],
    memories: [],
    usage: { turns: 0, input: 0, cached: 0, output: 0 },
    skills: [
      {
        id: "companion",
        name: "Thoughtful companion",
        enabled: true,
        instructions:
          "Be a warm, resourceful desktop companion. Be concise, speak naturally, and use a little humor when it fits. Never pretend you performed an action you did not perform.",
      },
      {
        id: "project-scout",
        name: "Project scout",
        enabled: true,
        instructions:
          "When exploring a project, read its instructions and package metadata first. Explain what it does, how to run it, and what to work on next. Ground conclusions in files you actually inspected.",
      },
    ],
  };
}
export function message(role: Message["role"], text: string): Message {
  return { id: randomUUID(), role, text, createdAt: Date.now() };
}
export class Store {
  state: AppState;
  warning?: string;
  constructor(readonly file: string) {
    mkdirSync(dirname(file), { recursive: true });
    if (existsSync(file)) {
      try {
        this.state = stateSchema.parse(JSON.parse(readFileSync(file, "utf8")));
      } catch {
        const backup = `${file}.recovery-${Date.now()}`;
        renameSync(file, backup);
        this.state = initialState();
        this.warning = `Your previous data could not be read. It is preserved at ${backup}.`;
      }
    } else this.state = initialState();
  }
  save() {
    const state = stateSchema.parse(this.state);
    writeFileSync(`${this.file}.tmp`, JSON.stringify(state, null, 2), {
      mode: 0o600,
    });
    renameSync(`${this.file}.tmp`, this.file);
  }
  addMessage(role: Message["role"], text: string) {
    const session = this.state.sessions.find(
      (s) => s.id === this.state.activeSessionId,
    )!;
    session.messages.push(message(role, text));
    session.messages = session.messages.slice(-100);
  }
}
