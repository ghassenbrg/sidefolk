//! When a repeating reminder comes back (docs/V1.md §4). A series keeps the wall-clock time of
//! its first occurrence (its anchor) in the Mac's time zone: 09:00 stays 09:00 across daylight
//! saving. A time that doesn't exist on a day (clocks jump forward) fires at the next minute that
//! does; a time that happens twice (clocks go back) fires the first time. Monthly on the 31st is
//! the last day of shorter months.

use jiff::{
    Timestamp,
    civil::{Date, DateTime},
    tz::{AmbiguousOffset, TimeZone},
};

use crate::reminders::Repeat;

/// The instant a wall-clock time happens in `tz`.
pub fn instant(dt: DateTime, tz: &TimeZone) -> u64 {
    let mut wall = dt;
    // Clocks jumped over this time: the next minute that exists (at most a few hours on).
    for _ in 0..(24 * 60) {
        match tz.to_ambiguous_timestamp(wall).offset() {
            AmbiguousOffset::Gap { .. } => wall = wall.checked_add(jiff::Span::new().minutes(1)).unwrap_or(wall),
            AmbiguousOffset::Unambiguous { offset } | AmbiguousOffset::Fold { before: offset, .. } => {
                return offset.to_timestamp(wall).map(|t| t.as_millisecond().max(0) as u64).unwrap_or_default();
            }
        }
    }
    0
}

/// The wall-clock time of an instant in `tz`.
pub fn wall(ms: u64, tz: &TimeZone) -> DateTime {
    Timestamp::from_millisecond(ms as i64).unwrap_or(Timestamp::UNIX_EPOCH).to_zoned(tz.clone()).datetime()
}

/// The `k`-th occurrence's date after the anchor's (k = 0 is the anchor itself).
fn nth(anchor: Date, repeat: &Repeat, k: i64) -> Option<Date> {
    let n = repeat.n as i64;
    match repeat.every.as_str() {
        "day" => anchor.checked_add(jiff::Span::new().days(k * n)).ok(),
        "week" => anchor.checked_add(jiff::Span::new().days(7 * k * n)).ok(),
        "month" => {
            let months = (anchor.year() as i64) * 12 + (anchor.month() as i64 - 1) + k * n;
            let (year, month) = (months.div_euclid(12) as i16, (months.rem_euclid(12) + 1) as i8);
            let first = Date::new(year, month, 1).ok()?;
            Date::new(year, month, anchor.day().min(first.days_in_month())).ok()
        }
        _ => None,
    }
}

/// The first occurrence strictly after `after`, from a series anchored at `anchor`.
pub fn next_after(anchor: u64, repeat: &Repeat, after: u64, tz: &TimeZone) -> u64 {
    let start = wall(anchor, tz);
    let time = start.time();
    if repeat.every == "weekday" {
        // Each weekday at the anchor's time.
        let mut day = wall(after.max(anchor), tz).date();
        if after < anchor {
            day = day.checked_sub(jiff::Span::new().days(1)).unwrap_or(day);
        }
        for _ in 0..14 {
            if !matches!(day.weekday(), jiff::civil::Weekday::Saturday | jiff::civil::Weekday::Sunday) {
                let at = instant(day.to_datetime(time), tz);
                if at > after && at >= anchor {
                    return at;
                }
            }
            day = day.checked_add(jiff::Span::new().days(1)).unwrap_or(day);
        }
        return after + 86_400_000;
    }
    // A first guess from the average length of a period, then step to the exact occurrence.
    let period: u64 = match repeat.every.as_str() {
        "day" => 86_400_000,
        "week" => 7 * 86_400_000,
        _ => 28 * 86_400_000,
    } * repeat.n as u64;
    let first = (after.saturating_sub(anchor) / period).saturating_sub(2) as i64;
    for k in (first..).take(1000) {
        let Some(date) = nth(start.date(), repeat, k) else { break };
        let at = instant(date.to_datetime(time), tz);
        if at > after {
            return at;
        }
    }
    after + period
}

/// The last occurrence at or before `until` that is after `from` (the most recent one missed),
/// or None when the next one is still to come.
pub fn last_missed(anchor: u64, repeat: &Repeat, from: u64, until: u64, tz: &TimeZone) -> Option<u64> {
    let mut last = None;
    let mut at = next_after(anchor, repeat, from, tz);
    for _ in 0..10_000 {
        if at > until {
            break;
        }
        last = Some(at);
        at = next_after(anchor, repeat, at, tz);
    }
    last
}

#[cfg(test)]
mod tests {
    use super::*;
    use jiff::civil::date;

    fn tz(name: &str) -> TimeZone {
        TimeZone::get(name).unwrap()
    }
    fn at(tz: &TimeZone, y: i16, m: i8, d: i8, h: i8, min: i8) -> u64 {
        instant(date(y, m, d).at(h, min, 0, 0), tz)
    }
    fn repeat(every: &str, n: u32) -> Repeat {
        Repeat { every: every.into(), n }
    }
    fn wall_of(ms: u64, tz: &TimeZone) -> (i8, i8, i8, i8) {
        let w = wall(ms, tz);
        (w.month(), w.day(), w.hour(), w.minute())
    }

    #[test]
    fn keeps_the_wall_clock_across_daylight_saving() {
        for name in ["Europe/Paris", "America/New_York"] {
            let tz = tz(name);
            let anchor = at(&tz, 2026, 10, 20, 9, 0);
            let mut t = anchor;
            for _ in 0..20 {
                t = next_after(anchor, &repeat("day", 1), t, &tz);
                assert_eq!(wall(t, &tz).time(), jiff::civil::time(9, 0, 0, 0), "{name}");
            }
        }
    }

    #[test]
    fn a_time_skipped_by_the_clocks_fires_at_the_next_minute_and_a_doubled_one_once() {
        let paris = tz("Europe/Paris");
        // 29 March 2026: 02:00 jumps to 03:00. A daily 02:30 fires at 03:00 that day.
        let anchor = at(&paris, 2026, 3, 27, 2, 30);
        let day = next_after(anchor, &repeat("day", 1), at(&paris, 2026, 3, 28, 12, 0), &paris);
        assert_eq!(wall_of(day, &paris), (3, 29, 3, 0));
        // 25 October 2026: 02:30 happens twice. It fires the first time, and only once.
        let anchor = at(&paris, 2026, 10, 24, 2, 30);
        let first = next_after(anchor, &repeat("day", 1), anchor, &paris);
        let second = next_after(anchor, &repeat("day", 1), first, &paris);
        assert_eq!((wall_of(first, &paris), wall_of(second, &paris)), ((10, 25, 2, 30), (10, 26, 2, 30)));
        assert_eq!(second - first, 25 * 3_600_000);
    }

    #[test]
    fn weekly_monthly_and_weekdays() {
        let tokyo = tz("Asia/Tokyo");
        // Monday 26 October 2026 09:00, weekly: the next Mondays, whatever "after" is.
        let monday = at(&tokyo, 2026, 10, 26, 9, 0);
        let tuesday = at(&tokyo, 2026, 10, 27, 10, 0);
        assert_eq!(wall_of(next_after(monday, &repeat("week", 1), tuesday, &tokyo), &tokyo), (11, 2, 9, 0));
        assert_eq!(wall_of(next_after(monday, &repeat("week", 2), monday, &tokyo), &tokyo), (11, 9, 9, 0));
        // Monthly on the 31st: the last day of shorter months.
        let jan31 = at(&tokyo, 2027, 1, 31, 9, 0);
        let feb = next_after(jan31, &repeat("month", 1), jan31, &tokyo);
        assert_eq!(wall_of(feb, &tokyo), (2, 28, 9, 0));
        assert_eq!(wall_of(next_after(jan31, &repeat("month", 1), feb, &tokyo), &tokyo), (3, 31, 9, 0));
        // Weekdays skip the weekend: Friday → Monday.
        let friday = at(&tokyo, 2026, 10, 30, 9, 0);
        assert_eq!(wall_of(next_after(friday, &repeat("weekday", 1), friday, &tokyo), &tokyo), (11, 2, 9, 0));
    }

    #[test]
    fn finds_the_most_recent_missed_occurrence() {
        let tokyo = tz("Asia/Tokyo");
        let anchor = at(&tokyo, 2026, 10, 20, 9, 0);
        let missed = last_missed(anchor, &repeat("day", 1), anchor, at(&tokyo, 2026, 10, 25, 10, 0), &tokyo);
        assert_eq!(wall_of(missed.unwrap(), &tokyo), (10, 25, 9, 0));
        assert_eq!(last_missed(anchor, &repeat("day", 1), anchor, at(&tokyo, 2026, 10, 20, 18, 0), &tokyo), None);
    }
}
