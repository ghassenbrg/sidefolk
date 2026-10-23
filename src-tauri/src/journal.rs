//! What happened while you were away: sessions starting and ending, prompts, outcomes and
//! questions, per project. One JSON line per entry, one file per UTC day, kept 30 days.
//! It stays on this Mac; tool-by-tool activity is not recorded.
use serde::{Deserialize, Serialize};
use std::{
    fs,
    io::{self, Write},
    path::PathBuf,
    sync::Mutex,
    time::{SystemTime, UNIX_EPOCH},
};

const KEEP_DAYS: u64 = 30;
const DAY_MS: u64 = 86_400_000;

#[derive(Serialize, Deserialize, Clone, Debug, PartialEq)]
pub struct Entry {
    /// Unix milliseconds.
    pub at: u64,
    pub source: String,
    pub session: String,
    pub project: String,
    /// start | prompt | waiting | done | failed | end | ask | answer
    pub kind: String,
    pub detail: String,
}

pub fn now_ms() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_millis() as u64)
        .unwrap_or_default()
}

/// "2026-10-24" for a day number since 1970 (proleptic Gregorian, UTC).
fn date(day: u64) -> String {
    // Howard Hinnant's civil_from_days.
    let z = day as i64 + 719_468;
    let era = z.div_euclid(146_097);
    let doe = z.rem_euclid(146_097);
    let yoe = (doe - doe / 1460 + doe / 36_524 - doe / 146_096) / 365;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let d = doy - (153 * mp + 2) / 5 + 1;
    let m = if mp < 10 { mp + 3 } else { mp - 9 };
    let y = yoe + era * 400 + i64::from(m <= 2);
    format!("{y:04}-{m:02}-{d:02}")
}

pub struct Journal {
    dir: PathBuf,
    write: Mutex<()>,
}

impl Journal {
    pub fn open(data_dir: &std::path::Path) -> Self {
        let journal = Self {
            dir: data_dir.join("journal"),
            write: Mutex::new(()),
        };
        journal.prune(now_ms() / DAY_MS);
        journal
    }

    fn file(&self, day: u64) -> PathBuf {
        self.dir.join(format!("{}.jsonl", date(day)))
    }

    pub fn record(&self, entry: &Entry) -> io::Result<()> {
        let _guard = self.write.lock().unwrap();
        fs::create_dir_all(&self.dir)?;
        let mut line = serde_json::to_vec(entry)?;
        line.push(b'\n');
        let mut options = fs::OpenOptions::new();
        options.create(true).append(true);
        #[cfg(unix)]
        {
            use std::os::unix::fs::OpenOptionsExt;
            options.mode(0o600);
        }
        options.open(self.file(entry.at / DAY_MS))?.write_all(&line)
    }

    /// Entries at or after `since` (Unix ms), oldest first. Unreadable lines are skipped.
    pub fn since(&self, since: u64) -> Vec<Entry> {
        let today = now_ms() / DAY_MS;
        let first = (since / DAY_MS).max(today.saturating_sub(KEEP_DAYS));
        (first..=today)
            .filter_map(|day| fs::read_to_string(self.file(day)).ok())
            .flat_map(|text| {
                text.lines()
                    .filter_map(|line| serde_json::from_str::<Entry>(line).ok())
                    .collect::<Vec<_>>()
            })
            .filter(|e| e.at >= since)
            .collect()
    }

    fn prune(&self, today: u64) {
        let Ok(files) = fs::read_dir(&self.dir) else { return };
        let oldest = date(today.saturating_sub(KEEP_DAYS));
        for file in files.flatten() {
            let name = file.file_name().to_string_lossy().into_owned();
            // Dated names sort as text; anything else in the folder is left alone.
            if name.len() == "2026-10-24.jsonl".len() && name.ends_with(".jsonl") && name.as_str() < oldest.as_str() {
                let _ = fs::remove_file(file.path());
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn dates() {
        assert_eq!(date(0), "1970-01-01");
        assert_eq!(date(20_750), "2026-10-24");
        assert_eq!(date(11_016), "2000-02-29");
    }
    #[test]
    fn records_reads_and_prunes() {
        let dir = std::env::temp_dir().join(format!("sidefolk-journal-{}", std::process::id()));
        let journal = Journal::open(&dir);
        let entry = |at: u64| Entry {
            at,
            source: "claude".into(),
            session: "s".into(),
            project: "/p".into(),
            kind: "done".into(),
            detail: "ok".into(),
        };
        let now = now_ms();
        journal.record(&entry(now - 1000)).unwrap();
        journal.record(&entry(now)).unwrap();
        journal.record(&entry(now - 40 * DAY_MS)).unwrap();
        assert_eq!(journal.since(now - 500), vec![entry(now)]);
        assert_eq!(journal.since(0).len(), 2);
        Journal::open(&dir);
        assert_eq!(fs::read_dir(dir.join("journal")).unwrap().count(), 1 + usize::from(now / DAY_MS != (now - 1000) / DAY_MS));
        fs::remove_dir_all(dir).unwrap();
    }
}
