---
name: sidefolk
description: Control Sidefolk, inspect its live status, and manage its reminders or work log through the connected Sidefolk MCP server.
---

# Sidefolk

Use Sidefolk's connected MCP server to act on the user's companion, reminders, and notebooks. Sidefolk is a control surface, not an agent; do not imply it performed work that another agent did.

## Start with discovery

1. Find the available Sidefolk MCP tools and read their current input schemas before calling them. Tool availability and schemas are authoritative; do not assume an upcoming tool is installed or invent argument names or values.
2. If `sidefolk_status` is available, call it with `{}` first and use its returned live state to ground the response and action.
3. If no Sidefolk MCP server/tools are connected, explain that the user can connect it in Sidefolk **Settings → Agents**. Do not edit agent configuration, install MCP, or change global settings yourself.

## Route the request

- **Show, hide, summon, or open a window/settings:** use `sidefolk_control` with the matching available action (`show`, `hide`, `summon`, `open_window`, `open_settings`). Use the user's wording and live status to choose; ask if it could reasonably mean different actions.
- **Change appearance or name:** use `sidefolk_control` actions `set_look` (`pip` or `spark`), `rename`, or `set_size` (`small`, `medium`, `large`) as appropriate. Do not infer unspecified fields; inspect the schema. Ask for the new name when absent.
- **Quiet mode:** use `sidefolk_control` action `set_quiet`; clarify the desired state if the user did not specify enable/disable and current status does not resolve it.
- **Reminder requests:** use `sidefolk_reminders` actions `list`, `add`, `complete`, `snooze`, or `delete` when available. For `add`, provide an explicit epoch due time as required by the live schema. Resolve relative dates against the user's locale/time zone and confirm the intended time when ambiguous; never guess a due time. For actions on an existing reminder, identify the target unambiguously and ask if needed.
- **Notebook/work-log requests:** use `sidefolk_notes` actions `list_notebooks`, `read`, or `append` when available. Use the default notebook **Log** when the user has not named one and the request is an ordinary log entry. For a named notebook, match its exact name from the available notebook list; if there are multiple plausible matches or no exact match, ask rather than choosing or creating one. Preserve the user's note text when appending.
- Existing `notify`, `ask`, `remind`, and `presence` tools may also be available. Read their schemas and use them only when they fit the request; do not substitute them for a control, reminder-management, or notebook action they cannot perform.

## Act and report

- Make only the action the user requested. Do not add, complete, snooze, delete, or change unrelated items.
- For any action, use only fields confirmed by that tool's current schema. If the schema or tool result is unclear, stop and explain what is missing.
- Report the result from the tool response. If it fails or is unavailable, say so plainly; never claim success based on intent.
- Do not run shell commands, seek agent approvals, or change global configuration as part of Sidefolk control.
