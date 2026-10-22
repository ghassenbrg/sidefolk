import { contextBridge, ipcRenderer } from "electron";
import type { Settings, Skill, Snapshot } from "../shared/types.js";

contextBridge.exposeInMainWorld("sidefolk", {
  snapshot: () => ipcRenderer.invoke("state:get"),
  chat: (text: string) => ipcRenderer.invoke("chat:send", text),
  settings: (settings: Settings) =>
    ipcRenderer.invoke("settings:set", settings),
  item: (id: string, action: string) =>
    ipcRenderer.invoke("item:action", id, action),
  chooseProject: () => ipcRenderer.invoke("project:choose"),
  runScript: (name: string) => ipcRenderer.invoke("project:run", name),
  stopJob: () => ipcRenderer.invoke("project:stop"),
  openHome: () => ipcRenderer.invoke("window:home"),
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
