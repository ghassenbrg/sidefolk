import { afterEach, describe, expect, it, vi } from "vitest";
import type { Card } from "./bubble";
import type { Companion } from "./companion";
import { memoryStore, Reminders } from "./reminders";

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
    expect(cards.get(`reminder-${r.id}`)!.lines![0]).toContain("Was due");
    await store.remove(r.id);
    await reminders.reload();
    expect(closeRequest).toHaveBeenCalledWith(`reminder-${r.id}`);
  });
});
