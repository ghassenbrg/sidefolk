//! Privacy-preserving support report. Raw logs are inspected only to count diagnostics;
//! their contents are never included in the returned report.

use crate::settings::Settings;

/// Build a compact report from platform details, a small settings allowlist, and aggregate
/// diagnostics. Raw log details remain local and are never copied into the report.
pub fn report(
    version: &str,
    os: &str,
    arch: &str,
    settings: &Settings,
    page_log: &str,
    crash_log: &str,
) -> String {
    let theme = match settings.theme.as_str() {
        "system" | "light" | "dark" => settings.theme.as_str(),
        _ => "unknown",
    };
    let size = match settings.pet_size.as_str() {
        "small" | "medium" | "large" => settings.pet_size.as_str(),
        _ => "unknown",
    };
    let page = summarize(page_log);
    let crash = summarize(crash_log);

    format!(
        "Sidefolk {version} on {os} ({arch})\n\nSettings: theme={theme}, size={size}, quiet={}, reduced_motion={}\n\nDiagnostics (aggregate counts only):\nPage log: {} lines, {} error-like, {} warning-like\nCrash log: {} lines, {} error-like, {} warning-like\n\nRaw log details and personal content remain on this Mac and are not included.\nWhat happened, and what did you expect?\n",
        !settings.sounds,
        settings.calm,
        page.lines,
        page.errors,
        page.warnings,
        crash.lines,
        crash.errors,
        crash.warnings,
    )
}

#[derive(Default)]
struct Counts {
    lines: usize,
    errors: usize,
    warnings: usize,
}

fn summarize(log: &str) -> Counts {
    let mut counts = Counts::default();
    for line in log.lines() {
        counts.lines += 1;
        let lower = line.to_ascii_lowercase();
        if ["error", "exception", "panic", "failed"].iter().any(|word| lower.contains(word)) {
            counts.errors += 1;
        }
        if ["warn", "warning"].iter().any(|word| lower.contains(word)) {
            counts.warnings += 1;
        }
    }
    counts
}

#[cfg(test)]
mod tests {
    use super::report;
    use crate::settings::Settings;

    #[test]
    fn report_contains_allowlisted_settings_and_aggregate_counts_only() {
        let private_path = "/Users/alice/private-project";
        let private_email = "alice@example.com";
        let private_token = "sk-live-very-secret";
        let first_prompt = "Please fix my confidential launch plan";
        let page_log = format!(
            "ERROR loading {private_path} for {private_email}: {private_token}\nWARN {first_prompt}\nordinary detail"
        );
        let crash_log = format!("panic in {private_path}\nfailed: {private_token}");
        let settings = Settings { theme: "dark".into(), pet_size: "large".into(), sounds: false, calm: true, ..Settings::default() };

        let output = report("1.2.3", "macOS 15.0", "aarch64", &settings, &page_log, &crash_log);

        for secret in [private_path, private_email, private_token, first_prompt] {
            assert!(!output.contains(secret), "report leaked {secret}");
        }
        assert!(output.contains("Sidefolk 1.2.3 on macOS 15.0 (aarch64)"));
        assert!(output.contains("theme=dark, size=large, quiet=true, reduced_motion=true"));
        assert!(output.contains("Page log: 3 lines, 1 error-like, 1 warning-like"));
        assert!(output.contains("Crash log: 2 lines, 2 error-like, 0 warning-like"));
        assert!(output.contains("remain on this Mac"));
    }

    #[test]
    fn invalid_setting_strings_are_not_reflected() {
        let settings = Settings { theme: "alice@example.com".into(), pet_size: "/Users/alice".into(), ..Settings::default() };
        let output = report("1", "macOS", "arm64", &settings, "", "");
        assert!(output.contains("theme=unknown, size=unknown"));
        assert!(!output.contains("alice@example.com"));
        assert!(!output.contains("/Users/alice"));
        assert!(output.contains("Page log: 0 lines"));
    }
}
