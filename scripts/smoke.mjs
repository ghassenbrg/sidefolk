// Runs the real desktop app against disposable data. No AI calls unless requested.
import { _electron as electron } from "playwright";
import {
  mkdtempSync,
  mkdirSync,
  writeFileSync,
  readFileSync,
  rmSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { resolve, join } from "node:path";
import assert from "node:assert/strict";
import { initialState } from "../dist-electron/electron/store.js";

const root = resolve(import.meta.dirname, "..");
const data = mkdtempSync(join(tmpdir(), "sidefolk-smoke-"));
const fixture = initialState();
fixture.settings.petShortcut = "Control+Alt+Shift+F20";
writeFileSync(join(data, "sidefolk.json"), JSON.stringify(fixture));
const project = join(data, "test-project");
mkdirSync(project);
writeFileSync(
  join(project, "package.json"),
  JSON.stringify({
    name: "sidefolk-test-project",
    scripts: { hello: 'node -e "console.log(12345)"' },
  }),
);
const env = { ...process.env, SIDEFOLK_DATA_DIR: data };
delete env.ELECTRON_RUN_AS_NODE;
delete env.SIDEFOLK_DEV_URL;
const errors = [];
let app;
const launch = () => electron.launch({ args: ["."], cwd: root, env });
const mainWindow = async (app) => {
  for (let i = 0; i < 150; i++) {
    const page = app
      .windows()
      .find(
        (window) =>
          window.url() &&
          window.url() !== "about:blank" &&
          !window.url().endsWith("#pet"),
      );
    if (page) return page;
    await new Promise((resolve) => setTimeout(resolve, 100));
  }
  throw new Error("Main window did not load.");
};
const screenshot = async (page, name) => {
  mkdirSync(join(root, "output/playwright"), { recursive: true });
  await page.screenshot({ path: join(root, `output/playwright/${name}.png`) });
};
try {
  app = await launch();
  let page = await mainWindow(app);
  page.on("pageerror", (error) => errors.push(error.message));
  await page.getByRole("heading", { name: "Meet Pip" }).waitFor();
  assert.equal(
    (await page.evaluate(() => window.sidefolk.snapshot())).settings.petVisible,
    true,
  );
  await page.evaluate(() => window.sidefolk.petControl("hide"));
  await page.locator("canvas").waitFor();
  await page.waitForTimeout(1800);
  await screenshot(page, "home");
  const send = async (text) => {
    await page
      .getByRole("textbox", { name: "Message your companion" })
      .fill(text);
    await page
      .getByRole("button", { name: "Send message", exact: true })
      .click();
  };
  await page
    .getByRole("button", { name: "Settings", exact: false })
    .first()
    .click();
  await page
    .getByRole("textbox", { name: "What should we call your pet?" })
    .fill("Mochi");
  await page.getByRole("radio", { name: "Local only" }).check();
  await page.getByRole("button", { name: "Save changes" }).click();
  await page.getByText("Settings saved.", { exact: false }).waitFor();
  await page
    .getByRole("button", { name: "Your companion", exact: true })
    .click();
  await page.getByRole("heading", { name: "Meet Mochi" }).waitFor();
  const requestedAt = Date.now();
  await send("can u remind to check my phone in 5 min from now");
  await page
    .getByRole("button", { name: "Complete check my phone", exact: true })
    .waitFor();
  const casual = await page.evaluate(() => window.sidefolk.snapshot());
  const phone = casual.items.find((i) => i.title === "check my phone");
  assert.ok(phone && Math.abs(phone.dueAt - requestedAt - 300_000) < 3000);
  assert.equal(
    casual.usage.turns,
    0,
    "casual wording should not spend model tokens",
  );
  await send("remind me to stretch in 5 seconds");
  await page
    .getByRole("button", { name: "Complete stretch", exact: true })
    .waitFor();
  await page
    .getByText("Ready now", { exact: false })
    .waitFor({ timeout: 15000 });
  await page
    .getByRole("button", { name: "Snooze stretch for 30 minutes" })
    .click();
  await page.waitForFunction(
    () => !document.body.innerText.includes("Ready now"),
  );
  await page
    .getByRole("button", { name: "Complete stretch", exact: true })
    .click();
  await send("add buy coffee to my todos");
  await page
    .getByRole("button", { name: "Complete buy coffee", exact: true })
    .waitFor();
  await send("remind me later to water the plants");
  await page
    .getByRole("button", { name: "tomorrow at 9am", exact: true })
    .click();
  await page
    .getByRole("button", { name: "Complete water the plants", exact: true })
    .waitFor();
  await send("remember that I prefer pnpm and TypeScript");
  await page.getByText("I’ll remember:", { exact: false }).waitFor();
  await screenshot(page, "home-with-reminders");
  await page.getByRole("button", { name: "Memory", exact: true }).click();
  await page
    .getByText("I prefer pnpm and TypeScript", { exact: true })
    .waitFor();
  await screenshot(page, "memory");
  await page.getByRole("button", { name: "Skills", exact: true }).click();
  await page.getByRole("button", { name: "Teach a skill" }).click();
  await page.getByRole("textbox", { name: "Skill name" }).fill("Small steps");
  await page
    .getByRole("textbox", { name: "How should your companion do it?" })
    .fill("Explain one practical next step at a time.");
  await page.getByRole("button", { name: "Save skill" }).click();
  await page.getByRole("heading", { name: "Small steps" }).waitFor();
  await page.getByRole("switch", { name: "Enable Small steps" }).click();
  await screenshot(page, "skills");
  await page
    .getByRole("button", { name: "Your companion", exact: true })
    .click();
  await page.getByRole("button", { name: "Show desktop pet" }).click();
  const pet = app.windows().find((window) => window.url().endsWith("#pet"));
  assert.ok(
    pet,
    "desktop window should exist independently of the main window",
  );
  await pet.getByRole("button", { name: "Talk", exact: true }).waitFor();
  assert.equal(
    await pet.evaluate(
      () => getComputedStyle(document.documentElement).backgroundColor,
    ),
    "rgba(0, 0, 0, 0)",
  );
  await pet.waitForTimeout(1200);
  await screenshot(pet, "floating-pet");
  assert.equal(
    await app.evaluate(({ BrowserWindow }) =>
      BrowserWindow.getAllWindows().some((w) => w.isAlwaysOnTop()),
    ),
    true,
  );
  if (process.platform === "darwin")
    assert.equal(
      await app.evaluate(({ BrowserWindow }) =>
        BrowserWindow.getAllWindows()
          .find((w) => w.getTitle() === "Sidefolk desktop companion")
          .isVisibleOnAllWorkspaces(),
      ),
      true,
    );
  const shortcut = (await page.evaluate(() => window.sidefolk.snapshot()))
    .settings.petShortcut;
  assert.equal(
    await app.evaluate(
      ({ globalShortcut }, key) => globalShortcut.isRegistered(key),
      shortcut,
    ),
    true,
  );
  // A conflict must leave the previously working shortcut and settings intact.
  const reserved = "Control+Alt+Shift+F19";
  assert.equal(
    await app.evaluate(
      ({ globalShortcut }, key) => globalShortcut.register(key, () => {}),
      reserved,
    ),
    true,
  );
  const conflict = await page.evaluate(async (key) => {
    const state = await window.sidefolk.snapshot();
    try {
      await window.sidefolk.settings({ ...state.settings, petShortcut: key });
      return false;
    } catch {
      return true;
    }
  }, reserved);
  assert.equal(conflict, true);
  assert.equal(
    (await page.evaluate(() => window.sidefolk.snapshot())).settings
      .petShortcut,
    shortcut,
  );
  assert.equal(
    await app.evaluate(
      ({ globalShortcut }, key) => globalShortcut.isRegistered(key),
      shortcut,
    ),
    true,
  );
  await app.evaluate(
    ({ globalShortcut }, key) => globalShortcut.unregister(key),
    reserved,
  );
  // Closing the control window leaves the pet visible and functional.
  await app.evaluate(({ BrowserWindow }) =>
    BrowserWindow.getAllWindows()
      .find((w) => w.getTitle() === "Sidefolk")
      .close(),
  );
  assert.equal(
    await app.evaluate(({ BrowserWindow }) =>
      BrowserWindow.getAllWindows()
        .find((w) => w.getTitle() === "Sidefolk")
        .isVisible(),
    ),
    false,
  );
  assert.equal(
    await app.evaluate(({ BrowserWindow }) =>
      BrowserWindow.getAllWindows()
        .find((w) => w.getTitle() === "Sidefolk desktop companion")
        .isVisible(),
    ),
    true,
  );
  await pet.evaluate(() => window.sidefolk.petControl("toggle"));
  assert.equal(
    (await pet.evaluate(() => window.sidefolk.snapshot())).settings.petVisible,
    false,
  );
  await page.evaluate(() => window.sidefolk.petControl("toggle"));
  assert.equal(
    (await page.evaluate(() => window.sidefolk.snapshot())).settings.petVisible,
    true,
  );
  assert.equal(
    await app.evaluate(({ BrowserWindow }) =>
      BrowserWindow.getAllWindows()
        .find((w) => w.getTitle() === "Sidefolk")
        .isVisible(),
    ),
    false,
  );
  // Repeated visibility changes reuse the same pet window.
  assert.equal(app.windows().length, 2);
  await pet.getByRole("button", { name: "Talk", exact: true }).click();
  assert.equal(
    await app.evaluate(({ BrowserWindow }) =>
      BrowserWindow.getAllWindows()
        .find((w) => w.getTitle() === "Sidefolk")
        .isVisible(),
    ),
    true,
  );
  await pet.getByRole("button", { name: "Hide desktop companion" }).click();
  await page.getByRole("button", { name: "Workshop", exact: true }).click();
  await app.evaluate(({ dialog }, path) => {
    dialog.showOpenDialog = async () => ({
      canceled: false,
      filePaths: [path],
    });
  }, project);
  await page
    .getByRole("button", { name: "Choose project", exact: true })
    .click();
  await page.getByText("sidefolk-test-project", { exact: true }).waitFor();
  await page.getByRole("button", { name: "Run", exact: true }).click();
  await page
    .getByRole("heading", { name: "Run this project script?" })
    .waitFor();
  await page.getByRole("button", { name: "Run script", exact: true }).click();
  await page.getByText("Process exited (0).", { exact: false }).waitFor();
  assert.ok(
    (await page.locator(".terminal-card pre").innerText()).includes("12345"),
  );
  await screenshot(page, "workshop");
  const saved = JSON.parse(readFileSync(join(data, "sidefolk.json"), "utf8"));
  assert.equal(saved.settings.petName, "Mochi");
  assert.equal(saved.memories[0].text, "I prefer pnpm and TypeScript");
  assert.ok(saved.items.some((item) => item.title === "water the plants"));
  assert.equal(
    saved.usage.turns,
    0,
    "all local actions must use zero model calls",
  );
  await app.close();
  app = await launch();
  page = await mainWindow(app);
  await page.getByRole("heading", { name: "Meet Mochi" }).waitFor();
  await page
    .getByRole("button", { name: "Complete water the plants", exact: true })
    .waitFor();
  await page.getByRole("button", { name: "Memory", exact: true }).click();
  await page
    .getByText("I prefer pnpm and TypeScript", { exact: true })
    .waitFor();
  assert.deepEqual(errors, []);
  console.log(
    "Desktop smoke passed: name, local chat, reminders, snooze, todos, memory, skills, floating 3D pet, project script, zero local AI calls, restart persistence.",
  );
} finally {
  if (app) await app.close().catch(() => {});
  rmSync(data, { recursive: true, force: true });
}
