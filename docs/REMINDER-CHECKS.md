# Reminder acceptance (PLAN-V2 §6.1)

Verified 24 October 2026: typecheck, Vitest (46), Rust tests, WebKit add/edit/repeat/Undo
in light and dark, and DST recurrence under `TZ=Europe/Paris`.

The bundled debug app was tested with the companion hidden. A 20-second reminder arrived
with Pip in the note pose, `unoccluded=true` and `overlay_key=false`. Snoozing saved a future
due time, cleared `fired`, and recorded history. Native logs: `/tmp/sidefolk-native-check.log`.
This verifies native delivery while hidden, not notification delivery while quit or actual
sleep/wake. No live model call or screen capture was used.

## Still needed on the Mac

1. Settings → Shortcut and startup → Allow notifications (also in setup's Where it lives).
   macOS currently reports `notRequested`. Without permission it refuses scheduling with
   UNErrorDomain 1. Companion reminders continue while the app is running.
2. Create a reminder a minute ahead. Review Save / Change, then Save. Quit Sidefolk before
   it is due. Verify the macOS notification arrives. Click it: Sidefolk opens that reminder's
   details/history. Edit/snooze it; verify the new due time.
3. Create another near-future reminder, sleep the Mac past its due time, then wake. Verify it
   appears once with the original due time. Answer it and ensure it stays answered.
4. In the app window, set a repeating reminder, complete it, edit its repeat, then clear it.
   Check the next due time and history. Only the next occurrence is scheduled with macOS;
   marking a repeat done advances it.

## Repeatable development checks

- `npm run web` (reuse port 1420 if already running), `npm run check:webkit`.
- `TZ=Europe/Paris npx vitest run src/when.test.ts` exercises a real DST time zone.
- Bundled dev app with log harness:
  `NODE_ENV=development PATH="$HOME/.cargo/bin:$PATH" npx tauri build --debug --bundles app`.
  Quit the running Sidefolk before starting the debug bundle, as only one can own port 47821.
- POST JSON to `http://127.0.0.1:47821/dev/ui` with Content-Type application/json:
  `{"action":"notifications"}` returns permission/error; `{"action":"reminders"}` returns
  the persisted snapshot. Existing `run:remind me in 20 seconds to ...`, `choose:Save`,
  `bubbles`, `state`, and `choose:Done` drive and inspect native delivery through the dev log.
  These endpoints are debug-only. They never grant notification permission.
- Always rebuild production with plain `npm run build` (without NODE_ENV=development), then
  relaunch the resulting `src-tauri/target/release/bundle/macos/Sidefolk.app`.
