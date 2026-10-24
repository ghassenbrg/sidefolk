// Loads every view of the Sidefolk window and the overlay in WebKit, the engine the app runs
// on, and fails on page or console errors. Screenshots go to the folder given as the first
// argument (default: a temp folder) for a look at light and dark.
//
//   npm run web &                      # the browser preview with sample data
//   npx playwright install webkit      # once
//   npm run check:webkit [-- <screenshot dir>]

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
  ["crew", "/settings.html?tab=crew"],
  ["pet", "/settings.html?tab=crew:byte"],
  ["reminders", "/settings.html?tab=reminders"],
  ["settings", "/settings.html?tab=settings"],
  ["activity", "/settings.html?tab=activity"],
  ["welcome", "/settings.html?tab=welcome&welcome"],
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
await browser.close();

console.log(`screenshots: ${out}`);
if (failures.length) {
  console.error(failures.join("\n"));
  process.exit(1);
}
console.log("WebKit: every view loaded without errors");
