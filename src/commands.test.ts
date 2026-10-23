import { describe, expect, it } from "vitest";
import { parse } from "./commands";

describe("parse", () => {
  it.each([
    ["call Pip", { kind: "call", who: "Pip" }],
    ["where is the api pet?", { kind: "call", who: "the api pet" }],
    ["send Pip home", { kind: "home", who: "Pip" }],
    ["Pip, go home", { kind: "home", who: "Pip" }],
    ["go home", { kind: "home", who: null }],
    ["tell Pip to run the tests", { kind: "tell", who: "Pip", task: "run the tests" }],
    ["Pip: fix the lint", { kind: "tell", who: "Pip", task: "fix the lint" }],
    ["codex: add a README", { kind: "codex", task: "add a README" }],
    ["rename Pip to Bun", { kind: "rename", who: "Pip", name: "Bun" }],
    ["rename to Bun", { kind: "rename", who: null, name: "Bun" }],
    ["Pip wear glasses", { kind: "look", who: "Pip", accessory: "glasses" }],
    ["wear a beanie", { kind: "look", who: null, accessory: "beanie" }],
    ["put on headphones", { kind: "look", who: null, accessory: "headphones" }],
    ["Pip take off the glasses", { kind: "look", who: "Pip", accessory: "none" }],
    ["Pip color midnight", { kind: "look", who: "Pip", palette: "midnight" }],
    ["be cocoa", { kind: "look", who: null, palette: "cocoa" }],
    ["Pip become a fox", { kind: "look", who: "Pip", species: "fox" }],
    ["turn into a cat", { kind: "look", who: null, species: "cat" }],
    ["crew", { kind: "crew" }],
    ["customize", { kind: "customize", who: null }],
    ["dress up Pip", { kind: "customize", who: "Pip" }],
    ["forget Pip", { kind: "forget", who: "Pip" }],
    ["remind me Friday at 3 to review the PR", { kind: "remind", text: "Friday at 3 to review the PR" }],
    ["reminders", { kind: "reminders" }],
  ])("%s", (input, expected) => {
    expect(parse(input)).toEqual(expected);
  });

  it("leaves everything else to an agent", () => {
    expect(parse("add dark mode to the settings page")).toEqual({ kind: "task", text: "add dark mode to the settings page" });
    // An unknown color is a task, not a silent no-op.
    expect(parse("be quiet").kind).toBe("task");
    expect(parse("http://x.y: look at this").kind).toBe("task");
  });
});
