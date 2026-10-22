import { test } from "node:test";
import assert from "node:assert/strict";
import {
  mkdtempSync,
  readFileSync,
  writeFileSync,
  rmSync,
  readdirSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { interpret } from "../shared/intents.js";
import { tickReminders } from "../electron/reminders.js";
import { initialState, Store } from "../electron/store.js";
import {
  agentArgs,
  agentPrompt,
  extractMemories,
  parseAgentEvent,
} from "../electron/agents.js";
import type { Item } from "../shared/types.js";
import { applyActions, extractActions } from "../electron/actions.js";
import { visibleAgentText } from "../shared/protocol.js";
import {
  clampPetPosition,
  summonedPetPosition,
  validPetShortcut,
  shortcutLabel,
  DEFAULT_PET_SHORTCUT,
} from "../shared/desktop.js";
import { stateSchema } from "../shared/types.js";

const now = new Date(2026, 9, 22, 14, 0);
test("desktop shortcuts require modifiers and format for the current platform", () => {
  assert.equal(validPetShortcut(DEFAULT_PET_SHORTCUT), true);
  assert.equal(validPetShortcut("Control+Alt+Space"), true);
  for (const shortcut of [
    "Space",
    "Shift+P",
    "CommandOrControl+",
    "nope+Space",
  ])
    assert.equal(validPetShortcut(shortcut), false);
  assert.equal(shortcutLabel(DEFAULT_PET_SHORTCUT, true), "⌘⇧Space");
  assert.equal(shortcutLabel(DEFAULT_PET_SHORTCUT, false), "Ctrl+Shift+Space");
});
test("pet summoning stays inside each monitor including negative coordinates", () => {
  const left = { x: -1920, y: -100, width: 1920, height: 1080 };
  assert.deepEqual(summonedPetPosition({ x: -2, y: -95 }, left), {
    x: -290,
    y: -100,
  });
  assert.deepEqual(clampPetPosition({ x: -5000, y: 5000 }, left), {
    x: -1920,
    y: 650,
  });
  const primary = { x: 0, y: 25, width: 1440, height: 850 };
  assert.deepEqual(clampPetPosition({ x: -1000, y: -100 }, primary), {
    x: 0,
    y: 25,
  });
});
test("existing app data gains desktop controls without losing the user’s hidden preference", () => {
  const old = JSON.parse(JSON.stringify(initialState()));
  old.settings.petVisible = false;
  delete old.settings.petShortcut;
  delete old.petPosition;
  const restored = stateSchema.parse(old);
  assert.equal(restored.settings.petVisible, false);
  assert.equal(restored.settings.petShortcut, DEFAULT_PET_SHORTCUT);
  assert.equal(restored.petPosition, null);
  assert.equal(initialState().settings.petVisible, true);
});
test("casual reminder requests work without a model call or exact syntax", () => {
  for (const input of [
    "can u remind to check my phone in 5 min from now",
    "could you please remind me to check my phone in 5 minutes?",
    "please remind me in 5 minutes to check my phone",
    "hey Pip, can you remind me to check my phone in 5 min",
    "set a reminder to check my phone in 5 minutes",
    "give me a nudge to check my phone in 5 minutes",
  ]) {
    assert.deepEqual(
      interpret(input, now),
      {
        type: "reminder",
        title: "check my phone",
        dueAt: now.getTime() + 300_000,
      },
      input,
    );
  }
});
test("questions, negation, quotes, and unrelated dated messages do not create reminders", () => {
  for (const input of [
    "can you remind me how to restart my phone?",
    "do not remind me to call Alex tomorrow",
    'explain the phrase "remind me tomorrow"',
    '"remind me to check my phone in 5 minutes"',
  ])
    assert.equal(interpret(input, now).type, "chat", input);
  assert.equal(
    interpret("tell me about tomorrow’s weather", now, "water the plants").type,
    "chat",
  );
});
test("ambiguous reminders use semantic fallback instead of saving placeholder titles", () => {
  assert.equal(interpret("remind me of that in 5 minutes", now).type, "chat");
  assert.equal(interpret("remind me in 5 minutes", now).type, "chat");
});
test("validated semantic actions create real reminders anchored to request time", () => {
  const state = initialState();
  const reply =
    'On it. <SIDEFOLK_ACTIONS>[{"type":"reminder.create","title":"check my phone","when":"in 5 minutes"}]</SIDEFOLK_ACTIONS>';
  const parsed = extractActions(reply);
  assert.equal(parsed.error, undefined);
  const result = applyActions(
    state,
    parsed.actions,
    now.getTime(),
    now.getTime() + 10_000,
  );
  assert.equal(state.items.length, 1);
  assert.equal(state.items[0].dueAt, now.getTime() + 300_000);
  assert.match(result.confirmations[0], /in 5 minutes/);
  assert.equal(visibleAgentText(reply), "On it.");
});
test("invalid and partial agent actions never save a task", () => {
  for (const payload of [
    '[{"type":"terminal.run","command":"rm -rf anything"}]',
    '[{"type":"reminder.create","title":"this","when":"tomorrow"}]',
    '[{"type":"reminder.create","title":"call Alex","when":"tomorrow","extra":true}]',
    "not json",
  ])
    assert.ok(
      extractActions(`<SIDEFOLK_ACTIONS>${payload}</SIDEFOLK_ACTIONS>`).error,
    );
  assert.ok(extractActions("<SIDEFOLK_ACTIONS>[").error);
  assert.equal(visibleAgentText("Working <SIDEFOLK_ACTIONS>[{"), "Working");
  const state = initialState();
  const result = applyActions(
    state,
    [
      { type: "todo.create", title: "coffee" },
      { type: "reminder.create", title: "call Alex", when: "yesterday" },
    ],
    now.getTime(),
    now.getTime(),
  );
  assert.ok(result.error);
  assert.equal(state.items.length, 0, "batch validation must be atomic");
});
test("duplicate actions execute once and unsupported output is not treated as an action", () => {
  const state = initialState();
  const action = {
    type: "reminder.create" as const,
    title: "call Alex",
    when: "in 5 minutes",
  };
  applyActions(state, [action, action], now.getTime(), now.getTime());
  assert.equal(state.items.length, 1);
  assert.equal(extractActions("I have scheduled something").present, false);
});
test("natural reminders preserve the task and resolve future dates", () => {
  const result = interpret(
    "remind me to send the proposal tomorrow at 3pm",
    now,
  );
  assert.equal(result.type, "reminder");
  if (result.type !== "reminder") return;
  assert.equal(result.title, "send the proposal");
  assert.equal(result.dueAt, new Date(2026, 9, 23, 15, 0).getTime());
  const week = interpret("remind me next week to call Alex", now);
  assert.equal(week.type, "reminder");
  if (week.type === "reminder") {
    assert.equal(week.title, "call Alex");
    assert.equal(new Date(week.dueAt).getHours(), 9);
  }
});
test("later asks for a time and follow-up schedules the original task", () => {
  assert.deepEqual(interpret("remind me later to water the plants", now), {
    type: "clarify",
    title: "water the plants",
  });
  const followup = interpret("in an hour", now, "water the plants");
  assert.deepEqual(followup, {
    type: "reminder",
    title: "water the plants",
    dueAt: now.getTime() + 3_600_000,
  });
});
test("preferences and todos route locally without being mistaken for reminders", () => {
  assert.deepEqual(interpret("remember that I prefer pnpm", now), {
    type: "memory",
    text: "I prefer pnpm",
  });
  assert.deepEqual(interpret("add buy coffee to my todos", now), {
    type: "todo",
    title: "buy coffee",
  });
});
test("past dates do not silently become a scheduled reminder", () => {
  assert.equal(
    interpret("remind me yesterday to call Alex", now).type,
    "clarify",
  );
});
const reminder = (): Item => ({
  id: "r",
  title: "Stretch",
  kind: "reminder",
  dueAt: 100,
  createdAt: 1,
  status: "pending",
  notifiedAt: null,
});
test("overdue reminders are delivered once after restart or sleep", () => {
  const item = reminder();
  assert.equal(tickReminders([item], 200, false).notify.length, 1);
  assert.equal(item.status, "due");
  assert.equal(tickReminders([item], 300, false).notify.length, 0);
  item.status = "done";
  item.notifiedAt = null;
  assert.equal(tickReminders([item], 400, false).notify.length, 0);
});
test("quiet mode holds notifications and delivers once when quiet ends", () => {
  const item = reminder();
  assert.equal(tickReminders([item], 200, true).notify.length, 0);
  assert.equal(item.status, "due");
  assert.equal(item.notifiedAt, null);
  assert.equal(tickReminders([item], 300, false).notify.length, 1);
});
test("snoozed reminders wait for their new due time", () => {
  const item = { ...reminder(), dueAt: 500 };
  assert.equal(tickReminders([item], 200, false).changed, false);
  assert.equal(tickReminders([item], 500, false).notify.length, 1);
});
test("the store persists sessions and preserves invalid data for recovery", () => {
  const dir = mkdtempSync(join(tmpdir(), "sidefolk-store-"));
  try {
    const file = join(dir, "state.json");
    const store = new Store(file);
    store.addMessage("user", "hello");
    store.save();
    assert.equal(
      new Store(file).state.sessions[0].messages.at(-1)?.text,
      "hello",
    );
    writeFileSync(file, "{invalid");
    const recovered = new Store(file);
    assert.ok(recovered.warning);
    const backup = readdirSync(dir).find((f) => f.includes(".recovery-"))!;
    assert.equal(readFileSync(join(dir, backup), "utf8"), "{invalid");
  } finally {
    rmSync(dir, { recursive: true });
  }
});
test("Codex resume reapplies read-only permission and never uses global last-session resume", () => {
  const session = { ...initialState().sessions[0], remoteId: "owned-session" };
  const args = agentArgs("codex", session, false);
  assert.deepEqual(args.slice(0, 2), ["exec", "resume"]);
  assert.ok(args.includes('sandbox_mode="read-only"'));
  assert.ok(args.includes("owned-session"));
  assert.ok(!args.includes("--last"));
});
test("Claude read-only turns expose no write or shell tools", () => {
  const args = agentArgs(
    "claude",
    { ...initialState().sessions[0], toolsEnabled: true },
    false,
  );
  assert.equal(args[args.indexOf("--tools") + 1], "Read,Glob,Grep");
  assert.ok(args.includes("dontAsk"));
});
test("unchanged session context is not resent, and unconfirmed memories stay out", () => {
  const state = initialState(),
    session = state.sessions[0];
  state.memories.push({
    id: "secret",
    text: "UNCONFIRMED FACT",
    source: "suggested",
    createdAt: 1,
  });
  const first = agentPrompt(state, session, "hello");
  assert.ok(!first.prompt.includes("UNCONFIRMED FACT"));
  session.remoteId = "session";
  session.contextHash = first.contextHash;
  const resumed = agentPrompt(state, session, "another question");
  assert.ok(resumed.prompt.length < first.prompt.length / 2);
  state.settings.petName = "Mochi";
  assert.ok(agentPrompt(state, session, "hi").prompt.includes("Mochi"));
});
test("shared memory payload stays bounded even with many notes", () => {
  const state = initialState();
  state.memories = Array.from({ length: 100 }, (_, i) => ({
    id: String(i),
    text: "long preference ".repeat(70),
    source: "you",
    createdAt: i,
  }));
  assert.ok(
    agentPrompt(state, state.sessions[0], "preference").prompt.length < 5000,
  );
});
test("memory suggestions are parsed from the same response and removed from visible text", () => {
  assert.deepEqual(
    extractMemories(
      'Okay!\n<SIDEFOLK_MEMORY>["Prefers pnpm"]</SIDEFOLK_MEMORY>',
    ),
    { text: "Okay!", memories: ["Prefers pnpm"] },
  );
  assert.deepEqual(
    extractMemories("Hello <SIDEFOLK_MEMORY>invalid</SIDEFOLK_MEMORY>"),
    { text: "Hello", memories: [] },
  );
});
test("provider events carry actual session, tool, result, and usage data", () => {
  assert.deepEqual(
    parseAgentEvent("codex", { type: "thread.started", thread_id: "abc" }),
    { sessionId: "abc" },
  );
  assert.deepEqual(
    parseAgentEvent("codex", {
      type: "turn.completed",
      usage: { input_tokens: 100, cached_input_tokens: 80, output_tokens: 10 },
    }).usage,
    { input: 100, cached: 80, output: 10 },
  );
  assert.equal(
    parseAgentEvent("claude", {
      type: "result",
      result: "hello",
      session_id: "xyz",
    }).text,
    "hello",
  );
});

test("legacy companions gain appearance defaults without changing identity or memory", () => {
  const original = initialState();
  const legacy = JSON.parse(JSON.stringify(original));
  delete legacy.settings.petSpecies;
  delete legacy.settings.petStyle;
  delete legacy.settings.petAccessory;
  legacy.settings.petName = "My friend";
  const directory = mkdtempSync(join(tmpdir(), "sidefolk-appearance-"));
  try {
    writeFileSync(join(directory, "sidefolk.json"), JSON.stringify(legacy));
    const restored = new Store(join(directory, "sidefolk.json"));
    assert.equal(restored.state.settings.petName, "My friend");
    assert.equal(restored.state.settings.petSpecies, "bunny");
    assert.equal(restored.state.settings.petStyle, "3d");
    assert.equal(restored.state.settings.petAccessory, "none");
    assert.deepEqual(restored.state.sessions, original.sessions);
  } finally {
    rmSync(directory, { recursive: true, force: true });
  }
});

test("generic add requests stay with the agent rather than creating unrelated todos", () => {
  for (const text of [
    "add dark mode to my app",
    "add a new endpoint",
    "add two numbers",
  ])
    assert.equal(interpret(text).type, "chat");
  assert.deepEqual(interpret("add buy coffee to my list"), {
    type: "todo",
    title: "buy coffee",
  });
  assert.deepEqual(interpret("todo: buy coffee"), {
    type: "todo",
    title: "buy coffee",
  });
});
test("project tools require a currently connected matching workspace", async () => {
  const { projectToolsAllowed } = await import("../shared/safety.js");
  assert.equal(projectToolsAllowed(undefined, "/old-project"), false);
  assert.equal(projectToolsAllowed("/new-project", "/old-project"), false);
  assert.equal(projectToolsAllowed("/project", "/project"), true);
});
test("external links reject executable schemes and credential-bearing URLs", async () => {
  const { externalWebUrl } = await import("../shared/safety.js");
  assert.equal(
    externalWebUrl("https://example.com/docs"),
    "https://example.com/docs",
  );
  for (const value of [
    "javascript:alert(1)",
    "file:///etc/passwd",
    "https://user:password@example.com",
    "data:text/html,hello",
  ])
    assert.throws(() => externalWebUrl(value));
});

test("script review rejects changed or newly added lifecycle hooks", async () => {
  const { scriptReviewMatches } = await import("../shared/safety.js");
  const original = { build: "tsc", prebuild: "echo ready" };
  assert.equal(scriptReviewMatches(original, { ...original }, "build"), true);
  assert.equal(
    scriptReviewMatches(
      original,
      { ...original, prebuild: "different command" },
      "build",
    ),
    false,
  );
  assert.equal(
    scriptReviewMatches(
      original,
      { ...original, postbuild: "new command" },
      "build",
    ),
    false,
  );
});

test("structurally valid data with a missing active session is preserved for recovery", () => {
  const directory = mkdtempSync(join(tmpdir(), "sidefolk-session-recovery-"));
  try {
    const broken = initialState();
    broken.activeSessionId = "missing";
    const file = join(directory, "sidefolk.json");
    writeFileSync(file, JSON.stringify(broken));
    const restored = new Store(file);
    assert.ok(restored.warning);
    assert.ok(
      restored.state.sessions.some(
        (s) => s.id === restored.state.activeSessionId,
      ),
    );
    assert.ok(readdirSync(directory).some((n) => n.includes(".recovery-")));
  } finally {
    rmSync(directory, { recursive: true, force: true });
  }
});
