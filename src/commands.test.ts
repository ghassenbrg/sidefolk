import { describe, expect, it } from "vitest";
import { knowCommands, parse } from "./commands";

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
    expect(parse("continue the refactor").kind).toBe("unknown");
  });

  it("recognizes plain commands locally and never sends them to an AI tool", () => {
    expect(parse("ls -la")).toEqual({ kind: "run", command: "ls -la", folder: null });
    expect(parse("git pull")).toEqual({ kind: "run", command: "git pull", folder: null });
    expect(parse("run npm test in api")).toEqual({ kind: "run", command: "npm test", folder: "api" });
    expect(parse("run make build in ~/git/sidefolk")).toEqual({ kind: "run", command: "make build", folder: "~/git/sidefolk" });
    expect(parse("$ du -sh *")).toEqual({ kind: "run", command: "du -sh *", folder: null });
  });

  it("knows PATH commands written like commands, not sentences that start with one", () => {
    knowCommands(["terraform", "open", "say", "make"]);
    expect(parse("terraform plan -out x").kind).toBe("run");
    expect(parse("terraform").kind).toBe("run");
    expect(parse("open the team's Jira").kind).toBe("unknown");
    expect(parse("say hello").kind).toBe("unknown");
    expect(parse("make a note about the release").kind).toBe("unknown");
    expect(parse("find my notes").kind).toBe("unknown");
    expect(parse("make build").kind).toBe("run");
    knowCommands([]);
  });
});
