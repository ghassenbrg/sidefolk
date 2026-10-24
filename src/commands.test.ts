import { describe, expect, it } from "vitest";
import { parse } from "./commands";

describe("parse", () => {
  it.each([
    ["remind me Friday at 3 to review the PR", { kind: "remind", text: "Friday at 3 to review the PR" }],
    ["reminders", { kind: "reminders" }],
    ["open session", { kind: "open", project: null }],
    ["open the api session", { kind: "open", project: "api" }],
    ["continue", { kind: "open", project: null }],
    ["open Sidefolk", { kind: "sidefolk" }],
    ["rename to Bun", { kind: "rename", name: "Bun" }],
    ["hide", { kind: "hide" }],
    ["help", { kind: "help" }],
  ])("%s", (input, expected) => {
    expect(parse(input)).toEqual(expected);
  });

  it("never turns unknown text into a task for an AI tool", () => {
    expect(parse("add dark mode to the settings page")).toEqual({ kind: "unknown", text: "add dark mode to the settings page" });
    expect(parse("ls -la").kind).toBe("unknown");
    expect(parse("continue the refactor").kind).toBe("unknown");
  });
});
