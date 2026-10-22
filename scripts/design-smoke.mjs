import { _electron as electron } from "playwright";
import { mkdtempSync, writeFileSync, mkdirSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import assert from "node:assert/strict";
import { initialState } from "../dist-electron/electron/store.js";
const root = resolve(import.meta.dirname, ".."),
  data = mkdtempSync(join(tmpdir(), "sidefolk-design-")),
  fixture = initialState();
fixture.setupComplete = true;
fixture.settings.petShortcut = "Control+Alt+Shift+F17";
fixture.settings.provider = "local";
fixture.settings.petVisible = false;
writeFileSync(join(data, "sidefolk.json"), JSON.stringify(fixture));
const env = { ...process.env, SIDEFOLK_DATA_DIR: data };
delete env.ELECTRON_RUN_AS_NODE;
delete env.SIDEFOLK_DEV_URL;
const app = await electron.launch({ args: ["."], cwd: root, env });
const errors = [];
try {
  let page;
  for (let i = 0; i < 100; i++) {
    page = app
      .windows()
      .find((p) => p.url().includes("index.html") && !p.url().endsWith("#pet"));
    if (page) break;
    await new Promise((r) => setTimeout(r, 100));
  }
  page.on("pageerror", (e) => errors.push(e.message));
  await page.getByRole("heading", { name: "Meet Pip" }).waitFor();
  mkdirSync(join(root, "output/playwright"), { recursive: true });
  const shot = async (name) => {
    await page.screenshot({
      path: join(root, `output/playwright/design-${name}.png`),
    });
    assert.equal(
      await page.evaluate(
        () => document.documentElement.scrollWidth > innerWidth,
      ),
      false,
      "No horizontal document overflow",
    );
  };
  await page.waitForTimeout(700);
  assert.equal(
    await page.locator(".chat-scroll").evaluate((el) => el.scrollTop),
    0,
  );
  await shot("home");
  await page.getByRole("button", { name: "Pet studio", exact: true }).click();
  await page.getByRole("button", { name: "2D · Illustrated" }).click();
  for (const name of ["Moonbun", "Miso", "Ember", "Pebble", "Fern", "Boo"]) {
    await page.getByRole("button", { name: `Preview ${name}` }).click();
    await page.locator(".studio-stage button").click();
    assert.equal(await page.locator(".studio-stage .pet-heart").count(), 1);
  }
  await page.getByRole("button", { name: "Preview Miso" }).click();
  await page
    .getByRole("button", { name: "Little professor", exact: true })
    .click();
  await shot("studio");
  await page.getByRole("button", { name: "Make this my companion" }).click();
  await page.getByRole("button", { name: "Companion updated" }).waitFor();
  const state = await page.evaluate(() => window.sidefolk.snapshot());
  assert.equal(state.settings.petSpecies, "cat");
  assert.equal(state.settings.petStyle, "2d");
  assert.equal(state.settings.petAccessory, "glasses");
  assert.equal(state.settings.petName, "Pip");
  await page.getByRole("button", { name: "3D · Soft sculpt" }).click();
  await page.locator(".studio-stage canvas").waitFor();
  await page.waitForTimeout(500);
  await shot("studio-3d");
  for (const name of ["Moonbun", "Miso", "Ember", "Pebble", "Fern", "Boo"]) {
    await page.getByRole("button", { name: `Preview ${name}` }).click();
    await page
      .getByRole("button", { name: "Lo-fi buddy", exact: true })
      .click();
    await page.waitForTimeout(150);
    await shot(`3d-${name.toLowerCase()}`);
  }
  const disk = JSON.parse(
    (await import("node:fs")).readFileSync(join(data, "sidefolk.json"), "utf8"),
  );
  assert.equal(disk.settings.petAccessory, "glasses");
  assert.equal(disk.settings.petSpecies, "cat");
  await assert.rejects(() =>
    page.evaluate(() =>
      window.sidefolk.addItem({
        title: "Past reminder",
        kind: "reminder",
        dueAt: Date.now() - 1000,
      }),
    ),
  );
  await page.getByRole("button", { name: "Tasks", exact: true }).click();
  await page.getByRole("button", { name: "Add task", exact: true }).click();
  await page
    .getByRole("textbox", { name: "Task title" })
    .fill("Review the new pet studio");
  await shot("task-dialog");
  await page
    .getByRole("button", { name: "Create reminder", exact: true })
    .click();
  await page
    .getByRole("button", { name: "Complete Review the new pet studio" })
    .waitFor();
  await shot("tasks");
  await page.getByRole("button", { name: "Add task", exact: true }).click();
  await page.keyboard.press("Escape");
  assert.equal(await page.locator("dialog").count(), 0);
  for (const name of ["Memory", "Skills", "Workshop", "Settings"]) {
    await page.getByRole("button", { name, exact: true }).first().click();
    await shot(name.toLowerCase());
  }
  await page.getByRole("button", { name: "Quick actions" }).click();
  await page
    .getByRole("textbox", { name: "Search quick actions" })
    .fill("studio");
  await page
    .locator("dialog")
    .getByRole("button", { name: "Pet studio" })
    .click();
  await app.evaluate(({ BrowserWindow }) =>
    BrowserWindow.getAllWindows()
      .find((w) => w.getTitle() === "Sidefolk")
      .setSize(980, 700),
  );
  await shot("compact-studio");
  await page
    .getByRole("button", { name: "Your companion", exact: true })
    .click();
  await shot("compact-home");
  await page.evaluate(() => window.sidefolk.petControl("show"));
  await page.waitForTimeout(400);
  const pet = app.windows().find((p) => p.url().endsWith("#pet"));
  await pet.getByRole("button", { name: "Pet your cat companion" }).waitFor();
  await pet.screenshot({
    path: join(root, "output/playwright/design-desktop.png"),
  });
  assert.equal(
    (await page.evaluate(() => window.sidefolk.snapshot())).usage.turns,
    0,
  );
  assert.deepEqual(errors, []);
  console.log(
    "Design checks passed: six 2D pets, 3D preview, adoption, tasks, Escape, quick actions, compact layouts, desktop sync, zero AI calls.",
  );
} finally {
  await app.close();
  rmSync(data, { recursive: true, force: true });
}
