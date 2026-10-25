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
  ["review", "/settings.html?tab=review:claude-1"],
  ["reminders", "/settings.html?tab=reminders"],
  ["settings", "/settings.html?tab=settings"],
  ["appearance", "/settings.html?tab=settings:appearance"],
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
  const context = await browser.newContext({ viewport: { width: 1040, height: 740 }, colorScheme: scheme, timezoneId: "Asia/Tokyo" });
  const page = await context.newPage();
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
  await page.goto(base + "/settings.html?tab=review:claude-1");
  await page.waitForTimeout(800);
  await page.getByRole("button", { name: "Allow once" }).click();
  await page.waitForTimeout(1200);
  const result = (await page.locator(".result").textContent()) ?? "";
  if (!result.includes("Sent to Claude")) failures.push(`${scheme} answer: "${result.trim()}"`);
  // A long operation can be allowed only after it was scrolled to its end (V1-D7).
  await page.goto(base + "/settings.html?longrequest&tab=review:claude-2");
  const allowLong = page.getByRole("button", { name: "Allow once" });
  await allowLong.waitFor();
  if (!(await allowLong.isDisabled())) failures.push(`${scheme} review: Allow on before the operation was read`);
  await page.evaluate(() => document.querySelectorAll(".facts.full code").forEach((code) => (code.scrollTop = code.scrollHeight)));
  await page.waitForTimeout(200);
  if (await allowLong.isDisabled()) failures.push(`${scheme} review: Allow still off after reading to the end`);
  // No session has a "full access" switch: Sidefolk never answers for a session (V1-D10).
  await page.goto(base + "/settings.html?tab=sessions");
  await page.getByRole("heading", { name: "Running" }).waitFor();
  if (await page.getByRole("button", { name: /Asks first|Full access/ }).count()) failures.push("sessions: a full access switch is back");
  // A note added in the window shows up first, and Delete offers Undo.
  await page.goto(base + "/settings.html?tab=notes:evaluation-h2-2026");
  await page.locator("#note-text").fill("Ran the accessibility audit.");
  await page.getByRole("button", { name: "Add note" }).click();
  await page.locator(".note").first().getByText("Ran the accessibility audit.").waitFor();
  await page.locator(".note").first().getByRole("button", { name: "Delete" }).click();
  await page.locator("#toast").getByRole("button", { name: "Undo" }).click();
  await page.locator(".note").first().getByText("Ran the accessibility audit.").waitFor();
  // Incoming companion notes preserve both capture and an unfinished entry edit.
  await page.locator("#note-text").fill("Unfinished capture");
  await page.locator(".note").first().getByRole("button", { name: "Edit", exact: true }).click();
  await page.getByRole("textbox", { name: "Edit note" }).fill("Unfinished edit");
  await page.evaluate(async () => {
    // Vite may version module URLs after an edit; use the page's actual API module.
    const api = performance.getEntriesByType("resource").find((entry) => entry.name.includes("/src/dashboard/api.ts"));
    if (!api) throw new Error("Preview API module was not loaded");
    const { invoke } = await import(api.name);
    await invoke("add_note", { notebook: "evaluation-h2-2026", text: "Arrived from companion", date: "2026-10-24", project: null });
  });
  await page.waitForTimeout(200);
  assert.equal(await page.locator("#note-text").inputValue(), "Unfinished capture");
  assert.equal(await page.getByRole("textbox", { name: "Edit note" }).inputValue(), "Unfinished edit");
  await page.locator(".note.editing").getByRole("button", { name: "Cancel" }).click();
  await page.getByText("Arrived from companion", { exact: true }).waitFor();
  await page.locator("#note-text").fill("");
  // Labs: starting sessions is off by default; turned on, New session offers a folder and the
  // tool's own mode, off by default.
  await page.goto(base + "/settings.html?tab=sessions");
  if (await page.getByRole("button", { name: "New session", exact: true }).count()) failures.push("sessions: New session shows with Labs off");
  await page.goto(base + "/settings.html?tab=settings:general");
  await page.getByRole("switch", { name: "Start sessions" }).check();
  await page.locator("#toast").getByText("Saved.", { exact: true }).waitFor();
  // The preview keeps settings in the page, so stay in it.
  await page.getByRole("button", { name: "Back to Sidefolk" }).click();
  await page.locator("nav").getByRole("button", { name: "Sessions" }).click();
  await page.getByRole("button", { name: "New session", exact: true }).click();
  await page.locator("#new-session-folder").fill("");
  await page.getByRole("dialog").getByRole("button", { name: "Browse…" }).click();
  assert.equal(await page.locator("#new-session-folder").inputValue(), "/Users/you/git/api");
  assert.equal(await page.locator("#new-session-full").isChecked(), false);
  await page.getByRole("dialog").getByRole("button", { name: "Cancel" }).click();
  // Your companion is Pip or Spark, always both (DECISIONS #41).
  await page.goto(base + "/settings.html?tab=settings:companion");
  if ((await page.locator(".crew-choice").count()) !== 2) failures.push("settings: Pip and Spark aren't both offered");
  await page.locator("label[for=look-spark]").click();
  await page.locator("#toast").getByText("Your companion is Spark now.", { exact: true }).waitFor();
  // English never becomes a command; with Labs → Commands on, "$ …" is confirmed in the window.
  await page.goto(base + "/settings.html");
  await page.locator(".tell-input").fill("ls -la");
  if (/Run `/.test((await page.locator(".tell-preview").textContent()) ?? "")) failures.push("tell bar: plain text was offered as a command");
  await page.goto(base + "/settings.html?tab=settings:general");
  await page.getByRole("switch", { name: "Commands" }).check();
  await page.locator("#toast").getByText("Saved.", { exact: true }).waitFor();
  await page.getByRole("button", { name: "Back to Sidefolk" }).click();
  await page.locator(".tell-input").fill("$ ls -la");
  assert.match((await page.locator(".tell-preview").textContent()) ?? "", /Run `ls -la` in your home folder/);
  await page.locator(".tell-input").press("Enter");
  await page.getByRole("dialog").getByRole("button", { name: "Run in terminal" }).click();
  await page.locator("#toast").getByText("Preview: nothing ran", { exact: false }).waitFor();
  // Repeat edits must survive saving, advancing, clearing, deleting and Undo.
  await page.goto(base + "/settings.html?tab=reminders");
  await page.getByRole("button", { name: "Add reminder", exact: true }).click();
  const add = page.getByRole("form", { name: "Add a reminder" });
  await add.getByLabel("What would you like to remember?").fill("every 2 weeks tomorrow at 9 to repeat acceptance");
  assert.equal(await add.getByLabel("Repeat", { exact: true }).inputValue(), "week");
  assert.equal(await add.getByLabel("Every how many?").inputValue(), "2");
  await add.getByRole("button", { name: "Save reminder" }).click();
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
  // Theme overrides persist after reload, follow OS changes only in System,
  // and propagate to another surface without changing that surface's OS appearance.
  await page.goto(base + "/settings.html?tab=settings:appearance");
  await page.getByRole("radio", { name: "Dark", exact: true }).check();
  await page.waitForFunction(() => document.documentElement.dataset.theme === "dark");
  await page.reload();
  await page.getByRole("radio", { name: "Dark", exact: true }).waitFor();
  assert.equal(await page.getByRole("radio", { name: "Dark", exact: true }).isChecked(), true);
  await page.emulateMedia({ colorScheme: "light" });
  assert.equal(await page.locator("html").getAttribute("data-theme"), "dark");
  const other = await page.context().newPage();
  await other.goto(base + "/?zoom=1.4");
  await other.waitForFunction(() => document.documentElement.dataset.theme === "dark");
  await page.getByRole("radio", { name: "Light", exact: true }).check();
  await other.waitForFunction(() => document.documentElement.dataset.theme === "light");
  await page.getByRole("radio", { name: "System", exact: true }).check();
  await page.waitForFunction(() => !document.documentElement.dataset.theme);
  await page.emulateMedia({ colorScheme: "dark" });
  assert.equal(await page.evaluate(() => getComputedStyle(document.documentElement).getPropertyValue("--canvas").trim()), "#191c22");
  await page.emulateMedia({ colorScheme: "light" });
  assert.equal(await page.evaluate(() => getComputedStyle(document.documentElement).getPropertyValue("--canvas").trim()), "#f7f3ea");
  await other.close();
  // Search jumps to the owning category; all settings remain reachable.
  await page.getByRole("searchbox", { name: "Search settings" }).fill("dark");
  await page.getByRole("button", { name: "Appearance Appearance", exact: true }).click();
  await page.getByRole("radio", { name: "System", exact: true }).waitFor();
  for (const section of ["general", "companion", "sound", "tools", "privacy", "accessibility", "help"]) {
    await page.goto(base + `/settings.html?tab=settings:${section}`);
    await page.locator(".settings-content h1").waitFor();
    assert.equal(await page.locator(".settings-content .settings-group").count() > 0, true);
  }
  // The command review remains pending until explicitly dismissed or run.
  await page.goto(base + "/settings.html?tab=settings:general");
  await page.getByRole("switch", { name: "Commands" }).check();
  await page.getByRole("button", { name: "Back to Sidefolk" }).click();
  await page.locator(".tell-input").fill("$ ls -la");
  await page.locator(".tell-input").press("Enter");
  await page.getByRole("dialog").waitFor();
  await page.waitForTimeout(4500);
  assert.equal(await page.getByRole("dialog").isVisible(), true);
  await page.keyboard.press("Escape");
  assert.equal(await page.getByRole("dialog").count(), 0);
  // The shortened setup completes a useful local action without an AI connection.
  await page.goto(base + "/settings.html?tab=setup:start");
  await page.getByRole("button", { name: "Set a two-minute reminder" }).click();
  await page.getByText("Saved. Your companion will remind you to stretch in two minutes.", { exact: true }).waitFor();
  await page.getByRole("button", { name: "Continue", exact: true }).click();
  await page.getByRole("heading", { name: "By your side." }).waitFor();
  await page.getByRole("button", { name: "Continue", exact: true }).click();
  await page.getByRole("button", { name: "Start using Sidefolk" }).click();
  await page.getByRole("heading", { name: "Today", exact: true }).waitFor();
  // Narrow layouts retain all controls, including larger text and settings search.
  await page.setViewportSize({ width: 520, height: 740 });
  for (const target of ["today", "reminders", "notes:evaluation-h2-2026", "sessions", "settings:appearance", "review:claude-1"]) {
    await page.goto(base + `/settings.html?tab=${target}`);
    await page.locator("main h1:visible").first().waitFor();
    await page.evaluate(() => document.documentElement.classList.add("large-text"));
    assert.equal(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth && document.querySelector("main").scrollWidth <= document.querySelector("main").clientWidth), true, `narrow overflow in ${target}`);
  }
  await page.goto(base + "/settings.html?tab=settings:appearance");
  await page.getByRole("radio", { name: "System", exact: true }).waitFor();
  await page.screenshot({ path: join(out, `${scheme}-narrow-appearance.png`) });
  await context.close();
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
// A request is only ever answered by the user: there is no "Allow everything" (V1-D8, V1-D10).
if (await overlay.getByRole("button", { name: /Allow everything/ }).count()) failures.push("overlay: Allow everything is back");
// A request longer than the card is reviewed whole in the window before it can be allowed (V1-D7).
await overlay.goto(base + "/?zoom=1.4");
await overlay.waitForTimeout(1200);
await overlay.keyboard.press("8");
const long = overlay.locator(".bubble.urgent").first();
await long.getByRole("button", { name: "Review all of it" }).waitFor();
if (await long.getByRole("button", { name: "Allow once" }).count()) failures.push("overlay: Allow offered on a request longer than its card");
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
await overlay.locator(".bubble input").fill("$ npm test in api");
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
// English never reaches the terminal card, even when it starts with a command's name.
await overlay.goto(base + "/?zoom=1.4");
await overlay.waitForTimeout(1200);
await overlay.keyboard.press("c");
await overlay.locator(".bubble input").fill("make coffee");
await overlay.locator(".bubble input").press("Enter");
await overlay.waitForTimeout(600);
if (await overlay.getByText("Run this in your terminal?").count()) failures.push("overlay: plain English was offered as a command");
// Starting a session shows the folder and the permission mode before anything starts.
await overlay.goto(base + "/?zoom=1.4");
await overlay.waitForTimeout(1200);
await overlay.keyboard.press("c");
await overlay.locator(".bubble input").fill("start a claude session in api");
await overlay.locator(".bubble input").press("Enter");
const start = overlay.locator(".bubble").filter({ hasText: "Start Claude Code here?" });
await start.waitFor();
for (const part of ["~/git/api", "Asks you first", "Start in auto mode"]) if (!(await start.innerText()).includes(part)) failures.push(`start card is missing "${part}"`);
await start.getByRole("button", { name: "Start Claude Code" }).click();
await overlay.getByText("Preview: nothing ran", { exact: false }).waitFor();
await browser.close();

console.log(`screenshots: ${out}`);
if (failures.length) {
  console.error(failures.join("\n"));
  process.exit(1);
}
console.log("WebKit: every view loaded without errors");
