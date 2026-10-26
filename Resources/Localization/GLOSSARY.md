# Glossary for translators

Sidefolk is a small companion that lives on the Mac desktop. It remembers things, reminds, watches
web pages, files and programs, and acts for its person through tools they approve. Every string
people read is in `Localizable.xcstrings` (one String Catalog, ten languages: en, fr, es, de, it,
pt-BR, ja, ko, zh-Hans, ar). Text written for the AI model is not in the catalog and stays English.

## Never translate

| Name | What it is |
|---|---|
| Sidefolk | The app, and the default name of the robot companion. |
| Mochi | The white rabbit companion, the brand mascot. |
| Spark | The little robot companion with headphones. |
| Pip, Byte, Seed, Melody, Scout, Tempo, Play, Guard, Nova, Brew | The folks, small characters with a job each (Pip: ideas and notes; Tempo: reminders; Scout: watching; Byte: agents and extensions; Guard: security and approvals …). Guard is a name here, not the word "guard". |
| Claude, Claude Code, Codex, Anthropic, Ollama, OpenAI | Other companies' products. |
| MCP, MCP server | A technical standard; keep the abbreviation. |
| `sidefolk mcp`, `sidefolk ext validate`, `claude update`, SKILL.md, files.mkdir, files.read | Commands, files and tool names. |
| “kind”, “target”, “when”, “level”, “interval_minutes” … | Field names in quotes inside error messages. Keep them exactly. |

Names of macOS places (Finder, Terminal, Keychain Access, System Settings › Privacy & Security ›
Files and Folders) take Apple's own name for them in your language.

## Product terms

Translate these once and use the same word everywhere, including in Settings and buttons.

| Term | Meaning |
|---|---|
| Notebook | Where notes, ideas, tasks and links are kept. |
| Inbox | The notebook collection where a note goes when no place is named. |
| About you | The notebook collection of facts and preferences Sidefolk keeps in mind. Shown in quotes inside sentences: “About you”. |
| collection, project, topic, list | Places in the notebook. A list is a shopping or to-do list. |
| note, idea, task, link | The four kinds of notebook item. |
| Now | The Home page that shows what is live: reminders, watches, agent sessions, things waiting. |
| Activity | The log of every action Sidefolk or an agent took. |
| Trash | Use your language's name for the macOS Trash (Corbeille, Papelera, Papierkorb, Cestino, Lixeira, ゴミ箱, 휴지통, 废纸篓, سلة المهملات). Things stay there 30 days. |
| watch, watcher, watching | Sidefolk keeping an eye on something (a page, a site, a file, a folder, a program, a command) and saying when it happens. "A watch" and "a watcher" are the same thing. |
| reminder | Something Sidefolk tells you at a time. Done, Snooze ("10 min", "Tomorrow"). |
| quiet mode, Quiet | While it is on, only urgent things interrupt. |
| the Ask panel | The small window beside the companion where you type a request. |
| hint line | The line under the input that says what Enter will do, ending in "no AI" when no AI model is used. |
| approval, Allow once, Always allow | Sidefolk asking before it does something. |
| extension, skill | Add-ons: an extension brings tools and watchers; a skill is written instructions. |
| folk, on duty | A folk is "on duty" while its job is live (a reminder is near, a watch is running). |

## Addressing the person

Chosen once for the whole app (rule 4). A companion is close to its person, so use the warmer form
wherever the language's software allows it.

| Language | "You" | Buttons and menu items |
|---|---|---|
| fr | vous | infinitive (Supprimer, Réessayer) |
| es | tú | infinitive (Eliminar, Reintentar) |
| de | du | infinitive (Löschen, Erneut versuchen) |
| it | tu | imperative, as macOS does (Elimina, Riprova) |
| pt-BR | você | infinitive (Apagar, Tentar de novo) |
| ja | です・ます; leave "you" out as Japanese does, never あなた | noun or する form (削除, もう一度試す) |
| ko | 해요체; leave "you" out, never 당신 | noun or 하기 (삭제, 다시 시도) |
| zh-Hans | 你 | verb (删除, 重试) |
| ar | Modern Standard Arabic, masculine singular where a form is unavoidable, as macOS does | verbal noun (حذف, إعادة المحاولة) |

The companion says "I" and has no gender: word its sentences so nothing agrees with it (French
"C'est fait" rather than "Je suis prêt"). Where a form is unavoidable, use the grammatical default.
Do the same for the person.

## Rules

1. **Example commands stay in English.** The understanding of typed requests without AI is English
   only, so anything in quotes that shows what to type stays as it is: “remind me at 5 to stretch”,
   “tomorrow 9am”, “in 20 minutes”, “every weekday at 9”. Words the person typed come back in some
   messages (“Yesterday has passed.” is built from what they typed): translate the sentence, keep
   their words.
2. **Placeholders.** Keep every `%@`, `%lld` and `%d`, no more and no fewer. To change their order,
   number them: `%2$@ … %1$@`. A key with several placeholders already shows them numbered in its
   English value; the comment says what each one is when it is not obvious.
3. **Counts.** `%lld` before a noun is a count, and the key has English plural forms (one, other).
   Give your language's forms: Arabic needs zero, one, two, few, many and other; French, Spanish,
   Italian, Portuguese and German one and other; Japanese, Korean and Chinese only other. The count
   comes first in these keys and must stay the first argument.
4. **Voice** (docs/VOICE.md): short, plain and warm. Lead with the thing. No exclamation marks, no
   emoji, no jokes in errors. "I" is the companion speaking about what it did or will do. Errors say
   what failed, whether anything changed ("Nothing was changed."), and one next step. Translate
   "Nothing was changed." exactly the same way everywhere, as the last sentence: when something did
   change, the app removes that ending and adds its own sentence instead. Buttons are
   verbs. Where your language has formal and informal "you", choose once for the whole app and keep
   it everywhere.
5. **Fragments.** Some keys are pieces of a sentence and start in lower case because they continue
   one: "when it changes" follows "I'll tell you %@"; "notes", "ideas" and "notebook" follow
   "Search %@"; "open that folder" follows "macOS didn't let me %@ at %@."; "5 min" follows "every %@".
   Translate them so the whole sentence reads well, and keep the case.
6. **Punctuation.** The English text uses “curly quotes”; use your language's own (« » in French,
   „ “ in German, 「」 in Japanese). Keep " · " between parts of a line and "›" between menu levels
   (Settings › AI), and translate the menu names to match the app's own translation of them.
7. **Dates and times** are never written into strings: the app formats them in the person's language
   and always uses a 24-hour clock. "Today", "Tomorrow" and "Yesterday" are their own keys.
8. **Left in English on purpose:** what the AI model reads (tool results, tool descriptions,
   prompts), the `sidefolk` command-line tool's output, the extension manifest checks shown to
   extension authors, and logs.
9. **Room.** Some words sit in tight places: the six Settings tab names share one toolbar; the
   Activity table's chips (Low, Medium, High, Automatic, Allowed, Always, Denied, Blocked, Failed)
   and the segmented choices (All, Notes, Ideas, Tasks, Links; Idle, Thinking, Working, Sleeping;
   Small, Medium, Large) are short labels. Choose short words there. Sentences can run longer:
   buttons stack and lines wrap.
10. **The confirmation word.** Deleting everything asks the person to type a word ("delete", lower
   case); translate it as one short lower-case word. The English word works in every language.
11. **Check your work** in pictures: `swift run SidefolkApp --ui-snapshots /tmp/ui-fr --language fr`
   renders every page in light and dark with the catalog as it is.
