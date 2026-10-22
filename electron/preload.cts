import { contextBridge, ipcRenderer } from "electron";
import type { NewItem, Settings, Skill, Snapshot } from "../shared/types.js";

contextBridge.exposeInMainWorld("sidefolk", {
  finishSetup: (settings: Settings) =>
    ipcRenderer.invoke("setup:finish", settings),
  openQuick: () => ipcRenderer.invoke("window:quick"),
  closeQuick: () => ipcRenderer.invoke("window:quick-close"),
  openLink: (url: string) => ipcRenderer.invoke("link:open", url),
  testNotification: () => ipcRenderer.invoke("notification:test"),
  exportBackup: () => ipcRenderer.invoke("data:export"),
  updateItem: (id: string, item: NewItem) =>
    ipcRenderer.invoke("item:update", id, item),
  snapshot: () => ipcRenderer.invoke("state:get"),
  chat: (text: string) => ipcRenderer.invoke("chat:send", text),
  settings: (settings: Settings) =>
    ipcRenderer.invoke("settings:set", settings),
  item: (id: string, action: string) =>
    ipcRenderer.invoke("item:action", id, action),
  addItem: (item: NewItem) => ipcRenderer.invoke("item:add", item),
  chooseProject: () => ipcRenderer.invoke("project:choose"),
  runScript: (name: string) => ipcRenderer.invoke("project:run", name),
  stopJob: () => ipcRenderer.invoke("project:stop"),
  openHome: (page?: string) => ipcRenderer.invoke("window:home", page),
  onNavigate: (listener: (page: "home" | "settings" | "tasks") => void) => {
    const handler = (_event: unknown, page: "home" | "settings" | "tasks") =>
      listener(page);
    ipcRenderer.on("ui:navigate", handler);
    return () => ipcRenderer.removeListener("ui:navigate", handler);
  },
  petInteractive: (value: boolean) =>
    ipcRenderer.invoke("pet:interactive", value),
  petControl: (action: string) => ipcRenderer.invoke("pet:control", action),
  checkAgents: () => ipcRenderer.invoke("agents:check"),
  stopAgent: () => ipcRenderer.invoke("agents:stop"),
  newSession: () => ipcRenderer.invoke("session:new"),
  switchSession: (id: string) => ipcRenderer.invoke("session:switch", id),
  memory: (id: string, action: string) =>
    ipcRenderer.invoke("memory:action", id, action),
  addMemory: (text: string, id?: string) =>
    ipcRenderer.invoke("memory:add", text, id),
  saveSkill: (skill: Skill) => ipcRenderer.invoke("skill:save", skill),
  deleteSkill: (id: string) => ipcRenderer.invoke("skill:delete", id),
  onState: (listener: (state: Snapshot) => void) => {
    const handler = (_event: unknown, state: Snapshot) => listener(state);
    ipcRenderer.on("state:changed", handler);
    return () => ipcRenderer.removeListener("state:changed", handler);
  },
});
