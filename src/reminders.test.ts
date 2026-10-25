import { afterEach, describe, expect, it, vi } from "vitest";
import type { Card } from "./bubble";
import type { Companion } from "./companion";
import { aboutWriting, memoryStore, Reminders, snoozeUntil } from "./reminders";

function fixture() {
  const cards = new Map<string, Card>();
  const bubble = { show: (card: Card) => cards.set(card.id, card), close: (id: string) => cards.delete(id), say: vi.fn(), prompt: vi.fn() };
  const closeRequest = vi.fn((id: string) => cards.delete(id));
  const companion = { name: "Pip", pet: { name: "Pip", bubble, mind: { react: vi.fn() } }, request: bubble.show, closeRequest } as unknown as Companion;
  const store = memoryStore();
  return { cards, bubble, store, closeRequest, reminders: new Reminders(companion, store) };
}

afterEach(() => { vi.clearAllTimers(); vi.useRealTimers(); });

describe("reminder delivery", () => {
  it("does not save before confirmation, and Undo removes the saved reminder", async () => {
    vi.useFakeTimers();
    const { reminders, cards, store } = fixture();
    await reminders.command("in 20 minutes to stretch", "remind");
    expect(await store.list()).toHaveLength(0);
    cards.get("reminder-preview")!.onChoose("save");
    await vi.advanceTimersByTimeAsync(0);
    const [r] = await store.list();
    expect(r.text).toBe("stretch");
    cards.get(`reminder-added-${r.id}`)!.onChoose("undo");
    await vi.advanceTimersByTimeAsync(0);
    expect(await store.list()).toHaveLength(0);
  });
  it("delivers missed reminders once and removes cards changed in the window", async () => {
    vi.useFakeTimers();
    const { reminders, cards, store, closeRequest } = fixture();
    const r = await store.add("overdue", Date.now() - 300_000, null);
    const request = vi.spyOn(cards, "set");
    await reminders.start();
    await vi.advanceTimersByTimeAsync(30_000);
    expect(request).toHaveBeenCalledTimes(1);
    expect(cards.get("away")!.title).toBe("While you were away: 1 reminder");
    expect(cards.get("away")!.lines![0]).toContain("Late · Was due");
    expect(cards.get("away")!.meta).toMatchObject({ kind: "reminder", count: "1" });
    await store.remove(r.id);
    await reminders.reload();
    expect(closeRequest).toHaveBeenCalledWith(`reminder-${r.id}`);
    expect(closeRequest).toHaveBeenCalledWith("away");
  });
});

describe("aboutWriting", () => {
  it.each(["note what I achieved this week", "write down the wins", "log the incident", "what I shipped for evaluation"])("offers a note for %s", (text) => expect(aboutWriting(text)).toBe(true));
  it.each(["call the bank", "stretch", "review the PR notesheet"])("not for %s", (text) => expect(aboutWriting(text)).toBe(false));
});


describe("snooze times", () => {
  const evening = new Date(2026, 9, 25, 18, 0);
  it("resolves every preset in the future, including evening after 18:00", () => {
    expect(snoozeUntil("10", evening).getTime() - evening.getTime()).toBe(600_000);
    expect(snoozeUntil("60", evening).getTime() - evening.getTime()).toBe(3_600_000);
    const tomorrow = snoozeUntil("tomorrow", evening);
    expect([tomorrow.getDate(), tomorrow.getHours()]).toEqual([26, 9]);
    const nextEvening = snoozeUntil("evening", evening);
    expect([nextEvening.getDate(), nextEvening.getHours()]).toEqual([26, 18]);
    expect(snoozeUntil("evening", new Date(2026, 9, 25, 17, 59)).getDate()).toBe(25);
  });
  it.each(["", "0", "-1", "nonsense", "Infinity"])("refuses invalid snooze %s", (choice) => {
    expect(() => snoozeUntil(choice, evening)).toThrow();
  });
  it("offers all contracted choices on an overlay reminder", async () => {
    vi.useFakeTimers(); vi.setSystemTime(evening);
    const { reminders, cards, store } = fixture();
    reminders.snoozeMinutes = 30;
    const r = await store.add("Call", evening.getTime(), null);
    await reminders.start();
    const card = cards.get(`reminder-${r.id}`)!;
    expect(card.choices.map((c) => c.value)).toEqual(expect.arrayContaining(["10", "60", "30", "evening", "tomorrow", "pick", "done"]));
    expect(card.choices.some((c) => c.value === "skip")).toBe(false);
    card.onChoose("evening"); await vi.advanceTimersByTimeAsync(0);
    expect((await store.list())[0].due).toBe(snoozeUntil("evening", evening).getTime());
  });
});


describe("project completion reminders", () => {
  it("confirms exact identity and expiry before saving, keeps failures retryable", async () => {
    vi.useFakeTimers(); vi.setSystemTime(new Date("2026-10-25T05:00:00Z"));
    const { reminders, store, cards } = fixture();
    store.resolveProject = vi.fn(async () => ({ path: "/git/api", label: "/git/api" }));
    const add = vi.spyOn(store, "addEvent");
    await reminders.command("when api finishes", "remind");
    const preview = cards.get("reminder-event-preview")!;
    expect(preview.lines?.join(" ")).toContain("When /git/api next finishes");
    expect(preview.lines?.join(" ")).toContain("Expires 24 hours after saving");
    expect(await store.list()).toHaveLength(0);
    add.mockRejectedValueOnce(new Error("disk full"));
    await preview.onChoose("save");
    expect(await store.list()).toHaveLength(0);
    expect(cards.get("reminder-event-preview")?.note).toContain("disk is full");
    await cards.get("reminder-event-preview")!.onChoose("save");
    const [r] = await store.list();
    expect(r.project).toBe("/git/api");
    expect(r.due).toBe(0);
    expect(r.event?.expires).toBe(Date.now() + 86_400_000);
    await reminders.start();
    await vi.advanceTimersByTimeAsync(60_000);
    expect(cards.has("away")).toBe(false);
    expect(cards.has(`reminder-${r.id}`)).toBe(false);
    await cards.get(`reminder-added-${r.id}`)!.onChoose("undo");
    expect(await store.list()).toHaveLength(0);
  });
  it("refuses ambiguous resolution without falling back to a date reminder", async () => {
    const { reminders, store, cards } = fixture();
    store.resolveProject = async () => { throw new Error("Choose a full project path; that name matches several projects."); };
    expect(await reminders.command("when api finishes", "remind")).toContain("several projects");
    expect(await store.list()).toHaveLength(0);
    expect(cards.size).toBe(0);
  });
  it("excludes expired conditions from due delivery", async () => {
    vi.useFakeTimers();
    const { reminders, store, cards } = fixture();
    vi.spyOn(store, "list").mockResolvedValue([{ id: "expired", text: "api finishes", project: "/git/api", due: 0, from: "you", created: Date.now() - 90_000_000, done: false, fired: false, event: { expires: Date.now() - 1000, expiredAt: Date.now() } }]);
    await reminders.start();
    await vi.advanceTimersByTimeAsync(60_000);
    expect(cards.size).toBe(0);
  });
});
