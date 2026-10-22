import { _electron } from "playwright";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import assert from "node:assert/strict";

const root = resolve(import.meta.dirname, "..");
const data = mkdtempSync(join(tmpdir(), "sidefolk-packaged-"));
const env = { ...process.env, SIDEFOLK_DATA_DIR: data };
delete env.ELECTRON_RUN_AS_NODE;
delete env.SIDEFOLK_DEV_URL;
let app;
try {
  app = await _electron.launch({
    executablePath: join(
      root,
      "release/Sidefolk-darwin-arm64/Sidefolk.app/Contents/MacOS/Sidefolk",
    ),
    env,
  });
  const page = await app.firstWindow();
  await page.getByRole("heading", { name: "Meet Pip" }).waitFor();
  assert.equal(await app.evaluate(({ app }) => app.isPackaged), true);
  if (process.argv.includes("--live")) {
    await page
      .getByRole("textbox", { name: "Message your companion" })
      .fill(
        "Reply with one short friendly sentence confirming you are connected. Do not use tools.",
      );
    await page
      .getByRole("button", { name: "Send message", exact: true })
      .click();
    let snapshot;
    for (let n = 0; n < 360; n++) {
      snapshot = await page.evaluate(() => window.sidefolk.snapshot());
      const session = snapshot.sessions.find(
        (s) => s.id === snapshot.activeSessionId,
      );
      if (!snapshot.agent && session.messages.length >= 3) break;
      await new Promise((resolve) => setTimeout(resolve, 250));
    }
    const session = snapshot.sessions.find(
      (s) => s.id === snapshot.activeSessionId,
    );
    assert.ok(!snapshot.agent, "agent should complete in 90 seconds");
    assert.ok(session.remoteId, JSON.stringify(session.messages));
    assert.equal(snapshot.usage.turns, 1);
    assert.ok(!session.messages.at(-1).text.includes("hit a snag"));
    await page.screenshot({
      path: join(root, "output/playwright/agent-connected.png"),
    });
    console.log(
      JSON.stringify({
        reply: session.messages.at(-1).text,
        usage: snapshot.usage,
      }),
    );
  }
  console.log("Packaged app check passed.");
} finally {
  if (app) await app.close();
  rmSync(data, { recursive: true, force: true });
}
