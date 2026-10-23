# Sidefolk app experience — friendly by default

Version 2 concept · 24 October 2026 · Selected identity: **Pip Signal**

Open [the clickable prototype](app-prototype.html). It uses sample data, stays local, and never connects to tools or executes commands. Its appearance/reminder/settings changes last only until the page reloads. Reset demo restores the initial sample state.

## What the user should understand

“Sidefolk shows what my connected tools are doing, tells me when they need an answer, and keeps my reminders nearby.” The character makes the source recognizable. The interface explains the actual action.

Use one interface with progressively disclosed detail. A nontechnical user sees a plain summary and labelled action. An experienced user can inspect the exact command, location and session. Do not put users in a permanent “beginner” or “expert” category.

## Two surfaces, one experience

**Desktop companion:** a small presence, a state signal and a short card when needed. Clicking the companion opens its status; a clear Open Sidefolk action opens the home window. Retain existing shortcuts as optional accelerators, not the only discoverable route. Do not overload a right-click menu with setup.

**Home window:** a calm native-feeling hub with five destinations: Home, Requests, Crew, Reminders, Settings. Menu-bar access remains available when characters are hidden. There is no dashboard of token counts, CPU graphs or terminal output on the first screen.

## The first minute

1. **Welcome.** “A little help, by your side.” Explain progress, requests and reminders. Offer Get started and Try a demo; no login wall in this proposal.
2. **Choose your comfort.** Friendly / Professional / Minimal preview. Name your companion; choose a look. Default Pip for Friendly, Slate for Professional, Dot for Minimal. A preset may suggest motion/sound/presence changes, but show them before Apply. Looks never change what an agent may do.
3. **Connect when ready.** Explain “Connect an AI tool to see its progress and requests here.” Show Claude Code and Codex as not connected until setup truly succeeds. Each Set up action explains the files/permissions it will change and invokes the existing confirm/backup installer flow. Offer Use reminders for now. Do not manufacture a connected success state.

The interactive prototype ends the connection step with a local sample workspace. Real product setup must query installed/available tools and actual connection state. Users without an agent can still try local reminders; this is not a promise of email/calendar/general-assistant integrations.

## Home

Lead with what needs attention: “One thing needs your attention”, then the named project, tool and short summary. Review request opens a dedicated decision view. Other projects appear below with a short factual status. Reminders have their own small section. Show a friendly empty state when there is no work: “You're all caught up” plus Add reminder / Connect a tool.

Avoid using a clock-dependent greeting if the time is unknown. Do not present completion estimates unless there is a reliable source. Keep the visible pet small enough that content remains the focus.

## Requests and decisions

The request card always shows pet + project + tool + session, even when the character has a unique look. Plain title first, then the actual action and scope. Technical details may include full path, command, request type and session identifier. A plain-language summary cannot replace the exact command for an approval.

For the sample: **Slate · Website refresh**, **Codex · Session 04**, “Run project tests?”, command `npm test`, folder `/work/website`. Do not promise that tests have no side effects. Text: “Review the command before allowing it.” Actions: Decline / Allow once, with neither preselected. Keyboard focus must not default to approval.

Real requests may supply different choices; preserve those semantics. Long commands wrap. Clicking an action locks both choices while pending. Show Sent only after acknowledgment; show Retry on transport failure. An expired or already-resolved request disables controls and says why. Never allow a second click to submit twice. The prototype simulates a completed local choice and labels it “demo only”.

Back to requests is navigation, not approval. A denied request is reported as declined, not “failed”. Display multiple requests as a queue grouped by project, and retain exact session ownership. Bring one card into focus without hiding the remaining count.

## Crew and appearance

Roster rows show name, project and status. Selecting a pet opens its appearance and bindings. Separate **collection** (Friendly/Professional/Minimal) from **art style** (3D/2D/Anime). Display unavailable combinations as unavailable; do not silently substitute another character. The prototype's appearance change is illustrative, not a downloadable renderer pack.

Save appearance changes the look and retains name, project and session. Assign project is a distinct action with a folder picker and confirmation of the selected folder. Rename uses a labelled text field. Explain the den in ordinary language: “Resting companions stay out of the way and return when needed.” Avoid describing off-screen pets as deleted or disconnected.

## Reminders

Use a labelled title and explicit date/time fields; natural-language input can remain optional. Show the resolved date, time and timezone before saving ambiguous phrases. In production, use the user's local timezone and handle daylight-saving transitions explicitly. Include edit, complete and delete actions, with undo for deletion where practical. Blank or invalid fields show inline errors next to their controls.

The prototype provides add and complete with a local datetime field; it does not schedule real notifications. For a real missed reminder after sleep, show the original due time and a clear action, using the existing reminder logic as the backend.

## Settings in plain language

| Label | Meaning | Detail only when useful |
|---|---|---|
| Desktop presence | Always visible / Only when needed / Menu bar only | Explain where waiting requests remain accessible |
| Reduce motion | Keep characters and transitions calm | Static state still visible |
| Sound cues | Play a short sound when something needs you | Separate from any future voice setting |
| Hide from screen recordings | Request platform capture protection | Supported capture tools only; no universal guarantee |
| Notification detail | Full preview / Project and status / Status only | Avoid showing project names in a status-only preview |
| Connected tools | Add, inspect, disconnect tools | Installer changes, backups and restore details |

Privacy-sensitive choices must be explicit. Disconnecting a tool needs an explanation of what stops working; switching a theme needs no confirmation. In the real app, settings save feedback must come from persistence success. The prototype clearly labels its in-memory changes.

## Language and recovery

| Internal idea | First-level UI wording |
|---|---|
| Agent | AI tool; use the actual tool name alongside it |
| Binding | Project this companion looks after |
| Den | Resting companions |
| Hook/MCP installation | Connect this tool; explain technical setup in details |
| Session/thread | Work session; keep the ID in request context |
| Provider unavailable | “Codex isn't connected. Set it up to see its activity here.” |
| Connection lost | “Connection lost. Your request hasn't been sent.” with Retry |
| No requests | “You're all caught up.” |

Use plain explanations without hiding consequences. Avoid “It's safe”, “Don't worry”, technical stack names or playful phrasing on destructive actions. Tool messages remain attributed to their source.

## Accessibility and layout

Keyboard-reachable controls, visible focus, proper headings, explicit input labels, 44 px targets, text plus icons for every state, and no color-only identity. Use real buttons and disclosures. In a narrow window, move the sidebar into a wrapping navigation row, stack cards, and allow long text to wrap. At 200% zoom, preserve access to choices without clipped content. Use the system font and honor OS reduced-motion preferences. Let card text size be independent of the companion size.

In a real implementation, focus follows navigation to the new heading and returns sensibly on Back. Decision results use a polite live region; dialogs must trap focus and restore it when closed. Test keyboard and screen-reader journeys with native Tauri behavior, not only HTML markup.

## Validation and scope

Prototype scenarios: complete or skip welcome; review the sample request and allow/decline once; show resolved state; change appearance; add and complete a reminder; change comfort settings; reset the demo. Data is intentionally nonpersistent. No server, network, account, real agent actions, native settings or notifications are connected.

Usability hand checks for later: can a first-time nontechnical person identify which project needs them and decline without help? Can a developer find the complete command/path in one action? Can a workplace user hide character previews and still find requests? Can all three journeys be completed with the keyboard? These require actual people and are not claimed as completed research.

Design v2 expands the earlier single concept board; the written behavior here supersedes conflicting incidental labels or portraits in generated mockups.
