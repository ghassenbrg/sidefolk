# Sidefolk 🌱

A little desktop company, powered by real AI agents. Name your pet, give it something to remember, or work on a project together.

**Local desktop MVP · Electron + React + Three.js · macOS tested**

## Run it

Requires Node.js 22.12+ (Node 24 recommended) and npm.

```sh
cd ~/git/sidefolk
npm install
npm run dev
```

For a production build:

```sh
npm run build
npm start
```

Create an unpacked desktop application with `npm run package`. On Apple Silicon the app appears under `release/Sidefolk-darwin-arm64/Sidefolk.app`. This is an unsigned local build.

## Meet your companion

- **A real 3D pet.** Name it and choose sage, peach, or lilac. Click to make it bounce. “Let pet roam” opens a draggable, transparent, always-on-top desktop window. The pet reacts to working, reminder, and quiet states.
- **Codex or Claude behind the scenes.** Connect the installed CLI, use its existing login, and resume Sidefolk-owned sessions across launches. Switching providers keeps shared memory and skills. Each provider retains its own native history.
- **Natural reminders.** “Can u remind to check my phone in 5 min from now” works directly; there is no required command phrase. Common wording stays local. For contextual or less direct wording, the agent proposes an action in its existing response; the app validates and saves it before confirming success. Date-only requests use 9am. Missing times get a short question. Snooze, complete, reopen, and delete reminders.
- **Local todos.** “Add buy coffee to my todos.” “Show my unfinished tasks.”
- **Shared memory.** “Remember that I prefer pnpm.” Add, edit, and forget notes in Memory. Agent responses can propose new preferences; only accepted suggestions enter shared context.
- **Editable skills.** Reusable instructions shape the companion across providers. Enabled skills share a 3,000-character budget and are sent only on a new session or when changed.
- **A small workshop.** Choose a project folder for agent work. Review and run an npm script, see live output, and stop its process group. The preview includes npm pre/post scripts.

Close the main window to keep Sidefolk in the menu bar. Use the menu bar icon to reopen it or quit. Reminders run while the app is running; they do **not** wake a shut-down computer or fire while the app is quit. Overdue reminders surface the next time the app runs or the computer wakes. macOS notification settings may need to allow notifications for Electron or Sidefolk. Quiet time defers notifications until turned off.

## Connect an agent

Install and sign in to **Codex CLI** or **Claude Code** using their official setup instructions. Sidefolk checks standard executable locations and your PATH. It uses the CLI's configured default model and credentials; it never asks you to paste a key into the UI.

Choose the provider in Settings. Without a selected project, the agent runs a lightweight conversation with project tools disabled. Choose a project in Workshop to enable project tools and work on your own code.

For project work, Codex defaults to its read-only sandbox. Claude is given only Read, Glob, and Grep tools. Optional workspace edits enable Codex's workspace-write sandbox or Claude's Edit/Write tools; Claude shell execution remains disabled. The explicit npm script runner is separate. Standard mode loads existing CLI customizations, skills, hooks, and MCP configuration according to the provider's behavior. Sidefolk's prompt asks the agent to stay within the workspace; Claude's tool allowlist is **not** an OS filesystem sandbox. Use trusted project folders.

Native provider skills remain provider-specific. Economy mode uses Sidefolk's shared skills instead of loading large global catalogs. Codex receives per-invocation overrides to skip user config, disable global skill entries, and use a compact base instruction file. Claude skips settings sources, slash commands, and external MCP configs. These overrides never modify your own CLI configuration. Standard mode restores normal provider customization loading. The current Codex adapter uses the `skip_host_skill_discovery` feature supported by the installed CLI 0.160.0; older CLI versions may need an upgrade.

References: [Codex non-interactive sessions](https://learn.chatgpt.com/docs/non-interactive-mode), [Claude Code programmatic usage](https://code.claude.com/docs/en/headless), [Electron context isolation](https://www.electronjs.org/docs/latest/tutorial/context-isolation), [React Three Fiber](https://r3f.docs.pmnd.rs/).

## Keep it light

No AI loop runs in the background. Animations, scheduling, todo actions, naming, and memory CRUD are local. Local-only mode works with no model or account at all.

The agent can create reminders and todos through a bounded app-action protocol even when project tools are disabled. Relative time is anchored to the original request, invalid or past dates are rejected, repeated actions within a response are deduplicated, and failed/stopped turns execute no actions. The app executes at most three validated actions per response. This adds no separate intent-classification model call. Local-only mode handles common wording; semantic and contextual fallback needs an agent.

Economy mode requests low reasoning effort and concise replies, with compact native instructions and global catalogs disabled. Native session resume avoids replaying the app's whole transcript. Up to four relevant confirmed memory snippets (300 characters each) are included per request. Unchanged skills/persona are not resent. Memory suggestions arrive in the existing response, with no extraction model call. Agent turns have a five-minute limit and a Stop button.

In the local smoke check, initial Codex input fell from 24,561 tokens with the original CLI configuration to 9,102 in lightweight Economy chat (about 63% less). Native agent overhead remains substantial, and these are observations on this machine, not a guaranteed request size. Codex's cumulative session counters are converted into incremental app usage.

The usage panel shows reported input, cached, and output tokens. Providers account for cache tokens differently; the totals are not a billing estimate. CLI system prompts, native skills, growing conversation history, and tool results still consume context. Start a fresh conversation when appropriate. Economy mode is a reduction strategy, not a hard token cap.

The 3D scene caps resolution at 1.5× and invalidates at 24 fps. Hidden documents stop animation invalidation. Reduced-motion mode updates once per second. Geometry is generated in code; no external 3D assets or network font requests are needed.

## Data and privacy

App state is stored as `sidefolk.json` in Electron's user data directory (on macOS, typically `~/Library/Application Support/Sidefolk/`). It contains pet settings, reminders, memory, skills, visible conversation history, native session IDs, and usage counters. Writes use a temporary file and atomic rename. Invalid data is preserved in a recovery file. This MVP does not encrypt local data.

Confirmed memory and conversation text are sent to the selected provider when an agent runs. No analytics or app-operated backend is configured. Forgetting a note excludes it from future Sidefolk prompts; it does not erase the provider's earlier session history. Create a new conversation after forgetting sensitive context.

## Development and verification

```sh
npm test                # Scheduling, local routing, storage, agent protocol, context budgets
npm run build           # Typecheck, Electron compilation, renderer production build
npm run test:desktop    # Real Electron UI test using disposable data; no AI calls
npm run test:agents     # Opt-in LIVE check: two short model calls per provider
npm run test:packaged   # Open/check the packaged macOS app without AI calls
node scripts/packaged-smoke.mjs --live # Opt-in: one real Codex turn in the .app
```

Desktop screenshots go into ignored `output/playwright/`. `SIDEFOLK_DATA_DIR` overrides the data directory for isolated testing.

Verified locally on macOS Apple Silicon: production build, 20 core tests, full desktop flow (including restart and casual reminders), native packaged launch, a live Codex conversation in the packaged app, and native Codex session resume. `npm audit` reports zero vulnerabilities. The Claude adapter's protocol and permissions are tested; its live check was blocked by this account's weekly Claude usage limit.

## Next iterations

- Voice input and optional speech.
- File/link attachments and contextual reminders.
- Compact session summaries and smarter memory retrieval.
- Visible helper agents with explicit task delegation and budget controls.
- Agent SDK/app-server transports for finer tool approvals and streaming.
- Recurring reminders, OS-backed scheduling, and optional launch at login.
- Richer animation, character customization, and Windows/Linux validation.

This first version supports one active agent turn at a time. There is no autonomous continuous learning or model retraining: learning means remembered preferences, accepted suggestions, and reusable skills.
