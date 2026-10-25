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
    expect(parse("continue the refactor").kind).toBe("unknown");
  });

  it("runs a shell command only with an explicit $, never from English", () => {
    expect(parse("$ ls -la")).toEqual({ kind: "run", command: "ls -la", folder: null });
    expect(parse("$ npm test in api")).toEqual({ kind: "run", command: "npm test", folder: "api" });
    expect(parse("$du -sh *")).toEqual({ kind: "run", command: "du -sh *", folder: null });
    for (const english of ["ls -la", "git pull", "make coffee", "touch grass", "less email please", "run npm test in api", "make build", "say hello", "find my notes"])
      expect(parse(english).kind).not.toBe("run");
  });

  it("turns anything with a date or time into a reminder, and app questions into the app", () => {
    expect(parse("call mom at 5pm")).toEqual({ kind: "remind", text: "call mom at 5pm" });
    expect(parse("dentist thursday 2:30").kind).toBe("remind");
    expect(parse("open enrollment closes friday 5pm").kind).toBe("remind");
    expect(parse("what do I have today")).toEqual({ kind: "sidefolk" });
    expect(parse("show my notes")).toEqual({ kind: "notes" });
    expect(parse("show my reminders")).toEqual({ kind: "reminders" });
    expect(parse("I finished the Q3 report").kind).toBe("unknown");
  });

  it("takes notes in one sentence", () => {
    expect(parse("note for evaluation: shipped the login migration, errors down 40%.")).toEqual({ kind: "note", notebook: "evaluation", text: "shipped the login migration, errors down 40%." });
    expect(parse("add to my ideas: a weekly wins digest")).toEqual({ kind: "note", notebook: "ideas", text: "a weekly wins digest" });
    expect(parse("note: call with Sam went well")).toEqual({ kind: "note", notebook: null, text: "call with Sam went well" });
    expect(parse("note that the API froze at 3pm")).toEqual({ kind: "note", notebook: null, text: "the API froze at 3pm" });
    expect(parse("new notebook Project X decisions")).toEqual({ kind: "notebook", name: "Project X decisions" });
    expect(parse("notes")).toEqual({ kind: "notes" });
    expect(parse("make a note about the release").kind).toBe("unknown");
  });

  it("starts sessions only when asked to start one", () => {
    expect(parse("start a claude session in sidefolk")).toEqual({ kind: "start", agent: "claude", folder: "sidefolk", full: false });
    expect(parse("new codex session in ~/git/api with full access")).toEqual({ kind: "start", agent: "codex", folder: "~/git/api", full: true });
    expect(parse("open a Claude Code session")).toEqual({ kind: "start", agent: "claude", folder: null, full: false });
    expect(parse("open the api session")).toEqual({ kind: "open", project: "api" });
  });

  it("opens folders in apps, links and apps", () => {
    expect(parse("open api in VS Code")).toEqual({ kind: "open-thing", target: "api", app: "VS Code" });
    expect(parse("open a terminal in ~/git/x")).toEqual({ kind: "open-thing", target: "~/git/x", app: "terminal" });
    expect(parse("open github.com/me/x")).toEqual({ kind: "open-thing", target: "github.com/me/x", app: null });
    expect(parse("open Slack")).toEqual({ kind: "open-thing", target: "Slack", app: null });
    expect(parse("open session")).toEqual({ kind: "open", project: null });
    expect(parse("open sidefolk")).toEqual({ kind: "sidefolk" });
    expect(parse("open notes")).toEqual({ kind: "notes" });
  });
});
