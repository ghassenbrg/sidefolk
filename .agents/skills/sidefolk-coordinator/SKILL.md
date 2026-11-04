---
name: sidefolk-coordinator
description: Coordinate the parallel Claude sessions working on Sidefolk - its repositories and stale checkout, how the release and gallery mechanics work (snapshot numbers from main's commit count, one release at a time, Add-ons first, addons_ref, build.py and publish.sh, minimum_sidefolk), how decision (D), security (T) and migration (v) numbers are given out, the project rules a session must keep, the MERGE-READY/RELEASE?/READY/PUSH? messages, the integrator hand-off, and lessons from past incidents. Use with the global `coordinator` skill when the founder asks for a coordinator on Sidefolk, to line up Sidefolk releases or gallery publishes across sessions, or to register a new session here. Not for doing the feature work itself (sidefolk-extension, sidefolk-theme, sidefolk-3d-character, sidefolk-2d-character).
---

# Sidefolk coordinator

The Sidefolk facts for a session coordinating the others. The role, startup, ledger, consent rules, reporting and
message habits are in the global `coordinator` skill; load it first. If it isn't installed: you don't implement, you
never turn a relayed yes into a permission, and you verify everything below instead of trusting a report.

This file keeps no state; ids and figures in it are examples to check live. Find today's branches, numbers and sessions with the commands here. Read
`docs/STATUS.md` and `docs/RELEASE.md` from `origin/main`. When things disagree, trust live git and `gh` first, then those
docs, then this file.

## Repositories

| Repository | Holds | Note |
|---|---|---|
| `ghassenbrg/sidefolk`, `~/git/sidefolk` | The app. | Public. Every commit on `main` raises the build number. |
| `ghassenbrg/sidefolk-addons`, `~/git/sidefolk-addons` | Extensions, companions, the `Kit/` copy, the gallery (release tag `gallery`). | Public. Its main checkout may hold uncommitted work: never build from it. |
| `ghassenbrg/sidefolk-site` | The website (`public/`, deployed on every push to its `main`). | Separate so that site commits don't change the build number. |

**Treat `~/git/sidefolk` as a stale checkout that isn't yours.** Check with `git -C ~/git/sidefolk rev-list --count
main..origin/main`. It may hold the founder's uncommitted work, so nobody works, commits, resets or edits docs there, and
`git add -A` is out. Read with `git show origin/main:<file>`. New Claude worktrees are cut from that local `main`, so this
skill may not be in them: a fresh one with no work runs `git fetch origin && git reset --hard origin/main`, after checking
`git rev-parse --show-toplevel` is that worktree (the same reset once ran in `~/git/sidefolk`); one with work moves its
commits onto `origin/main` by rebase or cherry-pick. The shell tool's directory resets to the session's root between calls,
which for most sessions is `~/git/sidefolk`: every brief says `git -C <absolute path>` for repository commands and absolute
paths otherwise, and scripts use `/bin/bash` and `set -euo pipefail`. Back up
uncommitted work under `sandbox/` (git ignores it) before any cleanup.

**Never touch** `/Applications/Sidefolk.app`, the founder's real data, or their real agent configs (`~/.claude*`,
`~/.codex`), not even for read-only checks of `~/.codex`. On any other `SIDEFOLK_HOME`, Connect writes stand-ins in
`$SIDEFOLK_HOME/agent-configs/` (D86).

## Rebuild the state

```bash
git fetch -q origin
git log --oneline -3 origin/main
git rev-list --count origin/main                                  # the build number of main as it stands
gh release list --repo ghassenbrg/sidefolk --limit 3              # latest snapshots
gh run list --repo ghassenbrg/sidefolk --limit 5 --json status,workflowName,conclusion,headSha
git worktree list
git for-each-ref --format='%(refname:short)' refs/heads/          # branches, shared by all worktrees
git -C ~/git/sidefolk-addons fetch -q origin
git -C ~/git/sidefolk-addons log --oneline -3 origin/main
gh release view gallery --repo ghassenbrg/sidefolk-addons --json assets --jq '.assets|length'
```

## Numbers

Three sequences, all collision-prone. Read the highest in use, across main and every branch:

```bash
for b in origin/main $(git for-each-ref --format='%(refname:short)' refs/heads/); do
  d=$(git show "$b:docs/DECISIONS.md" 2>/dev/null | grep -oE '^### D[0-9]+' | tr -dc '0-9\n' | sort -n | tail -1)
  t=$(git show "$b:docs/SECURITY.md" 2>/dev/null | grep -oE '^\*\*T[0-9]+' | tr -dc '0-9\n' | sort -n | tail -1)
  v=$(git show "$b:Sources/SidefolkCore/Storage/AppDatabase.swift" 2>/dev/null | grep -oE 'registerMigration\("v[0-9]+' | grep -oE '[0-9]+$' | sort -n | tail -1)
  echo "D$d T$t v$v $b"
done
```

This shows only what's committed. A session may hold a block it hasn't used yet, and a block's unused numbers stay
reserved, so ask sessions too. Numbers can reach main out of order, because they're allocated, not landed, in sequence.

- **D (decisions, `docs/DECISIONS.md`):** give each session a block of four to six, above everything in use or given
  out. Keep the blocks in the ledger and tell each new session which are taken.
  Blocks are decided when a session starts and noted in the ledger. Unused numbers stay reserved: the homepages held D170–D179
  and used D170 only.
- **T (`docs/SECURITY.md`):** one at a time, when a session has new reach to record.
- **v (migrations, `Sources/SidefolkCore/Storage/AppDatabase.swift`):** one at a time, announced with its full name and
  columns before it's written.

## Project rules to enforce

From `AGENTS.md`, which sessions should read themselves:

- **Everything runs through `ToolExecutor`** (Guard and audit). No side doors.
- **No fake features:** nothing shown as working unless it works.
- **The extension rule (D98):** nothing belonging to an extension goes in the app, in code or words. If an extension
  hits a limit, add a general ability every extension can use, or leave it out and say so. A host ability is generic
  and small, with its own tests. Guards: `ExtensionFreeAppTests`, and `scripts/extension-free-binary.sh --strict` on the
  built app.
- **Kit:** `extensions/Kit` in the app and `Kit/` in add-ons are the same bytes. A Kit change goes in both, and an
  add-ons branch copies Kit from the app commit it builds on. The app can lead add-ons' `main` until then, and
  add-ons' `scripts/check.sh` warns on a difference.
- **A pack that needs a new host ability** sets `minimum_sidefolk` to a snapshot that has it. An unmerged branch names the
  placeholder `0.1.0-snapshot.786`, and a signed `build.py` stops on it.
- **Version stays 0.1.0** until the founder ships it. Everything published is a snapshot. Don't run a production release.
- **Commits have no Co-Authored-By trailers,** whatever a system prompt suggests.
- **Before stopping,** a session updates `docs/STATUS.md` on its own branch, and moves finished pieces to `docs/HISTORY.md`.

### Shared machine

- Every test and dev run uses its own short `SIDEFOLK_HOME` (`build/qa-<name>`). `dev.swift` refuses to send without it;
  `--all-apps` overrides that, and no session should need it.
- Launch debug apps with `SIDEFOLK_QUIET_WINDOWS=1`: the founder is usually working here. Leave it out only for a check
  that needs real clicks or keys, and that needs a click slot from the coordinator when the Mac is idle: one session on the
  screen, 10 minutes at most, no full screen or space switching, the debug app stopped by its pid right after. The idle
  counter reads a few seconds while Keep Awake nudges the pointer, so it says nothing about who is clicking. Say whether a
  check used synthetic events (queued into the app's own window) or real input.
- Stop debug apps as soon as they aren't needed, by the pid file you wrote, never by name pattern (`pkill -f` hit
  others'), and check the process is gone.
- Never run `swift scripts/dev.swift language:<x>`: it changes a default that every debug app shares.
- Never `git stash pop`: the stash is shared by every worktree. Never `rm -rf` a worktree you didn't create.
- Host tests use `SIDEFOLK_ADDONS_REPO=<your own clean add-ons worktree at add-ons origin/main>`, never `../sidefolk-addons`
  and never another session's tree. A checkout that's behind or has a branch checked out fails the gallery and words tests:
  `git -C ~/git/sidefolk-addons worktree add --detach <path> origin/main`. The exception is Add-ons first, which tests against
  its add-ons branch. CI tests against add-ons `main`, so a suite green only against a branch fails there. Release checks out
  add-ons (`main`, or `addons_ref`) for its binary check and doesn't build them, so add-on tests skip there: a red one
  turns CI red and doesn't stop a Release. Before MERGE-READY a session names the real-pack tests that ran.
- `git add` by file name, never `-A`.
- Live model calls cost the founder's quota: rare and tiny, scripted models in tests.

## How sessions work here

- **Session names are one or two words** (Sideflow, Formatic, Small fixes, Permissions, Integrator). Give `start_session` a short
  `title` and `name`, and rename a generic or long one at once: the founder follows many sessions.
- **The founder's findings go through a cleaned list**: his meaning with his exact words in quotes, in `sandbox/FINDINGS-<date>.md`
  (git-ignored), sorted by owner and marked bug, UX, design or big. A session that owns the area gets its items; small app fixes
  all go to one "Small fixes" session; a big new topic gets its own. Send bugs first, then clarity, then design; a large redesign
  starts as a written plan with real-app pictures, which you answer for the founder. Tell him who got what.
- **A session started with a worktree is cut from the stale local `main`.** Its brief says `git fetch origin`, then
  `git checkout -B <branch> origin/main` in its own worktree, before anything else.
- **Relay "keep clear" file lists.** A session that lists the files it is changing has the list sent to every session nearby that
  day. Two sessions in the same Guard or Kit files take turns: the one further along lands first, the other does inventory or design.
- **One worktree and one branch per task, from `origin/main`, local only.** Branches are usually `team/<name>`, with a
  matching branch in add-ons if needed.
- **Before writing code:** branch, files, and every new manifest key, Kit API, bridge method or tool name go to the
  coordinator.
- **`RELEASE? <branch>, <commit>, tests green, release build OK`** once the session holds the founder's explicit yes for
  that piece, with the founder's words and the end of the test run. CI doesn't run on branches, so that log is the evidence.
- **`READY: <branch>, <commit>, tests green, release build OK`** for a fix that rides in another session's release: its
  own branch and commit. The releasing session includes it and reruns everything on the combined commit.
- **`PUSH? <branch>, <commit>, files`** for a docs commit to `main`. It still raises the build number, so it waits while a
  release is pending, and it rebases before going.
- **Anything that widens reach** (sandbox, agents, a new permission) needs independent security review rounds until one
  comes back clean, a T entry, and the founder's yes, on top of real checks in the debug app. The reviewer gets the code,
  not the session's conclusion.
- **Real checks count.** A session names what it ran for real and what it didn't. "Not verified" lists are expected.

**With an integrator** (global skills `coordinator` and `integrator`, Sidefolk facts in `sidefolk-integrator`), sessions
don't land their own work: each sends you MERGE-READY in the global skill's form, and you check it and pass it on. Sidefolk's
own checks before passing: the Kit pair, the migration name (`vN-name`, unique), the add-ons ref it needs, the T entry and the
founder's yes for anything that widens reach. From the cut on, `PUSH?` and `READY` wait or become MERGE-READY. The answer to
the integrator's `RELEASE?` is `GO` (the global skill's form), not `RELEASE OK`, and a yes belongs to that commit. A gallery
publish needs its own yes: it comes after the snapshot that carries its host abilities or, for a pack the app no longer
bundles, before that snapshot. A standing approval (global skill, "While the user is away") can stand for these yeses if its
words cover them: quote them. One night's order: MERGE-READY cutoff, direct pushes stop, add-ons `main` stops 15 minutes before
the last pass, `RELEASE?`, `GO`. A second push to `main` also cancels the first's CI (`cancel-in-progress`), so read CI on the newest commit.

Starter for a new session's rules message: the global skill's template, filled in with the base commit, a D block, the
migrations taken, the overlaps nearby, and the "Shared machine" list above.
With an integrator present, say: "Send me MERGE-READY (not RELEASE?), in this form: <the global form>. Don't message the
integrator; I relay and bring its questions to you. After MERGE-READY, new commits or a measured failure mean UPDATE, with
suite and review for the new tip, or WITHDRAWN, at once."


## Releasing an app snapshot

With an integrator, it is "the session" in the steps below for the combined commit, and your `GO` stands for `RELEASE OK`.

The tag is `v0.1.0-snapshot.<build>`, and the build number is `git rev-list --count` of the commit. **Only one at a time**,
and main stays still from `RELEASE OK` until the snapshot and its CI are confirmed.

**The session, on the exact commit, before asking:**

```bash
make strings                                       # first: commit Resources/Localization/Localizable.xcstrings if it changed
swift build -c release --product SidefolkApp       # debug-only tests miss release-only breakage
SIDEFOLK_ADDONS_REPO=<clean add-ons worktree> swift test --no-parallel
```

If a suite is rerun because of a failure, it's rerun in full.

**The coordinator, before `RELEASE OK`:** the global skill's checks (fast-forward, commit list, docs `--numstat`, no
trailers, nothing running and the last runs green, on `--repo ghassenbrg/sidefolk`), the founder's yes, then
`git rev-list --count <commit>`, the expected snapshot number.

**The session lands it:**

```bash
git push origin <commit>:refs/heads/main && git fetch -q origin && test "$(git rev-parse origin/main)" = "<commit>" &&
  gh workflow run release.yml --repo ghassenbrg/sidefolk --ref main -f channel=snapshot
```

**Confirm** (a run that started isn't a release):

```bash
gh release view v0.1.0-snapshot.<N> --repo ghassenbrg/sidefolk --json tagName,isPrerelease,targetCommitish,assets --jq '{tagName,isPrerelease,targetCommitish,assets:[.assets[].name]}'
git fetch -q origin --tags && git rev-list --count v0.1.0-snapshot.<N>   # equals N
gh run list --repo ghassenbrg/sidefolk --limit 5 --json workflowName,conclusion,headSha    # CI and Release green on that commit
gh release view v0.1.0-snapshot.<N> --repo ghassenbrg/sidefolk --json body --jq .body      # read it
```

The assets must be `Sidefolk-0.1.0-snapshot.<N>.dmg` and its `.sha256`. The notes come from commit subjects, so a subject
that turned out false needs `gh release edit <tag> --notes-file <file>`. A failed release leaves no snapshot, and
main may not compile: tell everyone not to branch or rebase until a hotfix lands, and the hotfix gets the next number.
Then tell every active session the new `origin/main` and what to expect on rebase. Release workflow runs have waited a
long time on notarization; check why before rerunning.

## Add-ons first

When a gallery change needs a new app (`docs/RELEASE.md`, "Add-ons first", D98). Publishing replaces the gallery's packs,
and there's no rollback but a revert, so the app is proved first. One `RELEASE?` covers all these steps and needs the
founder's yes for both the app and the gallery, asked before step 1 (steps 1, 4 and 5 are public). **Main is frozen from
step 1 until step 8.**

With an integrator, `sidefolk-integrator` has the order, and it differs in two ways: step 1 stays local until step 6, with
the same number, and the founder's yes comes after the add-ons commit exists, before steps 3 to 5. It does the app side
(steps 1 and 6) and the add-ons owner, through you, the rest. You freeze main on its `N <n> on <commit>`, pass N to the
owner, pass back `ADDONS-READY <branch>, <commit>` and later `ADDONS-HELD <branch>, <commit>`. Your `GO` names the commit,
N, each step, the add-ons branch and its commit, and the owner gets its own go for the publish. CI on the pushed commit
tests add-ons `main`, so it may be red until step 8; rerun after step 8, and that run is the confirmation.

1. Merge to `main`, read `git rev-list --count origin/main`. `N` is that plus one more commit, the last before the build
   (a `docs/STATUS.md` line naming `N`). Before step 6, check that `git rev-list --count origin/main` equals `N`.
2. In add-ons, change each placeholder `minimum_sidefolk` to `0.1.0-snapshot.N`.
3. Build, no publish, in a clean add-ons worktree: `python3 scripts/build.py --sidefolk-build N`.
4. `gh release create gallery-next dist/*.zip --prerelease` in add-ons, a holding release.
5. Push that add-ons branch, unmerged, so the Release's binary check reads the packs this app goes with. The add-on tests
   ran earlier, in the pass against this branch.
6. Run Release with `seed_gallery` and `addons_ref`:
   `gh workflow run release.yml --repo ghassenbrg/sidefolk --ref main -f channel=snapshot -f seed_gallery=https://github.com/ghassenbrg/sidefolk-addons/releases/download/gallery-next -f addons_ref=<branch>`
7. Only when that release exists: publish the same `dist/` with `scripts/publish.sh`, delete `gallery-next`, and prove it with
   `python3 -I <app>/scripts/seed-packs.py fetch <temp> --required`.
8. Merge the add-ons branch to add-ons `main` and push, so later tests and builds see it. `docs/RELEASE.md` doesn't list this
   step; confirm the order with the session running it.

## Publishing the gallery alone

When no new app is needed. The queue has one slot, separate from the app's, but an app release and an upload shouldn't
run together. One add-ons builder at a time too: `publish.sh` replaces the whole catalog and deletes packs it doesn't name,
so the next publisher rebases over add-ons `main`, rebuilds and retests. A Kit change lands in the app first, so `diff -r` differs until
the add-on lands: say which side leads. A pack-only change still runs the app's whole suite against that pack, with no name filter. A session
holding the founder's yes, in a **clean add-ons worktree** (`build.py` packs the whole checkout):

1. `swift test --no-parallel`, then `python3 scripts/build.py --unsigned`, `SIDEFOLK_APP=<clean app worktree> scripts/check.sh`, and
   `<app>/scripts/extension-strings.py check <extension folder>…`.
2. `RELEASE? <branch>, <commit>, tests green`. The coordinator checks it fast-forwards add-ons `origin/main`, then answers.
3. Merge to add-ons `main`, push, `python3 scripts/build.py --sidefolk-build <latest snapshot>`. A signed build uses the
   Developer ID in this Mac's keychain, and only runs after the founder's yes for the publish. The app's own signing and
   notarization stay in the Release workflow.
4. **Catalog dry-run diff against the live one,** before publishing. Only what was meant should change:

   ```bash
   gh release download gallery --repo ghassenbrg/sidefolk-addons -p catalog.zip -D <temp>
   unzip -p <temp>/catalog.zip catalog.sidefolkaddon/Contents/Resources/catalog.json > <temp>/live.json
   unzip -p dist/catalog.zip catalog.sidefolkaddon/Contents/Resources/catalog.json > <temp>/new.json
   python3 -I - <temp>/live.json <temp>/new.json <<'EOF'
   import json, sys
   a, b = [{x['id']: x for x in json.load(open(p))['addons']} for p in sys.argv[1:3]]
   for i in sorted(a.keys() | b.keys()):
       x, y = a.get(i), b.get(i)
       if x != y:
           print(i, 'added' if not x else 'removed' if not y else sorted(k for k in x.keys() | y.keys() if x.get(k) != y.get(k)), (y or x).get('version'), (y or x).get('minimum_sidefolk'))
   print(len(a), '->', len(b))
   EOF
   ```

5. `scripts/publish.sh`, then fetch the live catalog again and check its digest, the entry, its `minimum_sidefolk`, and that
   nothing else moved. The CDN can serve the old catalog for about two minutes, so an old answer right after isn't a failure.
   Any queued add-on rebases over the new add-ons `main` next.

A gallery yes doesn't cover an app release, or the other way round.

## Lessons

- **The stale checkout.** Sessions started from it, read docs there, and wrote `docs/STATUS.md` entries into it, which then had
  to be undone line by line. Every rules message now states the base commit.
- **A fix released without a measurement.** A full-screen window change (D137) shipped "not yet proven" with an idle-Mac test
  still to run. The test showed it didn't work, in old and new builds, and the first version of the test couldn't tell them
  apart. The notes got a known-problem line at the top, and the founder heard before trying it. Check that a test can fail;
  say "unproven" until it's measured.
- **Real checks found what reviews didn't.** A session's real card checks on the final tree contradicted something it had told the
  founder about what a person would see. Reviews and unit tests had passed. The founder got the corrected picture as a question,
  with a safe default. Don't accept unit tests for a claim about what a person sees.
- **The forgotten go.** A session said it would wait for a signal once two things landed, then sat idle after they did. Nobody had
  recorded the promise. Keep the owed list.
- **A release-only break.** Tests passed, but code had landed inside `#if DEBUG`, so the release build failed and left no snapshot.
- **Unscoped commands.** `dev.swift` without `SIDEFOLK_HOME` reached other sessions' apps. It refuses now. A pressed card blamed on
  this was the founder's own click: ask before concluding, and tell everyone when it's settled.
- **A name filter hid the test that mattered.** A pack's "452 of 452" left out `everyGamesScenesRead`, which its new menu entry
  broke, and it surfaced only after the pack was live. Run the app's whole suite against a pack.
- **A suite that wasn't.** A wrong relative path broke every `cd` in a homepages script, so `make strings`, a release build and
  a filtered test ran in `~/git/sidefolk`, and the suite reported as running never ran. The owner said so at once. Two hours
  later another session's `git reset --hard` hit the same checkout; a backup under `sandbox/` meant nothing was lost.
- **Reading the workflow beats remembering it.** A fallback was withdrawn on the belief that Release runs the add-on tests.
  It doesn't build them (`release.yml`).
- **Words typed in a session.** Some sessions published only on the founder's own sentence there ("Publish Sideflow"), until
  the founder typed in those sessions that the coordinator's permission was enough. Permission checks stayed theirs.
- **Release tags sort as text** on GitHub's page and in its list: 961 sat above 1170. Read the list by version number, and keep
  the digit count (four digits hold to 9999). The app sorts by version, so only people reading the page were misled, and the
  founder drafted the old three-digit releases.
- **A site in the main repository** would have raised snapshot numbers and broken the Add-ons first freeze, so it has its own.
- **A session that wants the founder's real data or synthetic input** (the real audit or log, a scripted drag) asks you. You may
  say yes under his standing order, with limits: read only, only the named rows, report counts and kinds and never file names or
  contents; synthetic input only after 15 minutes without any, aborting on any input, in a scratch window of a debug app, one
  screen user at a time, never answering a system security dialog. The session's own permission check still decides.
- **A cause found by reading the code is not a finding** until a run or a test shows it: ask which it is.
- **Every new rule or lesson goes into the skills the same day**: the global ones in the `agent-skills` repository
  (`~/.claude/skills` links to it), the project ones here.
- **Security text in this public repository** follows the global skill's hygiene section. This file is public too.
