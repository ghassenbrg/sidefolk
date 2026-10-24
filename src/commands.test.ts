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

  it("adds and removes Spark workers by project", () => {
    expect(parse("give api a spark")).toEqual({ kind: "spark", project: "api", name: null, remove: false });
    expect(parse("add a spark for ~/git/web called Frontend")).toEqual({ kind: "spark", project: "~/git/web", name: "Frontend", remove: false });
    expect(parse("send the api spark home")).toEqual({ kind: "spark", project: "api", name: null, remove: true });
    expect(parse("give me a minute").kind).toBe("unknown");
  });
});
