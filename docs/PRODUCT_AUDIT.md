# Sidefolk product audit · 23 October 2026

## Product promise

A desktop companion that helps you capture a request, follow through, and return to your work. Personality makes the tool welcoming; reliable actions make it worth keeping open.

The daily loop is **summon → ask → see the result → return to work**. The full window is for reviewing tasks, conversations, and preferences. Character customization is secondary to getting help.

## Findings from code and real Electron workflows

| Priority | Finding                                                                                   | User impact                                                       | Resolution target                                                               |
| -------- | ----------------------------------------------------------------------------------------- | ----------------------------------------------------------------- | ------------------------------------------------------------------------------- |
| P0       | Restored project sessions retain toolsEnabled even after the connected project is cleared | A conversation can retain unexpected project-tool access          | Recompute access from the actively connected project before every turn          |
| P1       | No first-run setup; default provider may not be installed                                 | First conversation fails without clear explanation                | One-screen setup with detected CLI availability and explicit local mode         |
| P1       | Clicking the pet opens a 1280px dashboard                                                 | Capturing one reminder disrupts current work                      | Focused Quick Ask window, Escape to dismiss, menu-bar and global shortcut entry |
| P1       | Any sentence beginning “add” can become a to-do                                           | Agent requests such as “add dark mode” are silently misclassified | Only explicit todo syntax takes the deterministic route                         |
| P1       | Reminders cannot be edited                                                                | Correcting a date requires deleting and recreating a task         | Edit title/time/type in place, validate future reminder times                   |
| P1       | Chat Markdown links are noninteractive spans                                              | Answers look broken                                               | Validated HTTP(S) links open in the system browser                              |
| P1       | Task deletion is immediate                                                                | Accidental loss of a reminder                                     | Explicit confirmation with task title                                           |
| P1       | Existing skill/script dialogs lack native focus containment and Escape behavior           | Keyboard navigation is inconsistent                               | Use the shared native dialog component                                          |
| P1       | A selected CLI looks “connected” without authenticating                                   | False sense of readiness                                          | Distinguish installed CLI from verified login; explain recovery                 |
| P2       | Large slogan headers and competing navigation dominate the useful content                 | Product feels like a collection of demos                          | Task-focused language, conversation-first navigation, quieter visual hierarchy  |
| P2       | Chat drafts disappear when navigating                                                     | Thought is lost                                                   | Persist local draft per conversation in session storage                         |
| P2       | No in-app notification check or local backup export                                       | Hard to verify reminder setup or protect data                     | Notification test, explicit delivery limits, JSON backup export                 |
| P2       | 3D fallback is a static plant emoji                                                       | Unsupported GPU breaks character identity                         | Render the chosen illustrated character as fallback                             |

## Validation and release boundaries

Run core tests, real Electron workflows, a focused product acceptance script, packaged launch, and a production dependency audit. Use disposable app data and no model calls for UI checks. Review screenshots at normal and compact sizes. Keep existing names, appearance, memory, tasks, and sessions through migration.

This is a local macOS release candidate, not a publicly distributable production release. Distribution still needs a signing identity and notarization, installer/update strategy, crash reporting policy, Windows/Linux native testing, and accessibility checks with assistive technology. Reminder delivery requires Sidefolk to remain running; macOS notification permission is controlled by the user. CLI presence does not verify login, quota, or network availability. Those conditions must never be represented as verified by detection alone.

## Implemented in this pass

All findings in the table above have an implementation in this branch. Additional hardening covers npm lifecycle scripts (a changed or newly added pre/post hook invalidates the review), structurally invalid conversation references (preserved in a recovery backup), and renderer failure recovery. Failed requests offer an explicit edit/retry path. Notification clicks open Tasks; Quick Ask’s connection control opens Settings and dismisses the compact window. Existing users can review setup without resetting their records.

The navigation now groups daily work separately from personalization. The welcome artwork is original generated imagery, recorded in WELCOME_ART.md. The daily conversation remains quiet and action-focused. All six existing character choices are retained.

3D rendering is a separate lazy-loaded bundle. The initial renderer JavaScript decreased from approximately 1,367 KB to 451 KB before compression; the 919 KB 3D bundle loads only when needed. This is a bundle measurement, not a claim of measured battery improvement.

## Verification recorded

- 29 core tests: routing, scheduling, storage migration/recovery, protocol validation, permission settings, URLs, and script lifecycle review.
- Product acceptance: first-run setup, local mode, draft recovery, compact Quick Ask, saved reminder receipt, edit-in-place, Escape, cancelled deletion, validated backup export, invalid URL rejection, connection navigation, pet entry, and restart persistence.
- Existing desktop suite: reminders, snooze, tasks, memory, skills, desktop controls, global-shortcut conflict handling, script execution, and restart.
- Design suite: six illustrated characters, accessories, sculpted previews, appearance persistence, compact layouts, and desktop appearance synchronization.
- Production dependency audit: no reported vulnerabilities at the time of this audit.
- New UI acceptance tests use disposable data and zero model calls. These do not substitute for live provider authentication/quota testing, a screen-reader audit, or notification permission checks on another machine.

## Release decision

Proceed as an **unsigned local macOS release candidate**. Do not label it a completed public production release. Remaining gates: developer signing/notarization, a supported installer/update path, cross-machine notification and login testing, assistive-technology review, and Windows/Linux packaging and behavior validation. Recurring and OS-backed reminders remain future capabilities. The existing single-active-agent constraint is explicit.
