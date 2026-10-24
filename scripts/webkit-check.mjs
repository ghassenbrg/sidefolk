// Loads every view of the Sidefolk window and the overlay in WebKit, the engine the app runs
// on, and fails on page or console errors. Screenshots go to the folder given as the first
// argument (default: a temp folder) for a look at light and dark.
//
//   npm run web &                      # the browser preview with sample data
//   npx playwright install webkit      # once
//   npm run check:webkit [-- <screenshot dir>]

import assert from "node:assert/strict";
import { mkdtempSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { webkit } from "playwright";

const base = process.env.SIDEFOLK_WEB ?? "http://127.0.0.1:1420";
const out = process.argv[2] ?? mkdtempSync(join(tmpdir(), "sidefolk-webkit-"));
const views = [
  ["home", "/settings.html"],
  ["requests", "/settings.html?tab=requests"],
  ["review", "/settings.html?tab=review:codex-1"],
  ["reminders", "/settings.html?tab=reminders"],
  ["settings", "/settings.html?tab=settings"],
  ["setup", "/settings.html?tab=setup:start"],
  ["new-reminder", "/settings.html?tab=reminders:new"],
  ["notes", "/settings.html?tab=notes"],
  ["sessions", "/settings.html?tab=sessions"],
  ["notebook", "/settings.html?tab=notes:evaluation-h2-2026"],
];

const browser = await webkit.launch();
const failures = [];
const watch = (page, label) => {
  page.on("pageerror", (e) => failures.push(`${label}: ${e.message}`));
  page.on("console", (m) => m.type() === "error" && failures.push(`${label}: ${m.text()}`));
};

for (const scheme of ["light", "dark"]) {
  const page = await browser.newPage({ viewport: { width: 1040, height: 740 }, colorScheme: scheme });
  for (const [name, path] of views) {
    watch(page, `${scheme} ${name}`);
    await page.goto(base + path);
    await page.waitForTimeout(1200);
    if (!(await page.locator("h1").count())) failures.push(`${scheme} ${name}: no heading`);
    await page.screenshot({ path: join(out, `${scheme}-${name}.png`) });
    page.removeAllListeners("pageerror");
    page.removeAllListeners("console");
  }
  // Answering from the window shows "Sent" only after the pet confirms.
  watch(page, `${scheme} answer`);
  await page.goto(base + "/settings.html?tab=review:codex-1");
  await page.waitForTimeout(800);
  await page.getByRole("button", { name: "Allow once" }).click();
  await page.waitForTimeout(1200);
  const result = (await page.locator(".result").textContent()) ?? "";
  if (!result.includes("Sent to Codex")) failures.push(`${scheme} answer: "${result.trim()}"`);
  // Full access is off by default, shown on each session, and switches both ways.
  await page.goto(base + "/settings.html");
  const toggle = page.getByRole("button", { name: "Asks first" }).first();
  await toggle.click();
  await page.getByRole("button", { name: "Full access" }).first().waitFor();
  await page.getByRole("button", { name: "Full access" }).first().click();
  await page.getByRole("button", { name: "Asks first" }).nth(1).waitFor();
  // A note added in the window shows up first, and Delete offers Undo.
  await page.goto(base + "/settings.html?tab=notes:evaluation-h2-2026");
  await page.locator("#note-text").fill("Ran the accessibility audit.");
  await page.getByRole("button", { name: "Add note" }).click();
  await page.locator(".note").first().getByText("Ran the accessibility audit.").waitFor();
  await page.locator(".note").first().getByRole("button", { name: "Delete" }).click();
  await page.locator("#toast").getByRole("button", { name: "Undo" }).click();
  await page.locator(".note").first().getByText("Ran the accessibility audit.").waitFor();
  // Drafting with AI is explicit: it says what it sends, then shows the draft.
  await page.getByRole("button", { name: "Draft a summary…" }).click();
  await page.getByText("and nothing else", { exact: false }).waitFor();
  await page.getByRole("button", { name: "Draft with Claude Code" }).click();
  await page.getByRole("heading", { name: "Draft by Claude Code" }).waitFor();
  // A Spark added in the window shows up in the Sparks list with its color.
  await page.goto(base + "/settings.html?tab=sessions");
  await page.locator("#spark-folder").fill("web");
  await page.getByRole("button", { name: "Add Spark" }).click();
  await page.getByText("Spark · web", { exact: true }).waitFor();
  // The Tell bar confirms a plain command itself and never hands it to an AI tool.
  await page.goto(base + "/settings.html");
  await page.locator(".tell-input").fill("ls -la");
  assert.match((await page.locator(".tell-preview").textContent()) ?? "", /Run `ls -la` in your home folder/);
  await page.locator(".tell-input").press("Enter");
  await page.locator("#toast").getByRole("button", { name: "Run in terminal" }).click();
  await page.locator("#toast").getByText("Preview: nothing ran", { exact: false }).waitFor();
  // Repeat edits must survive saving, advancing, clearing, deleting and Undo.
  await page.goto(base + "/settings.html?tab=reminders");
  const add = page.getByRole("form", { name: "Add a reminder" });
  await add.getByLabel("What would you like to remember?").fill("every 2 weeks tomorrow at 9 to repeat acceptance");
  assert.equal(await add.getByLabel("Repeat", { exact: true }).inputValue(), "week");
  assert.equal(await add.getByLabel("Every how many?").inputValue(), "2");
  await add.getByRole("button", { name: "Add reminder" }).click();
  const reminder = page.locator("article.reminder").filter({ hasText: "repeat acceptance" });
  await reminder.getByRole("button", { name: "Open", exact: true }).click();
  await page.getByRole("heading", { name: "History", exact: true }).waitFor();
  await page.getByRole("button", { name: "Back to Reminders" }).click();
  await reminder.getByRole("button", { name: "Edit", exact: true }).click();
  let edit = page.getByRole("form", { name: "Edit repeat acceptance" });
  assert.equal(await edit.getByLabel("Repeat", { exact: true }).inputValue(), "week");
  await edit.getByLabel("Repeat", { exact: true }).selectOption("day");
  await edit.getByLabel("Every how many?").fill("1");
  const originalDate = await edit.getByLabel("Date", { exact: true }).inputValue();
  await edit.getByRole("button", { name: "Save changes" }).click();
  await reminder.getByRole("button", { name: "Mark complete" }).click();
  await reminder.getByRole("button", { name: "Edit", exact: true }).click();
  edit = page.getByRole("form", { name: "Edit repeat acceptance" });
  assert.notEqual(await edit.getByLabel("Date", { exact: true }).inputValue(), originalDate);
  await edit.getByLabel("Repeat", { exact: true }).selectOption("");
  await edit.getByRole("button", { name: "Save changes" }).click();
  assert.equal((await reminder.innerText()).includes("then every"), false);
  await reminder.getByRole("button", { name: "Delete", exact: true }).click();
  await page.locator("#toast").getByRole("button", { name: "Undo" }).click();
  await reminder.getByRole("button", { name: "Edit", exact: true }).click();
  assert.equal(await page.getByRole("form", { name: "Edit repeat acceptance" }).getByLabel("Repeat", { exact: true }).inputValue(), "");
  await page.close();
}

const overlay = await browser.newPage({ viewport: { width: 1100, height: 800 } });
watch(overlay, "overlay");
await overlay.goto(base + "/?zoom=1.4");
await overlay.waitForTimeout(2500);
await overlay.keyboard.press("5");
await overlay.waitForTimeout(1200);
const card = (await overlay.locator(".bubble.urgent").first().innerText().catch(() => "")).replace(/\s+/g, " ");
for (const part of ["Work session", "Run a command?", "Command", "Folder", "Decline", "Allow once"])
  if (!card.includes(part)) failures.push(`overlay permission card is missing "${part}"`);
await overlay.screenshot({ path: join(out, "overlay.png") });
// "Allow everything from this session" turns on full access; a risky command still asks.
await overlay.getByRole("button", { name: "Allow everything from this session" }).click();
await overlay.waitForTimeout(600);
await overlay.keyboard.press("5");
await overlay.getByText("Full access is on, but this one is hard to undo", { exact: false }).waitFor();
// Browser key r creates a real in-memory reminder; Undo must remove it from the list.
await overlay.goto(base + "/?zoom=1.4");
await overlay.waitForTimeout(1200);
await overlay.keyboard.press("r");
await overlay.getByRole("button", { name: "Save", exact: true }).click();
await overlay.getByRole("button", { name: "Undo", exact: true }).click();
await overlay.keyboard.press("c");
await overlay.locator(".bubble input").fill("reminders");
await overlay.locator(".bubble input").press("Enter");
await overlay.getByText("No reminders", { exact: true }).waitFor();
// A note to a notebook that doesn't exist yet offers to start it, then confirms with Undo.
await overlay.goto(base + "/?zoom=1.4");
await overlay.waitForTimeout(1200);
await overlay.keyboard.press("c");
await overlay.locator(".bubble input").fill("note for evaluation: shipped the login migration");
await overlay.locator(".bubble input").press("Enter");
await overlay.getByRole("button", { name: "Start evaluation" }).click();
await overlay.getByText("Noted in evaluation.", { exact: true }).waitFor();
// A plain command is recognized locally and only runs after the confirmation card.
await overlay.goto(base + "/?zoom=1.4");
await overlay.waitForTimeout(1200);
await overlay.keyboard.press("c");
await overlay.locator(".bubble input").fill("run npm test in api");
await overlay.locator(".bubble input").press("Enter");
const run = overlay.locator(".bubble").filter({ hasText: "Run this in your terminal?" });
await run.waitFor();
const runText = (await run.innerText()).replace(/\s+/g, " ");
for (const part of ["npm test", "~/git/api", "Cancel", "Run in terminal"])
  if (!runText.includes(part)) failures.push(`overlay run card is missing "${part}"`);
await overlay.waitForTimeout(800);
await overlay.screenshot({ path: join(out, "overlay-run.png") });
await run.getByRole("button", { name: "Run in terminal" }).click();
await overlay.getByText("Preview: nothing ran", { exact: false }).waitFor();
// "give api a spark" puts a second companion on the desktop with the project under its feet.
await overlay.goto(base + "/?zoom=1.4");
await overlay.waitForTimeout(1200);
await overlay.keyboard.press("c");
await overlay.locator(".bubble input").fill("give api a spark");
await overlay.locator(".bubble input").press("Enter");
await overlay.locator(".worker-badge", { hasText: "api" }).waitFor();
if ((await overlay.locator(".pip").count()) !== 2) failures.push("overlay: a Spark didn't join Pip");
await overlay.waitForTimeout(600);
await overlay.screenshot({ path: join(out, "overlay-spark.png") });
// Starting a session shows the folder and the permission mode before anything starts.
await overlay.goto(base + "/?zoom=1.4");
await overlay.waitForTimeout(1200);
await overlay.keyboard.press("c");
await overlay.locator(".bubble input").fill("start a claude session in api");
await overlay.locator(".bubble input").press("Enter");
const start = overlay.locator(".bubble").filter({ hasText: "Start Claude Code here?" });
await start.waitFor();
for (const part of ["~/git/api", "Asks first", "Start with full access"]) if (!(await start.innerText()).includes(part)) failures.push(`start card is missing "${part}"`);
await start.getByRole("button", { name: "Start Claude Code" }).click();
await overlay.getByText("Preview: nothing ran", { exact: false }).waitFor();
await browser.close();

console.log(`screenshots: ${out}`);
if (failures.length) {
  console.error(failures.join("\n"));
  process.exit(1);
}
console.log("WebKit: every view loaded without errors");
