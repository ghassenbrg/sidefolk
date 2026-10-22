import { z } from "zod";
import { DEFAULT_PET_SHORTCUT, validPetShortcut } from "./desktop.js";

export const settingsSchema = z.object({
  petName: z.string().trim().min(1).max(24),
  color: z.enum(["sage", "peach", "lilac"]),
  focus: z.boolean(),
  petVisible: z.boolean(),
  petShortcut: z
    .string()
    .max(90)
    .refine(
      validPetShortcut,
      "Choose a shortcut with Command, Control, or Alt and a key.",
    )
    .default(DEFAULT_PET_SHORTCUT),
  provider: z.enum(["local", "codex", "claude"]),
  allowEdits: z.boolean(),
  economy: z.boolean(),
});
export type Settings = z.infer<typeof settingsSchema>;
export const itemSchema = z.object({
  id: z.string(),
  title: z.string(),
  kind: z.enum(["todo", "reminder"]),
  createdAt: z.number(),
  dueAt: z.number().nullable(),
  status: z.enum(["pending", "due", "done"]),
  notifiedAt: z.number().nullable(),
});
export type Item = z.infer<typeof itemSchema>;
export const messageSchema = z.object({
  id: z.string(),
  role: z.enum(["user", "assistant"]),
  text: z.string(),
  createdAt: z.number(),
});
export type Message = z.infer<typeof messageSchema>;
export const memorySchema = z.object({
  id: z.string(),
  text: z.string().max(1200),
  source: z.enum(["you", "suggested"]),
  createdAt: z.number(),
});
export type Memory = z.infer<typeof memorySchema>;
export const skillSchema = z.object({
  id: z.string(),
  name: z.string().min(1).max(60),
  instructions: z.string().min(1).max(6000),
  enabled: z.boolean(),
});
export type Skill = z.infer<typeof skillSchema>;
export const sessionSchema = z.object({
  id: z.string(),
  title: z.string(),
  provider: z.enum(["local", "codex", "claude"]),
  workspace: z.string(),
  remoteId: z.string().nullable(),
  messages: z.array(messageSchema),
  createdAt: z.number(),
  contextHash: z.string().default(""),
  toolsEnabled: z.boolean().default(false),
  reportedUsage: z
    .object({ input: z.number(), cached: z.number(), output: z.number() })
    .default({ input: 0, cached: 0, output: 0 }),
});
export type AgentSession = z.infer<typeof sessionSchema>;
export const stateSchema = z.object({
  version: z.literal(1),
  settings: settingsSchema,
  items: z.array(itemSchema),
  sessions: z.array(sessionSchema),
  activeSessionId: z.string(),
  memories: z.array(memorySchema),
  skills: z.array(skillSchema),
  usage: z.object({
    turns: z.number(),
    input: z.number(),
    cached: z.number(),
    output: z.number(),
  }),
  pendingReminder: z.object({ title: z.string() }).nullable(),
  petPosition: z
    .object({ x: z.number().finite(), y: z.number().finite() })
    .nullable()
    .default(null),
});
export type AppState = z.infer<typeof stateSchema>;
export type Project = {
  path: string;
  name: string;
  scripts: Record<string, string>;
};
export type Job = {
  id: string;
  script: string;
  status: "running" | "done" | "error" | "stopped";
  output: string;
  startedAt: number;
};
export type AgentRun = {
  provider: string;
  status: "thinking" | "working";
  activity: string;
  text: string;
  startedAt: number;
};
export type Snapshot = AppState & {
  project: Project | null;
  job: Job | null;
  agent: AgentRun | null;
  storageWarning?: string;
  shortcutRegistered: boolean;
  shortcutError?: string;
};
export type Intent =
  | { type: "reminder"; title: string; dueAt: number }
  | { type: "clarify"; title: string }
  | { type: "todo"; title: string }
  | { type: "memory"; text: string }
  | { type: "list" }
  | { type: "project" }
  | { type: "chat" };
export interface SidefolkAPI {
  snapshot(): Promise<Snapshot>;
  chat(text: string): Promise<void>;
  settings(settings: Settings): Promise<void>;
  item(
    id: string,
    action: "done" | "reopen" | "snooze" | "delete",
  ): Promise<void>;
  chooseProject(): Promise<void>;
  runScript(name: string): Promise<void>;
  stopJob(): Promise<void>;
  openHome(): Promise<void>;
  petInteractive(value: boolean): Promise<void>;
  petControl(action: "show" | "hide" | "toggle" | "summon"): Promise<void>;
  checkAgents(): Promise<Record<string, string>>;
  stopAgent(): Promise<void>;
  newSession(): Promise<void>;
  switchSession(id: string): Promise<void>;
  memory(id: string, action: "accept" | "delete"): Promise<void>;
  addMemory(text: string, id?: string): Promise<void>;
  saveSkill(skill: Skill): Promise<void>;
  deleteSkill(id: string): Promise<void>;
  onState(listener: (state: Snapshot) => void): () => void;
}
