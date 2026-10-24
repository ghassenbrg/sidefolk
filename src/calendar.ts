import type { Companion } from "./companion";

// The calendar heads-up: a few minutes before a meeting, the companion says so, with Join when the
// event has a video link. Events come from the macOS calendars (calendar.rs), read on this Mac
// once a minute while the setting is on; each one is announced once.

/** Mirrors `Event` in src-tauri/src/calendar.rs. */
export type CalendarEvent = { id: string; title: string; start: number; end: number; location: string; link: string | null; calendar: string };

const KEY = "sidefolk.announced";
const CHECK_MS = 60_000;

const clock = (ms: number) => new Date(ms).toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" });

/** "Design review in 5 min", "Design review now". */
export function headline(event: CalendarEvent, now = Date.now()) {
  const mins = Math.round((event.start - now) / 60_000);
  return mins <= 0 ? `${event.title} now` : `${event.title} in ${mins} min`;
}

/** The events to announce now: starting within `lead` minutes (or started under 2 minutes ago). */
export function due(events: CalendarEvent[], lead: number, announced: ReadonlySet<string>, now = Date.now()) {
  return events.filter((e) => !announced.has(e.id) && e.start - lead * 60_000 <= now && now < e.start + 2 * 60_000);
}

export class HeadsUp {
  private announced = new Set<string>(this.read());
  private timer = 0;

  constructor(
    private readonly companion: Companion,
    private readonly upcoming: () => Promise<CalendarEvent[]>,
    private readonly openLink: (url: string) => void,
  ) {}

  /** Starts or stops checking, as the setting says; `lead` is minutes before a meeting. */
  set(on: boolean, lead: number) {
    clearInterval(this.timer);
    if (!on) return;
    const check = () => void this.check(lead).catch(() => {});
    check();
    this.timer = window.setInterval(check, CHECK_MS);
  }

  /** "next meeting": what's next today, said by the companion. */
  async next(): Promise<string> {
    const events = await this.upcoming();
    const e = events.find((x) => x.start > Date.now() - 60_000);
    return e ? `Next: ${e.title} at ${clock(e.start)}${e.location ? `, ${e.location}` : ""}.` : "Nothing on your calendar in the next few hours.";
  }

  private async check(lead: number) {
    for (const event of due(await this.upcoming(), lead, this.announced)) {
      this.announced.add(event.id);
      this.save();
      this.show(event);
    }
  }

  private show(event: CalendarEvent) {
    const pet = this.companion.pet;
    const id = `meeting-${event.id}`;
    pet.bubble.show({
      id,
      who: `${pet.name} · ${event.calendar || "calendar"}`,
      title: headline(event),
      lines: [`${clock(event.start)}–${clock(event.end)}${event.location ? ` · ${event.location}` : ""}`],
      choices: [...(event.link ? [{ label: "Join", value: "join", primary: true }] : []), { label: "OK", value: "ok", primary: !event.link }],
      onChoose: (value) => {
        pet.bubble.close(id);
        if (value === "join" && event.link) this.openLink(event.link);
      },
    });
    pet.mind.react("wave", 1.6);
    // Gone a few minutes after it started; the meeting has its own reminders from there.
    setTimeout(() => pet.bubble.close(id), Math.max(60_000, event.start + 5 * 60_000 - Date.now()));
  }

  private read(): string[] {
    try {
      const value = JSON.parse(localStorage.getItem(KEY) ?? "[]");
      return Array.isArray(value) ? value.filter((v) => typeof v === "string") : [];
    } catch {
      return [];
    }
  }

  private save() {
    try {
      localStorage.setItem(KEY, JSON.stringify([...this.announced].slice(-100)));
    } catch {
      // Kept for this run only.
    }
  }
}
