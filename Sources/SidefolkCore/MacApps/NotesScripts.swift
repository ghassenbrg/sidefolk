// The JavaScript for Automation programs Sidefolk sends to Notes (DECISIONS D38). Each defines
// `main(app, params)` and returns plain JSON; `AutomationScript` wraps it. Property names follow
// Notes' scripting dictionary (/System/Applications/Notes.app/Contents/Resources/Notes.sdef).
//
// Bulk reads (`folder.notes.name()`) are one Apple Event for a whole folder; per-note reads are kept
// to the notes a call is about. Nothing here writes, except `remove`, which only runs for notes the
// tool checked first (`AppleNotesRemoveTool`).

enum NotesScripts {
    /// "No such note" and "invalid index": the note went away between the list and this call.
    private static let missing = """
        function missing(e) { return !!e && (e.errorNumber === -1728 || e.errorNumber === -1719); }
        """

    /// Accounts, every folder (with the folders that list it, so Swift can rebuild the tree whichever
    /// way Notes reports nesting), and every note's id, title, folder, dates and lock. No bodies.
    static let index = """
        function main(app, params) {
          const accounts = [], folders = [], notes = [], seen = {};
          const accs = app.accounts;
          const accIds = accs.id(), accNames = accs.name();
          for (let a = 0; a < accIds.length; a++) {
            accounts.push({ id: accIds[a], name: accNames[a] });
            visit(accs.byId(accIds[a]), accIds[a], null);
          }
          function visit(container, account, parent) {
            const list = container.folders;
            const ids = list.id(), names = list.name();
            for (let i = 0; i < ids.length; i++) {
              const id = ids[i];
              if (seen[id]) { if (parent !== null) seen[id].parents.push(parent); continue; }
              const folder = { id: id, name: names[i], account: account, parents: parent === null ? [] : [parent] };
              seen[id] = folder;
              folders.push(folder);
              const f = list.byId(id), n = f.notes;
              const noteIds = n.id();
              if (noteIds.length > 0) {
                const titles = n.name(), created = n.creationDate(), modified = n.modificationDate(), locked = n.passwordProtected();
                for (let j = 0; j < noteIds.length; j++) {
                  notes.push({ id: noteIds[j], name: titles[j], folder: id, created: created[j], modified: modified[j], locked: locked[j] });
                }
              }
              visit(f, account, id);
            }
          }
          return { accounts: accounts, folders: folders, notes: notes };
        }
        """

    /// The start of each note's plain text and how many attachments it has, for a page of a list.
    static let snippets = missing + """

        function main(app, params) {
          const out = {};
          for (const id of params.ids) {
            const note = app.notes.byId(id);
            try {
              const locked = note.passwordProtected();
              out[id] = { text: locked ? '' : note.plaintext().slice(0, params.maxChars), attachments: note.attachments.length };
            } catch (e) {
              if (!missing(e)) throw e;
            }
          }
          return out;
        }
        """

    /// Whole notes: where they are, their dates, their HTML body (embedded images replaced by an
    /// empty `data:` so a photo never travels as megabytes of base64) and their attachments' names.
    static let fetch = missing + """

        function main(app, params) {
          const out = [];
          for (const id of params.ids) {
            const note = app.notes.byId(id);
            let item;
            try {
              item = { id: id, name: note.name() };
            } catch (e) {
              if (missing(e)) { out.push({ id: id, missing: true }); continue; }
              throw e;
            }
            // Each part on its own: Notes answers "Can't get object" (-1728) for some attachments
            // (inline links, tags, tables) and some containers, and one such part must cost neither
            // the note nor the rest of the batch.
            try { const folder = note.container; item.folder = folder.id(); item.folderName = folder.name(); } catch (e) {}
            try { item.created = note.creationDate(); } catch (e) {}
            try { item.modified = note.modificationDate(); } catch (e) {}
            try { item.locked = note.passwordProtected(); } catch (e) { item.locked = false; }
            const atts = note.attachments;
            try {
              item.attachments = atts.name().map(n => n || '');
            } catch (e) {
              item.attachments = [];
              item.attachmentsPartial = true;
              try {
                const count = atts.length;
                for (let i = 0; i < count; i++) {
                  try { item.attachments.push(atts[i].name() || ''); } catch (e2) { item.attachments.push(''); }
                }
              } catch (e2) {}
            }
            try { item.cids = atts.contentIdentifier().map(c => c || ''); } catch (e) { item.cids = []; }
            if (!item.locked) {
              try {
                const html = note.body().replace(/(\\bsrc\\s*=\\s*["'])data:[^"']*/gi, '$1data:');
                item.truncated = html.length > params.maxChars;
                item.html = html.slice(0, params.maxChars);
              } catch (e) {
                item.unreadable = (e && e.errorNumber) || -1;
              }
            }
            out.push(item);
          }
          return out;
        }
        """

    /// Deletes notes the tool already checked; Notes moves them to its Recently Deleted folder. Reports
    /// where each one is afterwards, so Sidefolk says "moved" only when it saw it there.
    static let remove = missing + """

        function main(app, params) {
          const out = [];
          for (const id of params.ids) {
            const note = app.notes.byId(id);
            try { note.name(); } catch (e) {
              if (missing(e)) { out.push({ id: id, status: 'missing' }); continue; }
              throw e;
            }
            app.delete(note);
            let folder = null;
            try { folder = app.notes.byId(id).container.name(); } catch (e) { if (!missing(e)) throw e; }
            out.push({ id: id, status: folder === null ? 'gone' : 'deleted', folder: folder });
          }
          return out;
        }
        """
}
