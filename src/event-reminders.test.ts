import { describe, expect, it, vi } from "vitest";
import { eventDescription, isScheduledReminder, resolveEventProject } from "./event-reminders";
import type { Reminder } from "./reminders";

const reminder: Reminder = { id: "event", text: "api finishes", project: "/git/api", from: "you", created: 1000, due: 0, done: false, fired: false, event: { expires: 86_401_000 } };

describe("exact event project resolution", () => {
  it("passes one exact known identity through the host resolver", async () => {
    const host = vi.fn(async (path: string) => ({ path, label: path }));
    expect(await resolveEventProject("api", ["/git/api", "/git/web", "/git/api"], host)).toEqual({ path: "/git/api", label: "/git/api" });
    expect(host).toHaveBeenCalledWith("/git/api");
  });
  it("asks rather than guessing among matching basenames or near names", async () => {
    const host = vi.fn();
    await expect(resolveEventProject("api", ["/work/api", "/personal/api"], host)).rejects.toThrow("several projects");
    await expect(resolveEventProject("ap", ["/git/api"], host)).rejects.toThrow("no exact project match");
    await expect(resolveEventProject("API", ["/git/api"], host)).rejects.toThrow("no exact project match");
    expect(host).not.toHaveBeenCalled();
  });
  it("accepts an explicit path and rejects a host's unresolved relative result", async () => {
    const host = vi.fn(async () => ({ path: "/git/new", label: "~/git/new" }));
    expect((await resolveEventProject("~/git/new", [], host)).path).toBe("/git/new");
    expect(host).toHaveBeenCalledWith("~/git/new");
    await expect(resolveEventProject("/git/new", [], async () => ({ path: "new", label: "new" }))).rejects.toThrow("full project folder path");
  });
});

describe("event reminder presentation", () => {
  it("keeps waiting and expiry outside date delivery while retaining their visible explanation", () => {
    expect(isScheduledReminder(reminder)).toBe(false);
    expect(eventDescription(reminder)).toContain("When /git/api next finishes");
    const expired = { ...reminder, event: { expires: 86_401_000, expiredAt: 86_401_001 } };
    expect(isScheduledReminder(expired)).toBe(false);
    expect(eventDescription(expired)).toContain("No reminder was sent");
    const triggered = { ...reminder, due: 2000, event: { expires: 86_401_000, triggeredAt: 2000 } };
    expect(isScheduledReminder(triggered)).toBe(true);
    expect(isScheduledReminder({ ...triggered, done: true })).toBe(false);
    expect(eventDescription(triggered)).toContain("Triggered by /git/api finishing");
  });
});
