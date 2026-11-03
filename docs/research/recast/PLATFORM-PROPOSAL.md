# Formatic: proposal for options A, B and C

2026-11-03. For review by Sideflow and the coordinator. Nothing is built, and the founder hasn't given the go to build.
Read from `origin/main`, `team/noor` and `team/sideflow-host` (the code excerpts are from those branches, not run). Base any work on
`origin/main` after Noor lands. Questions for reviewers are in section 4.

## 1. Option B (D141): a list of files, granted one by one

**Proposal: a new tool key, `file_lists`, leaving `paths` as it is.**

```json
"tools": { "convert": { "title": "Convert files", "file_lists": { "files": "read" }, "timeout": 300 } },
"drops": [{ "id": "convert", "title": "Convert", "kinds": ["file"], "tool": "convert", "input": { "files": "{values}" } }]
```

**Why not raise the cap of 4.** The cap counts parameters, not files, and each parameter holds one string
(`ExtensionTool.scope` and `run` use `input.string(param)`; `refusal` rejects anything else). A higher cap still wouldn't
allow a list of any length.

**The rules**

- Read only. A tool has at most one list, of at most 64 files. Its entries don't count toward the 4.
- Every entry is a full path to a regular file. A folder or a relative path refuses the whole call, before any card.
- `scope(for:)` adds each entry to `readPaths`, so Guard checks each one as it checks a path today.
- `run` canonicalises each entry, checks it again, and adds one `ExtensionFolderGrant` per file.
- An entry that fails refuses the whole call, so a call never half-runs.
- `{value}` is unchanged. `{values}` is new and is valid only under a `file_lists` argument (`ExtensionAbilityRules`).
- For several dropped files, only `{values}` offers appear, and every file must match the offer's `patterns`.
- Any caller that names paths in its input gets only Guard's normal shared-folder check.

**Conditions from Noor's review** (from reading the code, nothing run). What makes `pickedFile` safe isn't `caller == .user`, since every page click is `.user`. It is that only the host's panel code sets it, from a path the system returned. `pickedFiles` must hold to the same:

1. It is set only by the panel or drop code, from URLs the system handed over, never from tool input. A test proves that a page or model call naming paths gets no grant.
2. The `file_lists` argument is overwritten with exactly those paths, not merged. `pathParameters` stripping runs on drops too, because an offer's `input` template could otherwise plant a path.
3. Each entry is canonicalised and then checked to be a regular file, and Guard's forbidden places hold per file, so a dropped symlink to `~/.ssh/...` is refused.
4. The grant lasts for that one call. It doesn't carry into a retry after a card, or into a plan or flow step. Noor is checking this with Sideflow.
5. History shows every file. The card can summarise, the audit can't.

**A drop isn't quite a pick.** A panel shows the person what they chose, but a drag can carry more files than its image shows, and another app can start one. So:

- A card worded by Sidefolk names the extension, the file count and the names. An offer's title is the extension's own words and can't be the only thing said.
- If the extension has `network`, the card says it can send these files on. Formatic has no `network`, but this rule is general.
- **The card is the yes.** Noor, who owns T43, confirmed that one card is enough and no second one is needed, because Sidefolk draws a drop card, unlike a page's `allow`. These conditions apply:
  - Sidefolk's words aren't controlled by the extension and are visible before the choice.
  - Nothing is pre-selected, and Return doesn't confirm.
  - An offer's title is shown as what the extension says it does, set apart from Sidefolk's lines. It must not read as Sidefolk's own, or restate or contradict the file count.
  - When names are shortened, the exact total stays visible and every name can be reached.
  - Clicks are ignored for a brief moment after the card appears, because it opens under a mouse that has just released a drag.
  - T43 states that the card is the yes, and a test proves that a drop with no choice made runs nothing.

**Docs:** T12 gains the extension as a second reader ("one-turn read of that file only" is about the model today), T43 records the change, and drops get their own sentence.

**What changes in code**

| Where | Change |
|---|---|
| `ExtensionManifest`, `ManifestValidator`, `ExtensionAbilityRules` | The key, its rules, `{values}` |
| `ExtensionTool` | List handling in `scope`, `refusal`, `run`, and the card's words ("12 files in Downloads") |
| `ExtensionHost.pathParameters` | Include list names, and strip them on drops as well as Noor's `file` action. **Without this, a page or an offer's template could plant extra files in the input** |
| `ToolExecutor.execute` | Add `pickedFiles: [String] = []`, read only, `caller == .user` only. Additive, so `pickedFile` and the Noor and Sideflow callers don't change |
| `Attachment`, `CompanionWindowController:942`, `DropCard` | Hold several files rather than `urls.first`. Dropping on Ask for the AI stays a one-turn read per file (T12) |
| `AppCoordinator+Entries.perform` | Pass the dropped files as picked files |
| Kit | `Schema.paths`, `args.paths`, and a sandbox test |

**How drops run today, and the proposed design** (checked on `team/sideflow-host`, not run).

- `perform(_: ExtensionDropAction…)` goes through `runLocal(.extensionCommand)`, and `LocalIntentRunner.swift:160` runs the tool as `caller: .command(extensionId:)`.
- `ToolExecutor` honours a picked file only for `caller == .user`, so passing `pickedFile` there wouldn't be enough.
- For an unshared file, Sideflow reports that Guard's folder check asks with a card offering access to **the whole folder**. That is wider than one file, so this design is narrower than today's behaviour.

**Decided by the founder: all drops** (section 4). Every offer with `kinds: ["file"]`, using `{value}` or `{values}`, runs its tool directly as `.user` with the dropped files as picked files, not through `.extensionCommand`. Sidefolk's card applies to all of them, including the `network` warning. Running these as `.user` is a security decision for D141's review.

- **Unchanged:** link and text drops. Folder drops also stay as they are, because the question was about files and Noor's conditions require a regular file.
- **A `"write"` parameter:** the grant is read only, so a file dropped under a `"write"` parameter still gets Guard's normal check.
- **Effect on shipped and planned extensions today: none.** On `sidefolk-addons` `origin/main` (`3549a8b`), the only real `drops` are Miraya's, and they're links. The coordinator checked `team/noor` and the Sideflow branches and found no file drop there either. Images, PDF Tools and Archives declare no drops, so earlier notes saying they would change were wrong. The rule applies to future extensions, and to any local extension that declares file drops.

**D141's independent review must cover:**

- A local third-party extension that declares a file drop gets a read of any dropped file for one call, with only Sidefolk's card as the yes. What does the card show when the offer's title is hostile?
- The `network` warning.
- `runSkipped` with no grant: a clear message, and no fallback to the whole-folder card.

**A later retry gets no grant.** `runSkipped` (the "Run it now" path) calls `perform` with no picked file. That fits Noor's condition 4: the grant ends with the call, and a retry gets no read of the dropped files. It must end in a clear message, and it mustn't fall back to the whole-folder card. Not yet traced.

**Compatibility**

- **Sideflow's flows and plans** (Sideflow's review, from reading its branch): no flow step or plan reads `paths`. Plans use `tool.scope(for:)`, so each listed file gets Guard's normal check and no flow gains reach.
- **Lists in plans always ask.** A list is compared byte for byte, so the same files in another order get a card. No slot may sit inside an array (`slotless`), and a plan step's list JSON can't exceed 300 characters (`objectsFit`), so a list of more than a few paths always gets a card. **Don't plan on unattended lists.** A flow that converts a whole batch will ask each time, which affects the idea of building watch folders as a flow.
- **Older Sidefolk copies:** strict decoding refuses an unknown key, so an older copy refuses the pack rather than running it wrongly. That needs the usual minimum-version handling (D83).

**The limit of 64:** measured under a hand-built profile with one `READ_n` parameter per file, as the real profile builds them. At 4, 64, 128 and 256 grants, every granted file could be read and an ungranted file in the same folder was refused, in about 40 to 120 ms at 64 and above (the first run took 261 ms). The real extension host wasn't used, so the sandbox test must repeat this.

## 2. Option A (D140): the host places the file, so the sandbox doesn't widen

**This adds no new sandbox rule**, which the coordinator agrees. The program never gets write access beside the original. It is a new capability in the host, though: Sidefolk copies a file the extension wrote into one of the person's folders.

1. The program writes its result in its own data folder, which it can already do.
2. Its tool result names what it made: `"outputs": [{ "data": "out/1.jpg", "name": "trip.jpg", "source": "/Users/ada/Downloads/trip.heic" }]`.
3. Sidefolk, not the program, checks and places each one, and records it in the audit trail.

**What the host enforces** (with the coordinator's additions; D140 needs independent review of all of it)

- **Destination:** beside a file the person dropped or picked in this same call, and only there. Never a system or hidden folder (`FolderAccess.forbiddenReason`). The program can't name any other destination.
- **The file in the data folder:** a regular file inside that folder, with no symlink and one hard link, opened without following links. Reading elsewhere through the host's own privileges is the main risk this guards against.
- **The name:** a bare name with no path parts or leading dot, and a length cap.
- **The type:** its ending must be on an allow-list and match what the extension declares in its manifest.
- **Size:** a cap, with the value set in D140. It has to leave room for long video.
- **No overwriting:** placing uses an exclusive create, and a clash gets a new unique name such as `trip 2.jpg`.
- **The placed file:** it loses any execute bit and carries the quarantine attribute.
- **Audit:** one entry for each placement.

**Why this is better than a sandbox grant**

- A sandbox rule that lets a program create and then write files in a folder could let it change other files there too. I didn't test how narrow that rule can be made.
- The host knows exactly which file it created, which option C needs.

**Costs**

- Output is written twice when the destination is on another disk (a copy rather than a move).
- Conversion needs free space on the home disk.
- It's a new kind of tool result, so `ToolExecutor` must apply it after the call, inside the same audit entry.

The destination folder may still need macOS's own permission (Desktop, Documents, Downloads), which macOS asks for on Sidefolk's behalf.

## 3. Option C (D142): Open, Show and Undo

The founder's words on Open and Show: "Allow both". Sidefolk draws the actions. They act only on a file the host placed in section 2,
only on the person's click, and extensions can't call them. I'd name the result part `outputs` and the actions `open_result`, `show_result` and
`undo_result`, none of which clash with Noor's or Sideflow's reserved names.

**Before Open**

- The file is checked again: a regular file, not a link, the same identity (device and inode) as when placed, inside the destination.
- Its type must be on the allow-list, checked by its ending *and* its contents: **images, audio, video, PDF, plain text and CSV.**
- **Anything else: Open isn't drawn, and Show still works.** That includes Office files, archives, HTML, SVG (it can carry scripts), apps, scripts, installers (`pkg`, `dmg`), `command`, `terminal`, `webloc` and `url`.

**Show** only reveals the file in Finder, after the same identity check.

**Undo** moves the placed file to the Trash, only if its identity and modification time still match. Otherwise it says the file has changed and
leaves it. The original is never touched.

## 4. Questions for reviewers

**Answered by Sideflow and Noor**

1. No flow step or plan reads `paths` other than through `scope(for:)` (section 1, Compatibility).
2. `ExtensionPlans.matches` is stricter than I read it, and lists fail towards a card.
3. An additive `pickedFiles` is acceptable for now. Folding it into one list later is cleaner, but would change Noor's two call sites during the landing queue.
4. `pickedFiles` fits T12 and T43 under the conditions in section 1.

**Decided by the founder (2026-11-03)**

Asked "Should dropping a file grant a read on all drops, or only for the new key?", the founder answered "All drops". Sideflow, the coordinator and I had recommended the new key only. No shipped extension declares a file drop today, so nothing shipped changes now (section 1).

**Answered by the coordinator**

- Section 2 adds no new sandbox rule but is a new host capability, reviewed as listed there.
- A drop as a pick is right in principle, and the founder decided its scope (above).
- The Open allow-list is the one in section 3.
