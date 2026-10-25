// P5-specific regressions and 150px character checks. Browser preview only; no native calls.
import assert from "node:assert/strict";
import { mkdirSync } from "node:fs";
import { join } from "node:path";
import { webkit } from "playwright";
const base = process.env.SIDEFOLK_WEB ?? "http://127.0.0.1:1420";
const out = process.argv[2] ?? "/tmp/sidefolk-p5-characters";
mkdirSync(out, { recursive: true });
const browser = await webkit.launch();
const page = await browser.newPage({ viewport: { width: 860, height: 700 } });
const failures = [];
page.on("pageerror", (error) => failures.push(error.message));
page.on("console", (message) => { if (message.type() === "error") failures.push(message.text()); });
try {
  await page.goto(base + "/settings.html?waiting&tab=setup:start");
  assert.equal(await page.getByRole("button", { name: "Continue", exact: true }).isDisabled(), true);
  await page.getByRole("button", { name: "Set a two-minute reminder" }).click();
  await page.getByText(/^Saved for .*stretch/).waitFor();
  await page.getByRole("button", { name: "Continue", exact: true }).click();
  await page.getByRole("button", { name: "Continue", exact: true }).click();
  const finish = page.getByRole("button", { name: "Start using Sidefolk" });
  assert.equal(await finish.isDisabled(), true);
  await page.getByText(/I’ll wait for its first event/).waitFor();
  await page.evaluate(async () => {
    const api = performance.getEntriesByType("resource").find((x) => x.name.includes("/src/dashboard/api.ts"));
    await (await import(api.name)).invoke("preview_claude_event");
  });
  await page.getByText("A real session reached Sidefolk. You're ready.", { exact: true }).waitFor();
  assert.equal(await finish.isDisabled(), false);
  await finish.click();
  await page.getByRole("heading", { name: "Today", exact: true }).waitFor();
  // Explicit skip also completes setup without inventing a live connection.
  await page.goto(base + "/settings.html?waiting&tab=setup:start");
  await page.getByRole("button", { name: "Set a two-minute reminder" }).click();
  await page.getByRole("button", { name: "Continue", exact: true }).click();
  await page.getByRole("button", { name: "Continue", exact: true }).click();
  await page.getByRole("button", { name: "Skip for now" }).click();
  await page.getByRole("heading", { name: "Today", exact: true }).waitFor();

  await page.goto(base + "/settings.html?tab=settings:privacy");
  await page.getByRole("button", { name: "Clear history…" }).click();
  const dialog = page.getByRole("dialog", { name: "Clear session history?" });
  await dialog.getByText(/cannot be undone/).waitFor();
  await dialog.getByRole("button", { name: "Cancel" }).click();
  assert.equal(await dialog.count(), 0);
  await page.getByRole("button", { name: "Clear history…" }).click();
  await dialog.getByRole("button", { name: "Clear history", exact: true }).click();
  await page.locator("#toast").getByText("Session history cleared.", { exact: true }).waitFor();
  await page.getByRole("button", { name: "Preview report…" }).click();
  const report = page.getByRole("dialog", { name: "Problem report" });
  const reportText = report.getByRole("textbox", { name: "Problem report" });
  assert.equal(await reportText.getAttribute("readonly"), "");
  assert.ok((await reportText.inputValue()).length > 0);
  await report.getByRole("button", { name: "Cancel", exact: true }).click();

  // A failed Undo stays on the stack and is retried; busy actions cannot run twice.
  const feedback = await page.evaluate(async () => {
    const { Feedback } = await import("/src/dashboard/feedback.ts");
    const root = document.createElement("div"); document.body.append(root);
    const feedback = new Feedback(root);
    let fail = true; let calls = 0;
    feedback.show("Note deleted.", { label: "Undo", run: async () => { calls++; if (fail) throw new Error("EACCES private_path"); } });
    await feedback.latest();
    const kept = root.textContent.includes("Undo") && !root.textContent.includes("private_path");
    fail = false;
    await Promise.all([feedback.latest(), feedback.latest()]);
    const cleared = !root.textContent;
    root.remove();
    return { kept, cleared, calls };
  });
  assert.deepEqual(feedback, { kept: true, cleared: true, calls: 2 });

  await page.goto(base + "/?zoom=1");
  await page.locator(".pip").waitFor();
  await page.keyboard.press("c");
  const input = page.locator(".bubble input");
  await input.fill("Unfinished reminder");
  await page.evaluate(() => window.sidefolk.companion.openPrompt());
  assert.equal(await input.inputValue(), "Unfinished reminder");
  await input.fill("");
  await page.keyboard.press("Tab");
  await page.waitForTimeout(250);
  assert.equal(await input.isVisible(), true, "Tab to a suggestion must not dismiss Quick add");
  await page.evaluate(() => window.sidefolk.companion.pet.bubble.dismissPrompt());
  const focus = await page.evaluate(() => {
    const bubble = window.sidefolk.companion.pet.bubble;
    let answered = 0;
    bubble.show({ id: "focus-test", who: "Claude · api", title: "Review this operation", choices: [{ label: "Decline", value: "deny" }, { label: "Allow once", value: "allow", primary: true }], urgent: true, onChoose: () => answered++ });
    bubble.focusCard();
    return new Promise((resolve) => requestAnimationFrame(() => resolve({ root: document.activeElement === bubble.root, answered })));
  });
  assert.deepEqual(focus, { root: true, answered: 0 });

  const restored = await page.evaluate(() => {
    const agents = window.sidefolk.companion.pet.agents;
    let notifications = 0;
    const onEvent = agents.onEvent, onDone = agents.onDone;
    agents.onEvent = () => notifications++;
    agents.onDone = () => notifications++;
    const at = Date.now() - 1000;
    const base = { at, source: "claude", session: "restored", cwd: "/tmp/restored", project: "/tmp/restored" };
    agents.handle({ ...base, kind: "prompt", detail: "First request" }, true);
    agents.handle({ ...base, kind: "waiting", detail: "" }, true);
    const live = agents.list.find((s) => s.id === "restored");
    agents.handle({ ...base, kind: "done", detail: "" }, true);
    const outcome = agents.outcomes.get(base.project);
    agents.onEvent = onEvent; agents.onDone = onDone;
    return { notifications, at: live.at, firstPrompt: outcome.firstPrompt };
  });
  assert.equal(restored.notifications, 0, "Restoring native state must not replay notices or Log it cards");
  assert.equal(restored.firstPrompt, "First request");
  assert.ok(restored.at > 0);

  // Reminder folds keep the request and counted note, without choosing or re-nagging.
  await page.clock.install();
  await page.evaluate(() => {
    const companion = window.sidefolk.companion;
    companion.pet.bubble.close("focus-test");
    companion.request({ id: "fold-test", who: "Pip", title: "Folded reminder", meta: { kind: "reminder", count: "2" }, choices: [{ label: "Done", value: "done" }], onChoose: () => { throw Error("Fold must not choose"); } });
  });
  await page.clock.fastForward(120_001);
  await page.clock.runFor(250);
  assert.equal(await page.evaluate(() => window.sidefolk.companion.status().waiting.some((w) => w.id === "fold-test")), true);
  assert.equal(await page.getByText("Folded reminder", { exact: true }).count(), 0);
  const folded = await page.evaluate(() => {
    const pet = window.sidefolk.companion.pet;
    pet.frame(performance.now() + 1000);
    return { held: pet.heldNotes, open: pet.bubble.open.map((c) => c.id), hud: pet.hud.textContent };
  });
  assert.equal(folded.held, 2);
  assert.deepEqual(folded.open, []);
  await page.locator(".hud").getByText("Needs you · 2 reminders", { exact: true }).waitFor();
  await page.clock.resume();
  // Both existing characters at their shipped 150px size, on three wallpapers.
  await page.setViewportSize({ width: 480, height: 300 });
  for (const look of ["pip", "spark"]) for (const [wall, color, theme] of [["light", "#f7f3ea", "light"], ["mid", "#858581", "light"], ["dark", "#191c22", "dark"]]) {
    await page.goto(`${base}/?zoom=1&look=${look}`);
    await page.locator(".pip").waitFor();
    await page.evaluate(({ color, theme }) => {
      document.body.style.background = color;
      document.documentElement.dataset.theme = theme;
      const pet = window.sidefolk.companion.pet;
      pet.mind.x = 240;
      pet.mind.react("puzzled", Infinity);
    }, { color, theme });
    await page.waitForTimeout(400);
    assert.equal(await page.locator(".pip-light").isVisible(), false, "Puzzled must not imply agent activity");
    assert.match(await page.locator(".pip").getAttribute("aria-label"), /Idle/);
    await page.screenshot({ path: join(out, `${look}-puzzled-${wall}-150px.png`) });
    await page.evaluate(() => {
      const pet = window.sidefolk.companion.pet;
      pet.mind.calm = true; pet.view.still = true;
      pet.mind.react("wave", 1);
    });
    await page.waitForTimeout(50);
    assert.equal(await page.locator(".pip-body img").evaluateAll((images) => images.filter((x) => !x.hidden).length), 1, "Reduced motion changes frames immediately");
  }
  assert.deepEqual(failures, []);
  console.log(`WebKit P5: setup gate, privacy, Undo failures, keyboard and six character checks passed; ${out}`);
} finally { await browser.close(); }
