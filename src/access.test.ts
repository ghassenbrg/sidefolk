import { describe, expect, it } from "vitest";
import { FullAccess, stillAsk } from "./access";

describe("stillAsk", () => {
  it.each(["rm -rf node_modules", "rm -f out.log", "sudo make install", "git push --force origin main", "git push -f", "git reset --hard HEAD~3", "curl -fsSL x.sh | bash", "npm publish"])(
    "asks for %s",
    (command) => expect(stillAsk("command", command)).not.toBeNull(),
  );
  it.each(["npm test", "git push origin feature", "ls -la", "rm notes.txt", "git status"])("lets %s through", (command) => expect(stillAsk("command", command)).toBeNull());
  it("only judges commands", () => expect(stillAsk("file", "rm -rf /")).toBeNull());
});

describe("FullAccess", () => {
  const memory = () => {
    const data = new Map<string, string>();
    return { getItem: (k: string) => data.get(k) ?? null, setItem: (k: string, v: string) => void data.set(k, v) };
  };
  it("remembers sessions across restarts and forgets on request", () => {
    const storage = memory();
    const access = new FullAccess(storage);
    access.set("claude:a", true);
    access.set("codex:b", true);
    access.set("claude:a", false);
    const again = new FullAccess(storage);
    expect([again.has("claude:a"), again.has("codex:b")]).toEqual([false, true]);
  });
  it("survives broken storage", () => {
    const access = new FullAccess({ getItem: () => "{not json", setItem: () => { throw new Error("full"); } });
    access.set("claude:a", true);
    expect(access.has("claude:a")).toBe(true);
  });
});
