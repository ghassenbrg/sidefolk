# Which extensions should ship with Sidefolk

> **Status:** decided and partly built (26 October 2026, DECISIONS D39). Git, World Clock, System
> Vitals and Weather ship switched on (Weather since 27 October); the rest of this page is the backlog
> and the reasoning behind it.

Sidefolk ships **no Core extension**, **three Bundled ones** (Git, World Clock, System Vitals: installed
and on, each can be switched off) and **one Optional one** (Weather: installed, off until the person
switches it on). Everything else on the founder's list is either better as a built-in tool (Calendar,
Mail, Music, Shortcuts, the clipboard: they need macOS permissions a sandboxed extension can never have),
better as the vendor's own MCP server (Notion, Linear, Jira, Slack, GitHub pull requests: they need the
person's account), or waits for a platform piece this study found missing (secrets for extensions,
a per-host network allow-list, Unix sockets). The extension builder covers the long tail in between:
when nothing in the catalog fits, Sidefolk's AI drafts a small extension for that person.

## What decides where a capability belongs

An extension is a folder with a manifest and a program that Sidefolk runs under `sandbox-exec` with only
what the manifest asks for (docs/EXTENSIONS.md). That sandbox is the whole point, and it also draws
the line:

| An extension can | An extension can't |
|---|---|
| Use the internet (all of it, or nothing) | Send Apple Events: other apps' content (Mail, Notes, Music, Calendar) |
| Read or change folders fixed in its manifest | Use the pasteboard, LaunchServices or the screen |
| Read or change a folder the person names in one request (`tools.<name>.paths`, new in D39) | Keep a secret (API key, token): there is nowhere to put one yet |
| Run listed programs, and `git` found by name (new in D39) | Connect to a Unix socket (Docker, many local daemons) |
| Run a check every 5 minutes or more (watchers) | Act on its own between checks, or run for more than 300 s per call |
| Speak MCP with Python 3.9's standard library, Node or sh | Reach the model with its own descriptions, unless it ships in the app (D24, D39) |

So each candidate falls into one of four homes:

1. **Built-in tool** (Swift, in the app): needs a macOS permission (Automation, EventKit), AppKit, or
   approval wording Guard must control exactly. Precedent: Apple Notes (D38).
2. **Bundled extension** (shipped in `extensions/`, listed in `extensions/catalog.json`): first-party
   code that fits the sandbox and helps many people.
3. **MCP server from the vendor** (Settings › Extensions › Add MCP Server): a service that needs the
   person's account. Unsandboxed by nature, labelled so (T16).
4. **Drafted extension** (the build-extension skill): small, specific to one person, fits the sandbox.

## How candidates were weighed

- **Value:** how many people would use it, and how often. A companion's daily questions beat a
  specialist's weekly one.
- **Risk:** what it may touch (network, folders, programs) and what leaves the Mac. A bundled extension
  is on for everyone, so its permissions must be defensible to someone who never asked for it.
- **Maintenance:** external APIs that change, keys to rotate, OS behaviour to re-verify each macOS
  release. Every bundled extension is code Sidefolk owns forever.
- **Fit now:** whether the sandbox and today's manifest can do it well, not eventually.

## Core: none

A Core tier (always on, can't be disabled) would only make sense for something Sidefolk can't work
without. Nothing qualifies: reminders, notes, watching, files, the web and the Mac's own apps are built-in
tools, and anything fundamental should stay one (D38). An extension is by definition an addition, and an
addition the person can't refuse contradicts "the user decides what you may do". If a capability ever
becomes that fundamental, it should move into the app, not be locked on as an extension.

## Bundled: on by default, switchable

| Extension | What it does | Permissions | Value | Risk | Maintenance |
|---|---|---|---|---|---|
| **Git** | `clone` a public https repository into a folder the person names; `status`, `pull` (fast-forward only) and `log` of a repository they name | Internet; git (Apple's or Homebrew's, found by name); a folder named per request, opened for that call only | High for developers, the founder's own example ("clone this repository under ~/git"); harmless for others (it does nothing until asked) | Medium: every call asks (network floor), the folder card names the exact folder; no SSH keys, no stored passwords, no hooks, no submodules, no system or global config | Low: git's CLI is stable; the sandbox rules for its https helper are tested |
| **World Clock** | The time in any place; a time converted between places, with daylight saving exact | None at all | High: a daily companion question that models answer wrongly around clock changes | None: no files, no network, every tool runs without a card | Very low: the time zone database is macOS's own |
| **System Vitals** | Battery, disk and memory; watchers for a low battery and a low disk | `pmset`, `vm_stat`, `sysctl` | Medium, and it is the sample people read first | Low: read-only system programs | Low |

Git's write access is the interesting part. A fixed `files.write` folder would have meant guessing where
people keep code (`~/git`, `~/code`, `~/Developer`…) and keeping that folder open at all times. Instead
its tools declare which parameter is a folder; Guard checks it against the folders the person shared,
asks "Let Sidefolk work in ~/git?" when it isn't shared, and the call runs in a process of its own whose
sandbox opens just that folder and ends with the call.

## Optional: shipped, off until switched on

| Extension | What it does | Permissions | Why off by default |
|---|---|---|---|
| **Weather** | Conditions now and for up to 7 days; a "Rain soon" watcher that fires once per wet spell | Internet (Open-Meteo, no account) | The place the person asks about goes to a third party. Useful daily, but that choice is theirs. |

Optional is the right tier for anything that sends the person's words to an outside service, or that
only some people want.

## Ideas: later, built-in, or for partners

| Idea | Best home | Value | Risk | Maintenance | What it needs first |
|---|---|---|---|---|---|
| Calendar (today, next meeting, free slots) | Built-in, EventKit | Very high | Medium (private data, read-only first) | Low | PRODUCT §13; EventKit expands repeating events, Apple Events doesn't (D38) |
| Mail (unread from people, find a message) | Built-in, Apple Events, read-only | High | High (private content, injection-prone) | Medium | The Notes pattern (D38): fixed scripts, typed tools, untrusted results |
| Music and Spotify (play, pause, what's playing) | Built-in, Apple Events | Medium | Low | Medium (two apps' dictionaries) | Automation per app; tiny fixed scripts |
| Shortcuts (run one of the person's shortcuts) | Built-in | Very high: a bridge to everything Shortcuts reaches | High: a shortcut can do anything; every run asks, never "always" | Low | `shortcuts run` needs the ShortcutsEvents service the sandbox (rightly) denies |
| Clipboard history | Built-in, off by default | Medium | High (passwords pass through the clipboard) | Low | A strong privacy design; the sandbox denies the pasteboard |
| Screenshots and OCR of the screen | Never | — | Screen Recording is on SECURITY's never list | — | — |
| OCR of image files in a named folder | Bundled extension, compiled helper using Vision | Medium | Low (read-only, folder per call) | Medium | Verify Vision works under `sandbox-exec` (it may need mach services) |
| Image tools (resize, convert HEIC to JPEG) | Bundled, `/usr/bin/sips` + folder per call | Medium | Low | Low | Nothing: it fits today. **Next candidate.** |
| RSS and Atom feeds (latest items; "new post" watcher) | Optional, internet | Medium | Low (reads public feeds) | Low | Nothing: it fits today. **Next candidate.** |
| Homebrew (outdated, info) | Optional, `brew` by name | Medium for developers | Medium (brew runs Ruby and writes caches) | Medium | Program-by-name support for `brew`, its caches pointed at the data folder |
| GitHub pull requests and CI | MCP server from GitHub today; later Optional | High for developers | Medium | Medium | Secrets for extensions (a token); public repositories could work without one (60 requests an hour) |
| Docker (containers, logs) | Optional | Medium | Medium | Medium | A Unix-socket permission for the Docker socket |
| Translate | The model already does it | Low | — | — | — |
| Web search | MCP server (Brave, Kagi, Exa) | High | Medium | Medium | Secrets for extensions; result quality |
| Focus timers, timers | Built-in reminders already | Low | — | — | Watchers check every 5 minutes at best: wrong tool for timers |
| Finder organizing | Built-in file tools and the organize-downloads skill | — | — | — | Already shipped |
| Notion, Linear, Jira, Slack, Google Drive | Vendor MCP servers now; partner extensions later | High for teams | Medium–high (accounts, team data) | Owned by the vendor | Secrets and an OAuth helper; a directory with verified publishers |
| Home Assistant, Hue | Partner or drafted extension | Medium | Medium (devices in the home) | Medium | A local-network allow-list and secrets |
| Currency rates (ECB reference rates) | Drafted on demand | Low | Low | Low | Nothing; a good builder demo |

## Platform pieces this catalog asks for

In the order they unlock the most:

1. **Secrets for extensions.** A Keychain item per extension (as MCP servers have), filled by the person
   in Settings, handed to the process in its environment, named on the install sheet ("Uses a key you
   give it for api.github.com"). Unlocks GitHub, web search, Notion-style connectors and Home Assistant.
2. **A per-host network allow-list.** `"network": ["api.open-meteo.com"]` enforced by a local egress
   proxy (SECURITY §3, P1), so "can use the internet" becomes "can reach api.open-meteo.com" and the
   install sheet stops warning about uploads it can't do.
3. **Extension settings.** The watcher `config` schema reused for the extension itself (a home city, a
   default folder), edited in Settings.
4. **Unix-socket and local-network permissions**, each named on the sheet, for Docker and home devices.
5. **Long work with progress.** A call that may run for minutes and report progress, instead of the
   300-second ceiling.

## How companies would publish extensions

"Any company should be able to make an extension that links Sidefolk to whatever they do." The format
already allows it (docs/EXTENSIONS.md, and `skills/sidefolk-extension/SKILL.md` for developers and their
agents). What's missing is trust at a distance. A proposal, none of it built:

- **Package.** A `.sidefolkext` file: the folder zipped, plus `signature.json` signing the SHA-256 of every
  file (the same list Sidefolk already pins at install). A company signs with its Apple Developer ID
  (codesign of the package, checked by `SecStaticCode`) or a key published at
  `https://<domain>/.well-known/sidefolk-extension-keys.json`. The manifest's reverse-DNS id must match
  the signer's domain (`com.linear.*` only from linear.app's key).
- **Trust levels**, shown on every sheet and row, deciding what reaches the model:

  | Level | Who | Sandbox | Tool descriptions reach the model |
  |---|---|---|---|
  | Built in | Sidefolk, inside the signed app | Yes | Yes (D39) |
  | Verified | Signed by a publisher whose domain the directory checked, reviewed | Yes | Yes, once reviewed |
  | Signed | Signed by a known publisher, not reviewed | Yes | No (D24) |
  | Local | A folder, or a draft Sidefolk wrote for the person | Yes | No (D24) |
  | MCP server | Anything the person adds by command | **No** | No |

- **Directory.** A static, signed JSON index Sidefolk hosts (id, publisher, version, download URL,
  SHA-256, the permission summary, review state), browsed in Settings. "Get" is a click: download,
  check hash and signature, then the normal install preview. Nothing installs from a link or a web page.
- **Review.** Automatic: the validator, a trial start with nothing granted, permission minimality
  (network plus folders needs a reason), no interpreters in `exec`. Human: anything with folders and
  the internet together, and every Verified publisher's first version.
- **Updates.** Opt-in checks (D15 still holds: no silent updates). An update shows the permission and tool
  diff; a gain in permissions waits for the person, as built-in updates already do (D39). Tool
  descriptions that change are held (T14).
- **Revocation.** The directory can list a version as withdrawn; Sidefolk then turns it off with a notice
  saying why, and keeps the person's data.

## What was built in this round

- `extensions/git`, `extensions/world-clock`, `extensions/weather`, icons for all shipped extensions
  (`scripts/extension-icons.swift`), and `extensions/catalog.json`.
- `BundledExtensions` (install, update, keep the person's choice, refuse removal), program-by-name
  (`ProgramResolver`), folders named per call (`tools.<name>.paths`), per-tool `timeout`, manifest `icon`.
- The builder: `extensions.draft`, `extensions.review`, `extensions.read_draft` and the `build-extension`
  skill; `skills/sidefolk-extension/SKILL.md` for developers.
- Tests: `BuiltInExtensionTests` (including the founder's request through the agent loop, offline and,
  with `SIDEFOLK_LIVE_NETWORK=1`, a real clone), `BundledExtensionsTests`, `ExtensionBuilderTests`,
  `ManifestIconAndProgramTests`.
