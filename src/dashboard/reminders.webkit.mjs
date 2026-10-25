// Reminder-only browser contracts. Start npm run web, then node src/dashboard/reminders.webkit.mjs.
// Uses an isolated in-memory command boundary; never launches the desktop or touches user data.
import assert from "node:assert/strict";
import { webkit } from "playwright";

const base = process.env.SIDEFOLK_WEB ?? "http://127.0.0.1:1420";
const browser = await webkit.launch();
try {
  const page = await browser.newPage({ viewport: { width: 640, height: 480 }, timezoneId: "Asia/Tokyo" });
  const errors = [];
  page.on("pageerror", (error) => errors.push(error.message));
  await page.route("**/reminder-harness", (route) => route.fulfill({ contentType: "text/html", body: '<link rel="stylesheet" href="/src/dashboard/window.css"><main></main>' }));
  await page.route("**/src/dashboard/api.ts*", (route) => route.fulfill({ contentType: "text/javascript", body: 'export const invoke = (...args) => window.reminderInvoke(...args);' }));
  await page.goto(`${base}/reminder-harness`);
  await page.clock.install({ time: new Date("2026-10-25T05:32:15Z") });
  await page.evaluate(async () => {
    const { addReminder, addEventReminder, renderReminders } = await import("/src/dashboard/reminders.ts");
    window.calls = []; window.saved = 0; window.fail = false;
    const due = new Date("2026-10-26T00:00:30Z").getTime();
    const repeating = { id: "weekly", text: "Weekly plan", due, anchor: due, occurrence: due, repeat: { every: "week", n: 1 }, history: [], created: due - 1000, from: "you", done: false, fired: false, project: "" };
    const state = { status: { pets: [{ sessions: [{ project: "/git/api" }], outcomes: [] }] }, reminders: [repeating], settings: { snooze_mins: 30 } };
    window.reminderInvoke = async (command, args) => {
      window.calls.push({ command, args });
      if (command === "notification_status") return { permission: "denied" };
      if (command === "resolve_folder") return { path: args.folder, label: args.folder };
      if (command === "resolve_event_project") return args.path;
      if (command === "add_event_reminder") { if (window.fail) throw "disk full"; return { id: "event", ...args, due: 0, created: Date.now(), done: false, fired: false, event: { expires: Date.now() + 86_400_000 } }; }
      if (command === "add_reminder") { if (window.fail) throw "disk full"; return { id: "new", ...args }; }
      if (command === "update_reminder") return true;
      if (command === "answer_reminder") return true;
    };
    const app = { state, live: () => {}, redraw: () => {}, refresh: async () => {}, toast: () => {}, go: () => {} };
    window.showList = () => document.querySelector("main").replaceChildren(renderReminders(app));
    window.create = () => addReminder(app, "", () => { window.saved++; });
    window.eventCreate = () => addEventReminder(app, "when api finishes", () => { window.saved++; });
    window.seedEvents = () => { state.reminders = [
      { ...repeating, id: "waiting", text: "Waiting api", project: "/git/api", repeat: null, due: 0, event: { expires: Date.now() + 86_400_000 } },
      { ...repeating, id: "expired", text: "Expired api", project: "/git/api", repeat: null, due: 0, event: { expires: Date.now() - 1000, expiredAt: Date.now() } },
    ]; window.showList(); };
    window.seedCompleted = () => { state.reminders = Array.from({ length: 8 }, (_, i) => ({ ...repeating, id: `completed-${i}`, text: `Completed ${i}`, history: [{ action: "Completed", at: due, due, text: `Occurrence ${i}` }] })); window.showList(); };
    window.showList();
  });
  const calls = (command) => page.evaluate((command) => window.calls.filter((call) => call.command === command), command);
  await page.evaluate(() => window.create());
  assert.equal(await page.locator("#new-text").evaluate((el) => el === document.activeElement), true);
  await page.locator("#new-text").fill("Water plants");
  await page.locator("#new-repeat").selectOption("week");
  await page.getByLabel("Monday", { exact: true }).check();
  await page.getByLabel("Thursday", { exact: true }).check();
  await page.getByLabel("Sunday", { exact: true }).uncheck();
  assert.match(await page.locator(".sheet .hint").first().textContent(), /Monday and Thursday/);
  assert.match(await page.locator(".sheet").textContent(), /Reminders show only while Sidefolk is running\./);
  await page.evaluate(() => { window.fail = true; });
  await page.getByRole("button", { name: "Save reminder", exact: true }).click();
  await page.getByText("Your disk is full; free some space and try again.", { exact: true }).waitFor();
  assert.equal(await page.evaluate(() => window.saved), 0);
  assert.equal(await page.locator("#new-text").inputValue(), "Water plants");
  await page.evaluate(() => { window.fail = false; });
  await page.getByRole("button", { name: "Save reminder", exact: true }).click();
  await page.locator("dialog").waitFor({ state: "detached" });
  assert.equal(await page.evaluate(() => window.saved), 1);
  assert.deepEqual((await calls("add_reminder")).at(-1).args.repeat.days, [1, 4]);

  await page.evaluate(() => window.create());
  await page.locator("#new-text").fill("Leap birthday");
  await page.locator("#new-date").fill("2028-02-29");
  await page.locator("#new-repeat").selectOption("year");
  await page.getByRole("button", { name: "Save reminder", exact: true }).click();
  await page.getByText("Confirm the February 28 policy for non-leap years.", { exact: true }).waitFor();
  await page.getByLabel("Use February 28 in non-leap years (February 29 in leap years).").check();
  await page.getByRole("button", { name: "Save reminder", exact: true }).click();
  await page.locator("dialog").waitFor({ state: "detached" });
  assert.equal((await calls("add_reminder")).at(-1).args.repeat.every, "year");

  const more = page.getByRole("button", { name: "More actions for Weekly plan", exact: true });
  await more.click();
  await page.getByRole("menuitem", { name: "Edit Weekly plan", exact: true }).click();
  await page.getByLabel("This one", { exact: true }).check();
  assert.equal(await page.locator("#edit-weekly-repeat").isDisabled(), true);
  await page.locator("#edit-weekly-text").fill("Guest plan");
  await page.getByRole("button", { name: "Save changes", exact: true }).click();
  await page.locator("dialog").waitFor({ state: "detached" });
  const change = (await calls("update_reminder")).at(-1).args.change;
  assert.equal(change.scope, "this_one");
  assert.equal(change.text, "Guest plan");
  assert.equal(change.expected_occurrence, new Date("2026-10-26T00:00:30Z").getTime());
  assert.equal("due" in change, false, "title edits preserve seconds and the existing delivery time");
  assert.equal("repeat" in change, false);
  assert.equal("clear_repeat" in change, false);

  await more.click();
  await page.getByRole("menuitem", { name: "Edit Weekly plan", exact: true }).click();
  await page.getByLabel("This one", { exact: true }).check();
  await page.locator("#edit-weekly-date").fill("2026-10-27");
  await page.locator("#edit-weekly-time").fill("10:00");
  await page.getByRole("button", { name: "Save changes", exact: true }).click();
  await page.locator("dialog").waitFor({ state: "detached" });
  assert.equal((await calls("update_reminder")).at(-1).args.change.due, new Date("2026-10-27T01:00:00Z").getTime(), "This one may move to a day outside the series rule");
  await more.click();
  await page.getByRole("menuitem", { name: "Edit Weekly plan", exact: true }).click();
  await page.getByLabel("All future", { exact: true }).check();
  await page.locator("#edit-weekly-text").fill("All plans");
  await page.getByRole("button", { name: "Save changes", exact: true }).click();
  await page.locator("dialog").waitFor({ state: "detached" });
  const rename = (await calls("update_reminder")).at(-1).args.change;
  assert.equal(rename.scope, "all_future");
  assert.equal("repeat" in rename, false, "an implicit anchor weekday must not become a rule edit");
  assert.equal("due" in rename, false);

  await more.click();
  await page.getByRole("menuitem", { name: "Pick snooze time… Weekly plan", exact: true }).click();
  await page.locator("#snooze-date").fill("2026-10-24");
  await page.getByRole("button", { name: "Snooze", exact: true }).click();
  await page.getByText("Choose a date and time later than now.", { exact: true }).waitFor();
  assert.equal((await calls("answer_reminder")).length, 0);
  assert.match(await page.locator("#snooze-preview").textContent(), /Asia\/Tokyo/);
  await page.locator("#snooze-date").fill("2026-10-26");
  await page.locator("#snooze-time").fill("09:00");
  await page.getByRole("button", { name: "Snooze", exact: true }).click();
  await page.locator("dialog").waitFor({ state: "detached" });
  assert.equal((await calls("answer_reminder")).at(-1).args.until, new Date("2026-10-26T00:00:00Z").getTime());
  await more.click();
  await page.getByRole("menuitem", { name: "Delete… Weekly plan", exact: true }).click();
  assert.equal(await page.getByRole("button", { name: "Skip this occurrence", exact: true }).count(), 1);
  assert.equal(await page.getByRole("button", { name: "Delete entire series", exact: true }).count(), 1);
  await page.getByRole("button", { name: "Cancel", exact: true }).click();
  await page.evaluate(() => window.seedCompleted());
  await page.getByRole("button", { name: "Completed", exact: true }).click();
  await page.evaluate(() => window.showList());
  assert.equal(await page.locator("article.reminder.done").count(), 8);
  assert.equal(await page.getByRole("button", { name: "Occurrence 7", exact: true }).count(), 1);

  await page.evaluate(() => window.eventCreate());
  assert.match(await page.locator("dialog").textContent(), /When \/git\/api next finishes/);
  assert.equal(await page.locator('dialog input[type="date"]').count(), 0);
  const savedBeforeEvent = await page.evaluate(() => window.saved);
  await page.evaluate(() => { window.fail = true; });
  await page.getByRole("button", { name: "Save reminder", exact: true }).click();
  await page.getByText("Your disk is full; free some space and try again.", { exact: true }).waitFor();
  assert.equal(await page.evaluate(() => window.saved), savedBeforeEvent);
  await page.evaluate(() => { window.fail = false; });
  await page.getByRole("button", { name: "Save reminder", exact: true }).click();
  await page.locator("dialog").waitFor({ state: "detached" });
  assert.deepEqual((await calls("add_event_reminder")).at(-1).args, { text: "api finishes", project: "/git/api" });
  assert.equal(await page.evaluate(() => window.saved), savedBeforeEvent + 1);
  await page.evaluate(() => window.seedEvents());
  await page.getByRole("button", { name: "Upcoming", exact: true }).click();
  await page.evaluate(() => window.showList());
  assert.match(await page.locator(".reminder-list").textContent(), /When \/git\/api next finishes/);
  assert.match(await page.locator(".reminder-list").textContent(), /No reminder was sent/);
  assert.equal(await page.getByRole("button", { name: /^Mark .* complete/ }).count(), 0);

  // The overlay uses the same validated fields inside its measured and clickable card.
  await page.evaluate(async () => {
    const { Reminders, memoryStore } = await import("/src/reminders.ts");
    const { Bubble } = await import("/src/bubble.ts");
    const root = document.createElement("div"); document.body.append(root);
    const bubble = new Bubble(root);
    const store = memoryStore();
    window.overlayStore = store;
    const companion = { name: "Pip", pet: { name: "Pip", bubble, mind: { react: () => {} } }, request: (card) => bubble.show(card), closeRequest: (id) => bubble.close(id) };
    const reminders = new Reminders(companion, store);
    await store.add("Overlay call", Date.now() - 1000, null);
    await reminders.start();
  });
  await page.getByRole("button", { name: "One by one", exact: true }).click();
  await page.getByRole("button", { name: "Pick…", exact: true }).click();
  await page.locator("#snooze-date").fill("2026-10-24");
  await page.getByRole("button", { name: "Snooze", exact: true }).click();
  await page.getByText("Choose a date and time later than now.", { exact: true }).waitFor();
  await page.locator("#snooze-date").fill("2026-10-26");
  await page.locator("#snooze-time").fill("09:00");
  await page.getByRole("button", { name: "Snooze", exact: true }).click();
  assert.equal(await page.evaluate(async () => (await window.overlayStore.list())[0].due), new Date("2026-10-26T00:00:00Z").getTime());
  assert.deepEqual(errors, []);
  console.log("Reminder WebKit contracts passed (640×480; create/retry/callback, weekly/yearly, scopes, snooze on both surfaces, deletion, completed history, event confirmation/expiry).");
} finally { await browser.close(); }
