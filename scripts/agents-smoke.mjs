// Opt-in live integration check. Makes TWO short model calls per named provider.
import { mkdtempSync, rmSync, mkdirSync, writeFileSync } from "node:fs";
import { join, resolve } from "node:path";
import { tmpdir } from "node:os";
import assert from "node:assert/strict";
import { initialState } from "../dist-electron/electron/store.js";
import { launchAgent, agentPrompt } from "../dist-electron/electron/agents.js";

const workspace = mkdtempSync(join(tmpdir(), "sidefolk-agent-check-"));
const providers = process.argv.slice(2).length
  ? process.argv.slice(2)
  : ["codex", "claude"];
const results = [];
try {
  for (const provider of providers) {
    assert.ok(["codex", "claude"].includes(provider));
    const state = initialState(),
      session = state.sessions[0];
    state.settings.provider = provider;
    session.provider = provider;
    session.workspace = workspace;
    async function turn(input) {
      let answer = "",
        usage;
      const hash = agentPrompt(state, session, input).contextHash;
      await new Promise((resolve, reject) => {
        const child = launchAgent(
          provider,
          session,
          state,
          input,
          (event) => {
            if (event.sessionId) session.remoteId = event.sessionId;
            if (event.text) answer = event.text;
            if (event.usage) usage = event.usage;
          },
          (error) => (error ? reject(new Error(error)) : resolve()),
        );
        child.unref();
      });
      session.contextHash = hash;
      return { answer, usage };
    }
    console.log(`Checking ${provider}: first turn…`);
    const first = await turn(
      "This is an integration check. My test word is acorn. Reply with exactly acorn. Do not use tools or propose memory.",
    );
    assert.ok(first.answer.toLowerCase().includes("acorn"), first.answer);
    assert.ok(session.remoteId, "must capture a native session ID");
    const id = session.remoteId;
    console.log(`Checking ${provider}: resume…`);
    const resumed = await turn(
      "What was my test word? Reply with that word only. Do not use tools or propose memory.",
    );
    assert.ok(resumed.answer.toLowerCase().includes("acorn"), resumed.answer);
    assert.equal(session.remoteId, id);
    results.push({ provider, first, resumed, resumedSameSession: true });
    console.log(
      `${provider} passed: live response + native session resume.`,
      JSON.stringify({ first: first.usage, resumed: resumed.usage }),
    );
  }
  const out = resolve("output/playwright");
  mkdirSync(out, { recursive: true });
  writeFileSync(
    join(out, "agents-check.json"),
    JSON.stringify(results, null, 2),
  );
} finally {
  rmSync(workspace, { recursive: true, force: true });
}
