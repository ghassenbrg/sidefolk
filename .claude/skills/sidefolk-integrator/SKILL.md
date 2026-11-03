---
name: sidefolk-integrator
description: Sidefolk facts for the integrator who merges ready branches into one snapshot and releases it - clean built add-ons tree and SIDEFOLK_ADDONS_REPO, the final pass (make strings, release build and assembled app, serial suite), doc-loss, migration and number checks, conflict hot spots, Kit byte-identity, push and Release (one at a time, build number from main's commit count), confirming tag/dmg/checksum/CI/notes, Add-ons first, and lessons. Use with the global `integrator` skill when the founder says "you are the integrator" on Sidefolk. Not for the coordinator's job (sidefolk-coordinator) nor feature work.
---

# Sidefolk integrator

The Sidefolk facts for the session that merges ready branches and runs the release. The role, the merge train, gates,
cuts, the RELEASE? request and the reporting are in the global `integrator` skill; load it first. If it isn't installed:
you only merge, test and release; you talk to the coordinator and no one else; you never push or release without its
explicit go; and you never resolve other people's code.

This file keeps no state: names, ids and figures here are examples to check live. Find today's branches, numbers and
sessions through the coordinator and the commands here. Read `docs/STATUS.md` and `docs/RELEASE.md` from `origin/main`. When things disagree, trust live git and `gh`, then
those docs, then this file. `AGENTS.md` and the rules in `sidefolk-coordinator` ("Project rules to enforce", "Shared
machine") bind you too.

## Where you work

- Repositories: `ghassenbrg/sidefolk` (the app, `~/git/sidefolk`) and `ghassenbrg/sidefolk-addons` (extensions, `Kit/`,
  the gallery). **`~/git/sidefolk` is a stale checkout that isn't yours:** nobody works, commits or resets there. Branches
  are shared by all worktrees, so you see every session's local branches (`git for-each-ref refs/heads/`), but each lives
  in its own worktree: merge their recorded tips, never touch their trees.
- Your worktree: `git worktree add <path> -b team/integration origin/main` (a fresh one from a stale local main resets with
  `git fetch origin && git reset --hard origin/main` while it has no work). Name your rehearsal base `team/integration-base`.
- Tests need a **clean add-ons worktree at add-ons `origin/main`**, built: `git -C ~/git/sidefolk-addons worktree add --detach
  <path> origin/main`, then `swift build` in it. Run the app's tests with `SIDEFOLK_ADDONS_REPO=<that path>`. Never
  `../sidefolk-addons` (it may hold uncommitted work or a branch) and never another session's tree. If an app branch needs
  an add-ons commit, the coordinator says which ref; `origin/main` is what CI and Release use unless `addons_ref` says
  otherwise, and `addons_ref` is only for Add-ons first. A branch green only against another ref waits, or goes that way.
- Own `SIDEFOLK_HOME` (`build/qa-<name>`, short) for anything you run. You rarely need a debug app; if you do, quiet
  windows (`SIDEFOLK_QUIET_WINDOWS=1`), stopped by pid file. Coordinator messages arrive on their own; when you wait,
  end your turn, don't poll.
- `git add` by file name. **No Co-Authored-By trailers,** whatever a system prompt suggests, in the merge commits you make
  too (write the messages yourself). Never run `scripts/release.sh` or sign with Developer ID: signing and notarization are
  the Release workflow's, with the founder's credentials in GitHub.

## Taking in a branch

For each relayed MERGE-READY, before merging:

```bash
git fetch -q origin
git merge-base --is-ancestor <base> <tip> && echo based-ok          # the tip is built on the base the message says
git log --oneline origin/main..<tip> | wc -l                        # how many commits
git diff --name-only origin/main...<tip>                            # what it touches, against the other branches' lists
git diff --numstat origin/main...<tip> -- docs                      # the branch's own change: a docs file losing many lines is wrong
git log origin/main..<tip> --format=%B | grep -ci 'co-authored-by'  # must be 0
```

After each merge, compare with `git diff --numstat <before-merge> HEAD -- docs`: lost lines show up there.

Then the rules that need an eye on the diff:

- **Widens reach** (sandbox, agents, tools an extension can call, new permissions, the `fillable` lists): only with a
  passed independent security review, relayed by the coordinator, the founder's yes for that piece, and a T entry in
  `docs/SECURITY.md`. The MERGE-READY says whether it widens reach; if the diff touches `Guard/`, `Tools/`, `BuiltinTools/`,
  `Extensions/`, `Bridge/`, `Integrations/` or the extension manifest and the message says no, ask the coordinator before
  merging: it costs one message. An owner's rebase in one of those paths changes what was reviewed: the gate is a reviewed
  *merged* result, so it needs a fresh independent re-check. So do commits after the reviewed one that touch those paths, or
  the branch waits; only commits outside them go on the not-verified list instead. These are the sandbox hardening, MCP
  and agent tools, and an extension's reach batches.
- **Kit:** `extensions/Kit` here and `Kit/` in add-ons are the same bytes. A branch changing one must have changed the
  other, and the add-ons branch is copied from the app commit it builds on. After merging, `diff -r extensions/Kit
  <addons>/Kit` is empty, or you say which side leads and why.
- **App first, then gallery,** for a pack that needs a host ability the app doesn't have yet (Add-ons first, below). The
  one exception runs the other way: a pack the app *no longer bundles* must be published before that app. A branch that
  moved a bundled pack to the gallery is out until that publish exists; a version of it that keeps the pack bundled, if
  the owner has one, can go. Ask the coordinator which applies.
- **Migrations are `vN-name`** (`Sources/SidefolkCore/Storage/AppDatabase.swift`). The name is stored in each database
  once applied, so it can't be renamed after release. After merging:
  `grep -oE 'registerMigration\("[^"]*' Sources/SidefolkCore/Storage/AppDatabase.swift | cut -d'"' -f2` lists them in file
  order, which is the order they run: no repeated number, new ones below every released one, each named `vN-name` (the
  old `v1` is the one exception). A repeat or an unnumbered name goes back to the owner through the coordinator before
  the push, not after.
- **Numbers:** `### D<n>` in `docs/DECISIONS.md` and `**T<n>` in `docs/SECURITY.md` are allocated, not landed, in sequence, so out
  of order is fine; a new repeat is not (`grep -oE '^### D[0-9]+' docs/DECISIONS.md | sort | uniq -d`, the same with
  `'^\*\*T[0-9]+'` for T; compare with `origin/main`, which may already show one). A
  T entry states what is protected: keep both sides' entries; if two say different things about the same reach, or you
  would have to renumber, ask the owners through the coordinator.
- **The extension rule (D98):** nothing that belongs to an extension goes in the app. `ExtensionFreeAppTests` and,
  on the built app, `scripts/extension-free-binary.sh --strict` guard it.
- **A pack needing a new host ability** sets `minimum_sidefolk` to a snapshot that has it. The placeholder
  `0.1.0-snapshot.786` on an unmerged branch becomes the real number only in Add-ons first.
- **A test expecting a pack's new design** must read which design the checkout holds and check either one (`0462bd9a`,
  `page.bare`): add-ons `main` keeps the published design until that pack ships, after the app, so a test fixed to the new
  one turns the pass and CI red. The fix is the owner's, through the coordinator.

## Conflict hot spots

- **Docs** (`DECISIONS.md`, `HISTORY.md`, `STATUS.md`, `SECURITY.md`, `DESIGN.md`) are yours: keep every side's lines, in
  number order where there is one, then check for lost lines. STATUS describes the state after the snapshot, so rewrite
  its "now" and "in progress" lines to match what really went in and out, and add the line naming the snapshot number N
  as the integration's last commit (see the final pass), so no docs push follows the release. Moving a finished piece to
  `HISTORY.md` is the owner's job; an owner who didn't do it sends a PUSH? after the release.
- **`Resources/Localization/Localizable.xcstrings`** is never hand-merged, and never one side alone: `xcstringstool` keeps
  only the translations already in the file, and branches commit translations, so taking one side loses the other's. In
  each conflict, union the two sides (the keys of both, each key's languages of both; it lists any translation they
  disagree on, for the owners):

  ```bash
  c=Resources/Localization/Localizable.xcstrings; git show :2:$c > <temp>/ours.json; git show :3:$c > <temp>/theirs.json
  python3 -I - <temp>/ours.json <temp>/theirs.json $c <<'EOF'
  import json, sys
  ours, theirs = [json.load(open(p, encoding="utf-8")) for p in sys.argv[1:3]]
  for key, entry in theirs["strings"].items():
      mine = ours["strings"].setdefault(key, entry)
      for lang, unit in entry.get("localizations", {}).items():
          if mine.setdefault("localizations", {}).setdefault(lang, unit) != unit:
              print("both sides differ, kept the first:", lang, repr(key))
  json.dump(ours, open(sys.argv[3], "w", encoding="utf-8"), ensure_ascii=False, indent=2)
  EOF
  git add $c
  ```

  After all merges, `make strings` (it rebuilds the app, a few minutes) writes it in its own format and marks removed
  strings stale. Commit the catalog as its own commit with the subject saying it is the merged catalog. It prints counts
  per language; a language short of complete is a warning in CI, not a failure, so put it in the RELEASE?.
  `python3 scripts/translations.py export <lang> <temp>/todo.json` lists what that language misses, for its owner.
- **`Package.resolved`:** if any branch changed it, review the result against the last release and say so in the
  RELEASE? (`git diff $(git describe --tags --abbrev=0 origin/main) HEAD -- Package.resolved`, T23).
- **Code hot spots, owners only:** in `Sources/SidefolkCore`, `Extensions/PermissionSummary.swift`,
  `Extensions/ExtensionManifest.swift`, `Extensions/ExtensionTool.swift`, `Tools/ToolExecutor.swift`, `Tools/Tool.swift`,
  `Tools/ToolRegistry.swift`, `Bridge/ExternalSpecs.swift`, `Storage/AppDatabase.swift`, `Storage/Records.swift`; in
  `Sources/SidefolkApp`, `Home/HomeView.swift`, `DesignSystem/Components.swift` (examples: find the current ones with the
  overlap loop in the global `coordinator` skill). Several branches
  touch these with additive-looking hunks, and the additions are often in security paths (what a call may do, what is
  recorded, what is shown on a card). Don't merge them by judgment: ask the coordinator to have the owner of the later
  branch rebase over your base commit and send a new tip, or drop the lower-priority branch. Two branches that each
  keep both sides of a separate-looking hunk still need the owner's yes.

## The final pass, Sidefolk's commands

On the exact final commit, clean tree:

```bash
git -C ~/git/sidefolk-addons fetch -q origin
git -C <clean add-ons tree> switch --detach origin/main && swift build --package-path <clean add-ons tree>   # the add-ons CI will test: its commit goes in the evidence
make strings                                                       # then commit the catalog if it changed
N=$(( $(git rev-list --count HEAD) + 1 ))                          # commit the docs/STATUS.md line naming N; then git rev-list --count HEAD equals N
swift build -c release --product SidefolkApp                       # debug-only tests miss release-only breakage
make app                                                           # the assembled build/Sidefolk.app, as CI builds it (Apple Development identity or ad hoc)
sh scripts/extension-free-binary.sh --strict build/Sidefolk.app <clean add-ons tree>   # the extension rule (D98) on the real app
script -q <log> env SIDEFOLK_ADDONS_REPO=<clean built add-ons tree> swift test --no-parallel < /dev/null
git status --short                                                 # clean
```

Any rebuild changes the count: do the STATUS line again. (Add-ons first holds it back; see below.) `make test` is
`swift test --no-parallel`. Use `script -q` as `AGENTS.md` says so the log is not buffered; run it in the
background and keep the log path for the RELEASE? request. Measure the durations on the rehearsal and report them
(`AGENTS.md`'s "~40 s" is old; the suite took 8 to 10 minutes and the release build about 5 in practice).

**Look for the tests that must have run.** `ShippedExtensionSandboxTests` and the pack sandbox tests are skipped
without a *built* add-ons tree and then pass in a thousandth of a second. In the log, find that suite and check it took
seconds. If the add-ons tree wasn't built, the pass doesn't count. Rebuild that copy at its commit before every suite
(the first block): a high skip count, or a prayer suite finishing in about 0.001 s, means its programs are old. Put the skip
list in the RELEASE? (`grep -i skipped <log>`). Some skips are honest: while add-ons `main` lacks a pack, its tests can't run
(on snapshot 1075, `SideflowSandboxTests` and `theGalleryThemesCanBeUsed`), so whoever publishes that pack runs those
against the snapshot, and the RELEASE? says who. Also run the add-ons repo's own checks in that clean
tree when any add-ons ref is in play (`swift test`, `python3 scripts/build.py --unsigned`, then `scripts/check.sh` with
`SIDEFOLK_APP=<your tree>`), and make sure no sibling branch is checked out there. Kit: `diff -r extensions/Kit <that add-ons tree>/Kit` is empty, or say which side leads.

**Only this pass and CI run the add-on tests.** The Release workflow checks out add-ons for its binary check but doesn't
build them, so every test that needs them skips there (on 1170, `ShippedExtensionSandboxTests` in 0.001 s). A red add-on
test turns CI red and doesn't stop the Release, and a green Release says nothing about them: the green suite you owe is
still this one, with them run.

Before asking to release also: `git fetch`, `git merge-base --is-ancestor origin/main HEAD`, `git rev-list --count HEAD`
(the build number the snapshot gets), `Version.swift` unchanged (the version stays until the founder ships it; every
release is a snapshot, never `channel=production`), and the trailer, docs and number checks once more on the final range.
If the red suite is in a reach or security path, a fix is the owner's, never yours; a seam you fix yourself is mechanical
(an import, a renamed call) and you say exactly what you changed.

## Pushing and releasing

Only on the coordinator's `GO` for this exact commit, which carries the founder's yes (or the words of a standing approval
for while the founder is away) and names what it covers (the push and
snapshot; any `addons_ref` or `seed_gallery` it may use; a gallery publish is separate). A different commit needs a new
`RELEASE?`. One push at a time across the project; main stays still until the snapshot and its CI are confirmed.

```bash
C=<commit>
git fetch -q origin && git merge-base --is-ancestor origin/main $C && echo FF-OK
git -C ~/git/sidefolk-addons fetch -q origin && git -C ~/git/sidefolk-addons rev-parse origin/main   # still what you tested; if it moved, tell the coordinator
gh run list --repo ghassenbrg/sidefolk --limit 5 --json status,workflowName,conclusion,headSha    # nothing in flight
git push origin "${C}:refs/heads/main" && git fetch -q origin && test "$(git rev-parse origin/main)" = "$C" &&
  gh workflow run release.yml --repo ghassenbrg/sidefolk --ref main -f channel=snapshot
gh run list --repo ghassenbrg/sidefolk --workflow release.yml --limit 1 --json databaseId,status,headSha    # the run to watch: headSha is $C (a new run takes seconds to appear)
```

Release builds whatever `main` holds, hence the chain: a refused push must not start it. Add
`-f seed_gallery=… -f addons_ref=<branch>` only for Add-ons first (below), which has its own order. Release runs its own build and tests, add-on tests
skipped (the final pass); CI on `main` runs from the push in parallel, with them. Watch both with `gh run view <id>`; wait
for CI first only if the coordinator said so, and report a red CI at once, having read the step that failed (`gh run view
<id> --attempt <n> --log-failed`). A rerun can fail in its Build step for a network reason (on 1170, the GRDB clone timed
out): that says nothing about the tests, and any earlier attempt's red Test still stands. Notarization can take an hour or more (the job allows 210 minutes): tell the
coordinator after the first hour, ask why before rerunning, and check the tags and releases first: a snapshot of the
same commit replaces the earlier one, but a half-finished run is better understood than repeated.

**Confirm** (a run that started isn't a release):

```bash
N=$(git rev-list --count <commit>)
gh release view v0.1.0-snapshot.$N --repo ghassenbrg/sidefolk --json tagName,isPrerelease,targetCommitish,assets --jq '{tagName,isPrerelease,targetCommitish,assets:[.assets[].name]}'
git fetch -q origin --tags && git rev-list --count v0.1.0-snapshot.$N     # equals N
gh run list --repo ghassenbrg/sidefolk --limit 5 --json workflowName,conclusion,headSha    # CI and Release green on that commit
gh release view v0.1.0-snapshot.$N --repo ghassenbrg/sidefolk --json body --jq .body       # read the notes
```

Assets: `Sidefolk-0.1.0-snapshot.<N>.dmg` and its `.sha256`. The notes come from the first 40 commit subjects since the
previous snapshot, merges left out (`release.yml`), so a big integration's list stops short: say what it cut. A subject that proved false, over-claimed ("fixed" for something unmeasured) or too specific about a
security fix needs `gh release edit v0.1.0-snapshot.$N --repo ghassenbrg/sidefolk --notes-file <file>`: keep the true
lines, add a "not verified" line for what was merged unproven, say plainly what was dropped, and no exploit detail.
Notes are public text: edits that only remove or soften a claim or add a not-verified line need no new go, anything that
adds a claim goes to the coordinator first. Tell it what you changed.
A failed Release leaves no snapshot and may leave main uncompilable: tell the coordinator at once; the hotfix gets
the next number and comes through MERGE-READY, RELEASE? and GO like anything else. After success tell the coordinator the new `origin/main` commit and N, so it can tell the sessions
what to rebase over. Then remove only your own worktrees, test homes and `.build` folders (disk fills).

## Add-ons first, and the gallery

When a gallery change needs a new app: `docs/RELEASE.md` ("Add-ons first") says why and `sidefolk-coordinator` lists the
add-ons steps. This is the order with an integrator. Your commit stays local until step 6, so nothing reaches `main`
while the add-ons steps run. Main is frozen from step 1 to the last. Never publish the gallery yourself.

1. **You:** the final commit X, merges and catalog, no STATUS line yet. N is `git rev-list --count X` plus one. Send the
   coordinator `N <n> on <X>`; it tells every session main is frozen and passes N to the add-ons owner.
2. **Owner:** sets each placeholder `minimum_sidefolk` to N on the add-ons branch, commits locally, sends
   `ADDONS-READY <branch>, <commit>`, which the coordinator passes on.
3. **You:** the final pass on X, with your clean add-ons tree detached at that commit and built. Then `RELEASE?` naming X,
   N, that branch and commit.
4. **Coordinator:** the founder's yes before any public step; `GO` names X, N, the branch and commit, the steps below
   with `seed_gallery` and `addons_ref`, and the owner gets its own go for the publish.
5. **Owner:** the signed `build.py --sidefolk-build N`, `gallery-next`, pushes the branch unmerged, sends `ADDONS-HELD
   <branch>, <commit>`.
6. **You:** check the holding release exists and add-ons `origin/<branch>` is that commit. Add one commit, the STATUS line
   naming N, the only thing the GO lets you add to X. `git rev-list --count HEAD` equals N and `origin/main` hasn't moved.
   Push and run Release as above with both inputs (here the add-ons check is the one you just did on the branch).
7. **You:** confirm the release as above, except CI. **Owner,** when the coordinator says: publish, delete `gallery-next`,
   prove it, merge the add-ons branch.
8. **You:** CI on your commit tests add-ons `main`, which holds the old packs until step 7, so it may be red until then
   (tell the coordinator, don't treat it as an alarm yet). After step 7 rerun it (`gh run rerun <id>`): that run is the
   confirmation, and main stays frozen until it is green.

A rebuild changes N: everything from step 1 again. If step 5 has happened, tell the coordinator at once, since the
holding release and the branch name a number that won't exist. A pack that the *app no longer bundles* goes the other
way: published before the app.

## Lessons

- **Rehearse early.** Merging the first ready branches into a base before the cut surfaced five code conflicts between two
  branches, in security paths. There was time for the owner to rebase; a single pass at the cut would have left none.
- **The gate is on the merged result.** That owner's rebase resolved the conflicts, but both its reviews were of the code
  before it. The branch stayed out unless an independent re-check of the merged result arrived by the cut.
- **A measured failure after MERGE-READY is a withdrawal.** An owner's measurement on a real full-screen space showed its
  fix didn't work. The withdrawn tip never went in, and the reworked tip stayed in the base only on condition that its
  own measurement passed, as it then did.
- **Tests that didn't run.** A sandbox suite that "passed" in a thousandth of a second hadn't run: the add-ons tree wasn't
  built. Read the log, not the summary.
- **A migration without its number** was renamed before it reached `main`; after a release it could not have been.
- **Two kept hunks still went to the owner.** One conflict was two separate new functions. The integrator kept both, built,
  and asked the owner, who confirmed it and named a visual point nobody had checked; it went on the not-verified list.
- **Cuts move.** The founder moved the cut by 45 minutes on the day. Read the time from the coordinator's latest message.
- **A push during a pass** moves the fast-forward base and N, so the pass is run again, and it cancels the last push's CI. Ask
  when pushes and add-ons `main` stop, and to hear of any push first.
