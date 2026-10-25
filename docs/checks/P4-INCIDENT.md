# P4 uninstall-test incident

Recorded 25 October 2026 from the saved handoff and LEARNINGS.md.

An earlier version of the uninstall unit test invoked real `claude mcp remove` and
`codex mcp remove` commands and deleted the real Sidefolk login LaunchAgent. The handoff records
changes around 12:01:52–53. The Claude Sidefolk MCP removal was confirmed; the Codex removal was
likely. Backups were placed in the test's temporary folder, which the test then deleted.

The test was corrected before P4 commit 65e3f99: uninstall paths are explicit `Places`, tests use
temporary paths and an empty agent list. The new P5 installer regression injects a fake MCP
failure and never invokes agent CLIs. Global agent config writes remain forbidden for agents.

The user was informed at the start of the P5 continuation. No restoration has been performed.
Restoration requires explicit user authorization; do not reconstruct a Codex entry by guessing.
A prior Claude backup is referenced in the session handoff, but its old temporary data-directory
path is not a valid new installation target. Use an app-confirmed setup or an explicitly reviewed
restore plan. Do not expose unrelated global config or secrets in logs or reports.
