import { _electron as electron } from "playwright";
import {
  mkdtempSync,
  writeFileSync,
  readFileSync,
  rmSync,
  mkdirSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import assert from "node:assert/strict";
import { initialState } from "../dist-electron/electron/store.js";
const root = resolve(import.meta.dirname, ".."),
  data = mkdtempSync(join(tmpdir(), "sidefolk-product-"));
const fixture = initialState();
fixture.sessions[0].toolsEnabled = true;
fixture.settings.petShortcut = "Control+Alt+Shift+F16";
fixture.settings.petVisible = false;
writeFileSync(join(data, "sidefolk.json"), JSON.stringify(fixture));
const env = { ...process.env, SIDEFOLK_DATA_DIR: data };
delete env.ELECTRON_RUN_AS_NODE;
delete env.SIDEFOLK_DEV_URL;
let app;
const errors = [];
const main = async () => {
  for (let i = 0; i < 150; i++) {
    const p = app
      .windows()
      .find((w) => w.url().includes("index.html") && !w.url().includes("#"));
    if (p) return p;
    await new Promise((r) => setTimeout(r, 50));
  }
  throw Error("Missing home window");
};
const shot = async (p, name) => {
  mkdirSync(join(root, "output/playwright"), { recursive: true });
  await p.screenshot({
    path: join(root, `output/playwright/product-${name}.png`),
  });
};
try {
  app = await electron.launch({ args: ["."], cwd: root, env });
  let page = await main();
  page.on("pageerror", (e) => errors.push(e.message));
  await page
    .getByRole("heading", { name: "Let’s make this useful." })
    .waitFor();
  await shot(page, "setup");
  await page
    .getByRole("textbox", { name: "Your companion’s name" })
    .fill("Nori");
  await page.getByRole("button", { name: "Start using Sidefolk" }).click();
  await page.getByRole("heading", { name: "Meet Nori" }).waitFor();
  assert.equal(
    (await page.evaluate(() => window.sidefolk.snapshot())).sessions[0]
      .toolsEnabled,
    false,
  );
  assert.equal(
    (await page.evaluate(() => window.sidefolk.snapshot())).setupComplete,
    true,
  );
  const draft = page.getByRole("textbox", { name: "Message your companion" });
  await draft.fill("An unfinished thought");
  await page.getByRole("button", { name: "Memory", exact: true }).click();
  await page
    .getByRole("button", { name: "Your companion", exact: true })
    .click();
  assert.equal(await draft.inputValue(), "An unfinished thought");
  await draft.fill("");
  await page
    .getByRole("button", { name: "Quick Ask", exact: false })
    .first()
    .click();
  let quick;
  for (let i = 0; i < 100; i++) {
    quick = app.windows().find((p) => p.url().endsWith("#quick"));
    if (quick) break;
    await page.waitForTimeout(50);
  }
  quick.on("pageerror", (e) => errors.push(e.message));
  await quick
    .getByRole("textbox", { name: "Message your companion" })
    .fill("remind me to review the prototype in 10 minutes");
  await quick.getByRole("button", { name: "Send message" }).click();
  await quick.getByText("Reminder saved", { exact: true }).waitFor();
  await shot(quick, "quick-receipt");
  await quick
    .locator(".action-receipt")
    .getByRole("button", { name: "Edit", exact: true })
    .click();
  await quick
    .getByRole("textbox", { name: "Task title" })
    .fill("Review the final prototype");
  await quick.getByRole("button", { name: "In 30 minutes" }).click();
  await quick.getByRole("button", { name: "Save task" }).click();
  await quick
    .getByText("Review the final prototype", { exact: true })
    .waitFor();
  await quick.getByRole("button", { name: "Connect AI", exact: true }).click();
  await page.getByRole("heading", { name: "Settings", exact: true }).waitFor();
  await page.getByRole("button", { name: "Review setup", exact: true }).click();
  await page
    .getByRole("button", { name: "← Back to workspace", exact: true })
    .click();
  await page
    .getByRole("button", { name: "Quick Ask", exact: false })
    .first()
    .click();
  await quick.keyboard.press("Escape");
  assert.equal(
    await app.evaluate(({ BrowserWindow }) =>
      BrowserWindow.getAllWindows()
        .find((w) => w.getTitle() === "Sidefolk Quick Ask")
        .isVisible(),
    ),
    false,
  );
  await page.getByRole("button", { name: "Tasks", exact: true }).click();
  await page
    .getByRole("button", {
      name: "Delete Review the final prototype",
      exact: true,
    })
    .click();
  await page.getByRole("dialog", { name: "Delete this task?" }).waitFor();
  await page.keyboard.press("Escape");
  assert.equal(
    (await page.evaluate(() => window.sidefolk.snapshot())).items.length,
    1,
  );
  await page
    .getByRole("button", { name: "Edit Review the final prototype" })
    .click();
  await page
    .getByRole("textbox", { name: "Task title" })
    .fill("Release checklist");
  await page.getByRole("button", { name: "Save task" }).click();
  await shot(page, "tasks");
  await assert.rejects(() =>
    page.evaluate(() => window.sidefolk.openLink("file:///tmp/test")),
  );
  const backup = join(data, "export.json");
  await app.evaluate(({ dialog }, path) => {
    dialog.showSaveDialog = async () => ({ canceled: false, filePath: path });
  }, backup);
  assert.equal(
    await page.evaluate(() => window.sidefolk.exportBackup()),
    backup,
  );
  assert.equal(
    JSON.parse(readFileSync(backup, "utf8")).items[0].title,
    "Release checklist",
  );
  await page
    .getByRole("button", { name: "Your companion", exact: true })
    .click();
  await shot(page, "workspace");
  await page.evaluate(() => window.sidefolk.petControl("show"));
  await page.waitForTimeout(300);
  const pet = app.windows().find((p) => p.url().endsWith("#pet"));
  await pet.getByRole("button", { name: "Talk", exact: true }).click();
  await quick
    .getByRole("textbox", { name: "Message your companion" })
    .waitFor();
  assert.equal(
    (await page.evaluate(() => window.sidefolk.snapshot())).usage.turns,
    0,
  );
  assert.deepEqual(errors, []);
  await app.close();
  app = await electron.launch({ args: ["."], cwd: root, env });
  page = await main();
  await page.getByRole("heading", { name: "Meet Nori" }).waitFor();
  const restored = await page.evaluate(() => window.sidefolk.snapshot());
  assert.equal(restored.items[0].title, "Release checklist");
  assert.equal(restored.setupComplete, true);
  console.log(
    "Product acceptance passed: onboarding, draft recovery, Quick Ask, saved-action receipts, editing, Escape, delete cancellation, backup export, URL rejection, pet entry, and restart. Zero AI calls.",
  );
} finally {
  if (app) await app.close();
  rmSync(data, { recursive: true, force: true });
}
