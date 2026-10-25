# Priya — Head of Product: strategy and release audit

25 October 2026. Independent simulated product seat; this is product judgment and source research, not customer research. I read the repository instructions, shared memory, README, guide, PLAN-V2 and current capture, setup, reminder, notebook, action and session code. I formed these conclusions without reading other council reports. Competitor claims below use six official sources checked today. No pricing assumptions or market-size claims.

## Decision: A, with a narrow first audience

Choose **A: everyday reminders and dated notes, with an optional narrow AI session monitor**. Position Sidefolk as “a small desktop companion that helps you remember the next thing and collect what you accomplished.” Target Mac-heavy individual contributors who already mean to keep a work log and regularly forget to capture small wins. Developers belong in that audience, but an agent connection must not be the qualification for getting value.

This is narrower than “an assistant for everyone.” The initial job is a short loop: **remember → receive a useful prompt → record one dated sentence → retrieve it when writing an update**. The evaluation notebook example is unusually concrete: the user knows why the record will matter later. A generic reminder manager has a much harder switching argument.

My confidence is moderate in this being the right experiment, low in established demand. The desktop character may create a memorable cue; it may also become decoration or an interruption. We have neither retention evidence nor evidence that people will maintain another task store.

**Release verdict: no public production launch. Conditional go for a small, explicitly experimental beta after the core native reminder checks and a usable distribution path pass.** More breadth cannot substitute for those gates.

## What is actually present

The recent redesign deserves credit. `src/dashboard/app.ts` puts Today, Reminders and Notes first, hides the AI navigation group until connected or visited, and leaves Actions in utility navigation. `setup.ts` has three steps, beginning with a real two-minute reminder; AI comes last and is optional. The README's five-step setup statement is stale. PLAN-V2's “nothing here is built yet” introduction and historical criticisms must not be mistaken for today's app.

Reminders now have local time parsing, repeating schedules, edit sheets, grouped lists, snooze, history and Undo. Notes are dated entries in topic notebooks, persisted as Markdown, with search, editing, copying and an optional summary workflow. `src/notes.ts` already connects writing reminders to a short capture prompt. This is enough surface area to test the proposed everyday loop.

The product is still much broader than that promise: calendar heads-up, morning brief, weekly wins, saved commands, an embedded terminal, project Sparks, multiple characters/styles and character import. Existing work need not be deleted, but every capability enlarges support and explanation costs. “Already built” is not a reason to feature it during onboarding.

The command field is a local grammar, not general conversation (`src/commands.ts`). Unknown requests do not silently spend model quota, which is a good trust decision. However, “Tell Pip” and a friendly face may imply much wider understanding. Examples help; failed requests must preserve the user's text and give a useful repair path. Notebook matching also needs scrutiny: ambiguous partial names currently select the most recently updated match (`matchNotebook`), risking a confidently saved note in the wrong place.

## The switching problem: six official sources

**Apple Reminders already covers the commodity promise.** Apple's documentation describes natural-language dates, repeating reminders, subtasks and changes appearing across configured Apple devices. “Type a sentence and get reminded” cannot be Sidefolk's main differentiation. Sidefolk's current independent local store sacrifices that cross-device continuity; a desktop-only reminder may be acceptable during focused work, but the beta must ask how often being away from the Mac breaks the job. [Apple: add or change reminders](https://support.apple.com/guide/reminders/add-or-change-reminders-remndc729e28/7.0/mac/26).

**Apple Notes already captures from other work.** Quick Note opens through Fn/Globe-Q or a hot corner and stays visible while open; it can collect Safari links and selected content. Sidefolk cannot claim that avoiding a full app switch is unique. Its possible advantage is consistently appending a dated event to the correct continuing topic, prompted at a useful moment. That is a workflow hypothesis, not proof that Apple Notes users will switch. [Apple: Quick Note](https://support.apple.com/guide/notes/create-a-quick-note-apdf028f7034/mac).

**Raycast competes directly for fast capture and actions.** Its Notes offers global commands to create, toggle and search notes, with Markdown support. Quicklinks launches saved URLs, paths and project folders; Script Commands turns personal scripts into searchable commands with hotkeys. Sidefolk's saved actions are useful convenience, but they are weak acquisition material against an installed launcher. “One sentence away” is a contested interaction, not a defensible category. [Raycast Notes](https://manual.raycast.com/notes), [Quicklinks](https://manual.raycast.com/quicklinks), [Script Commands](https://manual.raycast.com/script-commands).

**Agent attention already has a lightweight alternative.** Claude Code documents native desktop notification hooks when work needs input. A notification alone does not justify Sidefolk's integration and maintenance burden. Sidefolk must outperform that baseline through understandable project identity, a persistent request inbox, useful controls and reliable return to the correct session. Those benefits come from the app's implementation; the competitor source does not establish their uniqueness or adoption. [Claude Code: hooks guide](https://code.claude.com/docs/en/hooks-guide).

The resulting positioning is an **attention and recording habit**, with a companion as its interface. It is not a stronger task database, general notebook editor, launcher or coding environment. Sidefolk can coexist with those tools, provided people understand which information belongs here. Do not ask beta users to migrate their lives before proving the small loop.

## Contrary case: why B may win

The strongest argument against A is that reminders and notes face mature defaults while the Mac-only constraint matters immediately. A character is easy to like and easy to stop using. A weekly work log also has delayed payoff, so week-one enthusiasm can conceal weak long-term value.

**B, the developer-first companion, has a sharper urgent problem:** several sessions finish or need approval while the developer is elsewhere. The project companion, request review and return-to-session form a coherent workflow with an observable time-saving outcome. This audience may also tolerate setup better. Sidefolk's origin and substantial integration code support the direction.

But B carries continuous compatibility work, host-app limitations, permission complexity and competition from the tools' own attention interfaces. It should win only if real users repeatedly choose it over native notifications and their existing session workflow. Engineering investment and founder usage are not substitutes for that evidence.

I would switch to B if the beta shows persistent developer use and measurable attention benefits while everyday users abandon capture after novelty. In that case, change the positioning and default navigation explicitly; do not retain an “everyone” story over developer behavior.

**Reject C, the broad assistant shell.** A general promise increases expectations of language understanding, integrations and action coverage faster than this team can earn reliability. It also makes every failed command feel like a broken assistant. No evidence here supports that expansion.

## Keep, rework and defer

| Decision | Concrete scope and reason |
|---|---|
| Keep | Everyday navigation, one calm companion by default, local parsing, explicit AI use, Markdown notebooks, reminder editing/repeats/snooze and Undo. These serve the core loop and limit commitment risk. |
| Rework before beta | Complete quit/notification-click and sleep/wake acceptance on the actual release build. Show delivery limitations clearly when notification permission is denied. A saved reminder is not evidence that it will arrive. |
| Rework before beta | Make the work-log loop discoverable: a useful topic notebook, one optional recurring capture prompt and an obvious way to retrieve/copy the accumulated entries. Avoid introducing a second setup tutorial. |
| Rework before beta | Ask when notebook names are ambiguous; show the selected notebook in capture feedback. Keep original text recoverable when understanding or saving fails. A quiet misfile undermines six-month trust. |
| Keep, constrain | Existing session monitoring and request review for willing developer testers. State supported host behavior honestly; keep AI setup optional and do not imply every external session is equally controllable. |
| Defer promotion and expansion | New character work, more styles/import capabilities, embedded-terminal expansion, broad automation, agent teams, voice, screenshots and extra briefings. Existing advanced features can stay behind Settings or relevant destinations. |
| Investigate after evidence | Apple Reminders interoperability if duplicated task entry or phone access is the dominant reason to leave. Research that constraint before promising sync or rebuilding a task suite. |

## One week that can change the decision

Recruit **eight independent Mac users**, four fitting the everyday work-log job without agent setup and four developers running multiple sessions. If only two or three colleagues are available, use that as a rehearsal, not a demand verdict. Record prior tools and observe one baseline capture/retrieval attempt before installing. Avoid recruiting only people enthusiastic about desktop pets.

Use participant-kept counts, brief observation and opt-in diagnostic reports; do not collect notebook text or command content. Define metrics before starting and publish raw participant counts alongside percentages. These are proposed decision rules, not benchmarks validated for this market.

1. **Activation:** at least six of eight save a personally useful reminder and a dated note within ten minutes without facilitator rescue. The sample Stretch reminder does not count. Watch a native reminder arrive and be handled.
2. **Repeated usefulness:** at least three of four everyday participants capture useful items on three separate days and return on days six or seven without a researcher prompt. Count completed useful loops, not launches or animation time.
3. **Accumulating notes:** at least three everyday participants add three entries to one continuing notebook and retrieve/copy a relevant entry in under 30 seconds at week's end. Ask what they would otherwise have forgotten.
4. **Reliability gate:** zero lost notes, wrong-notebook saves or unexplained missed reminders in supported tested conditions; count every scheduled delivery and tested quit/wake condition. A small flawless sample still does not establish production reliability.
5. **Attention cost:** record companion hides, notification dismissals and specific interruptions. At least six keep Sidefolk installed and enabled voluntarily on day seven; hiding it while retaining useful notifications can still be success.
6. **Developer comparison:** at least three of four use session review or return on three days. Compare observed need-input-to-return times with their baseline, and document any wrong-session openings or duplicate interruptions. Do not claim time savings from self-reported excitement.

Ask each participant to choose at week's end: keep Sidefolk, return to the prior tools, or keep only its session feature—and explain the last concrete occasion driving the choice. If everyday repeated use and note retrieval pass, continue A for another three weeks to test the weekly habit. If only the developer cohort passes, run a focused B beta. If neither passes, stop adding features and revisit the job. One week cannot validate the six-month evaluation benefit or willingness to pay.

## Release sequence

First close the native reminder trust gap and release packaging. The coordinator reports passing current automated checks and a successful fresh build; that strengthens implementation confidence but does not complete native delivery acceptance, signing/notarization or participant use. An updater can wait for a supervised beta if replacement instructions are explicit; routine public distribution needs a credible maintenance path.

Next run the bounded beta with the current feature set, then make an explicit A/B continuation decision. Reserve the following work for the retention obstacle participants demonstrate. The most useful roadmap milestone is **people rely on a small loop twice without assistance**, not another pillar marked built. Public launch follows dependable delivery, understandable limits and repeated voluntary use.
