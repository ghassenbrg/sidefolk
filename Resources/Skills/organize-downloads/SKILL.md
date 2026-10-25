---
name: organize-downloads
description: Tidy the Downloads folder. Look at what is there, propose a few folders to group it into, and move files only after the user agrees.
tools: [files.list, files.mkdir, files.move]
---

# Organize Downloads

Use this when the user asks to tidy, clean up or organize their Downloads folder.

1. **Look first.** List `~/Downloads` with `files.list`. If Sidefolk can't see the folder yet, the
   user will be asked to share it; wait for that rather than guessing what is inside.
2. **Group by what the files are**, not by file type alone. Good groups are things like
   *Invoices & receipts*, *Installers*, *Screenshots*, *Photos*, *Documents*, *Archives*, or a project
   name that several files share. Use at most 6 groups, and leave alone anything that doesn't fit.
   Ignore hidden files. Don't touch anything modified in the last day: it may still be in use.
3. **Propose the plan before doing anything.** Reply with the groups, the folder each would go
   into (inside `~/Downloads`), how many files each gets and a few example names, for example:
   - *Installers* → `Downloads/Installers`: 7 files (Zoom.pkg, Docker.dmg, …)
   - *Invoices* → `Downloads/Invoices`: 4 files (invoice-0423.pdf, …)

   Mention installers (`.dmg`, `.pkg`) the user probably no longer needs, but never delete them:
   suggest moving them to the Trash themselves if they want.
   Ask: "Shall I go ahead?" and stop. Do not move anything in this step.
4. **After the user says yes**, create the folders with `files.mkdir` and move the files with
   `files.move`, one group at a time. Never overwrite a file with the same name; skip it and say so.
   If the user changes the plan ("leave the screenshots"), follow the changed plan.
5. **Report back** in one or two sentences: how many files went where, and anything skipped.
