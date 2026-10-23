import { describe, expect, it } from "vitest";
import { acceleratorFrom, shortcutLabel } from "./keys";

const press = (code: string, mods: Partial<Record<"metaKey" | "ctrlKey" | "altKey" | "shiftKey", boolean>> = {}) => ({
  metaKey: false,
  ctrlKey: false,
  altKey: false,
  shiftKey: false,
  code,
  ...mods,
});

describe("shortcuts", () => {
  it("shows accelerators as symbols", () => {
    expect(shortcutLabel("CommandOrControl+Shift+Space")).toBe("⌘⇧Space");
    expect(shortcutLabel("Alt+p")).toBe("⌥P");
  });
  it("records a combination with a modifier", () => {
    expect(acceleratorFrom(press("KeyP", { metaKey: true, shiftKey: true }))).toBe("CommandOrControl+Shift+P");
    expect(acceleratorFrom(press("Space", { altKey: true }))).toBe("Alt+Space");
  });
  it("waits for a real key and refuses shortcuts without a modifier", () => {
    expect(acceleratorFrom(press("ShiftLeft", { shiftKey: true }))).toBeNull();
    expect(acceleratorFrom(press("KeyA", { shiftKey: true }))).toBeNull();
  });
});
