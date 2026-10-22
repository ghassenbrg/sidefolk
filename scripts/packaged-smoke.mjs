import { _electron } from "playwright";
import { mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import assert from "node:assert/strict";
import { initialState } from "../dist-electron/electron/store.js";

const root = resolve(import.meta.dirname, "..");
const data = mkdtempSync(join(tmpdir(), "sidefolk-packaged-"));
const fixture = initialState();
fixture.settings.petShortcut = "Control+Alt+Shift+F18";
writeFileSync(join(data, "sidefolk.json"), JSON.stringify(fixture));
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
  let page;
  for (let i = 0; i < 150; i++) {
    page = app
      .windows()
      .find(
        (window) =>
          window.url() &&
          window.url() !== "about:blank" &&
          !window.url().endsWith("#pet"),
      );
    if (page) break;
    await new Promise((resolve) => setTimeout(resolve, 100));
  }
  assert.ok(page, "main window should load alongside the desktop pet");
  await page.getByRole("heading", { name: "Meet Pip" }).waitFor();
  assert.equal(await app.evaluate(({ app }) => app.isPackaged), true);
  const startup = await page.evaluate(() => window.sidefolk.snapshot());
  assert.equal(startup.settings.petVisible, true);
  assert.equal(
    await app.evaluate(
      ({ globalShortcut }, shortcut) => globalShortcut.isRegistered(shortcut),
      startup.settings.petShortcut,
    ),
    true,
  );
  if (process.argv.includes("--live") || process.argv.includes("--reminder")) {
    const reminder = process.argv.includes("--reminder");
    const requestedAt = Date.now();
    await page
      .getByRole("textbox", { name: "Message your companion" })
      .fill(
        reminder
          ? "I’d appreciate a little tap on the shoulder in seven minutes so I remember to check my phone."
          : "Reply with one short friendly sentence confirming you are connected. Do not use tools.",
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
    if (reminder) {
      assert.equal(snapshot.items.length, 1, JSON.stringify(session.messages));
      assert.equal(snapshot.items[0].kind, "reminder");
      assert.match(snapshot.items[0].title, /phone/i);
      assert.ok(
        Math.abs(snapshot.items[0].dueAt - requestedAt - 420_000) < 5000,
      );
      assert.match(session.messages.at(-1).text, /I’ll remind you/);
      assert.ok(!session.messages.at(-1).text.includes("SIDEFOLK_ACTIONS"));
    }
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
