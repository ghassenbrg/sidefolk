# Formatic: a quicker way in

> The pictures this names are kept out of the repository, in `sandbox/formatic-research/` on the founder's Mac. The icon is in `icon/` here.

2026-11-03. The founder approved the flow and asked for something in the spirit of Filee: a shortcut or a panel, perhaps a circle, so that "you just do this or that". Not a copy. This is a proposal, and nothing is built.

Pictures: [light](ring-light.png), [dark](ring-dark.png), [second set](ring-second-light.png). The founder preferred the version with glass slices and a vivid slice under the pointer, and asked for more choices, so it now has eight, plus a second set of eight.

## The ring

Hold a key while dragging a file. What it can become opens around the pointer, with the file in the middle. Drop on a slice to choose. Let go anywhere else and nothing happens.

**Where it differs from Filee's donut:**

- Outcomes first ("Opens anywhere", "For email"), not a wheel of format names.
- The file itself sits in the middle, so you see what you're holding.
- Sidefolk's own line sits under the ring and says who reads the file and that it can't use the internet.
- The result arrives as the same working card and receipt, beside your companion.
- It may need no Accessibility permission, which Filee needs for its gesture on a Mac. That isn't proven yet.

**The rules:**

- **General, not Formatic's alone (D98):** the ring draws any extension's file offers from its manifest. The app names no extension.
- **Eight slices, two sets.** Tab or the scroll wheel turns the ring to a second set of eight, with less common formats and quick changes like "Half the size". A drag can't open a menu, and both still work with a mouse button held.
- **The slices come from the file's type.** A photo, a song and a PDF each show their own eight.
- **The middle does nothing,** and every slice is a short move away, so a stray release doesn't choose.
- **Noor's drop rules apply:** the ring is the extension's words, and the line under it is Sidefolk's. Several files show the exact count, and the names appear when you hold over the middle. An extension with `network` gets the amber warning.
- **Off until the person turns it on,** in Settings, with the key they choose. It needs a watcher on every drag, so it should be their choice.
- **Accessibility:** the ring can't be reached by keyboard or VoiceOver during a drag, so the drop card and the right-click stay the complete way to do everything.

## How you open it

| You're doing | You press | What happens |
|---|---|---|
| Dragging a file | Hold ⌥ Option, or the key you chose | The ring opens at the pointer. Drop on a slice |
| A file selected in Finder | ⌃⌥F, or the keys you chose | The ring opens at the pointer. Click a slice |
| Nothing selected | The same keys | Sidefolk says to select a file first, and nothing else happens |

- **Why ⌃⌥F:** ⌥⌘F is commonly Find and Replace in other apps, so a global shortcut shouldn't take it. No Sidefolk session uses ⌃⌥F (coordinator's check). Off by default and changeable by the person, using D84's pattern: `KeyboardShortcuts.Name`, and never a shortcut macOS or Sidefolk already uses.
- **The selected-file shortcut has two possible routes.** A macOS Service with a default key needs no permission that I know of, but macOS doesn't promise the key will be free. A global shortcut that asks Finder for its selection needs macOS's Automation permission once. To be tested. A click on the ring keeps Noor's brief click guard.
- **On the Home page:** a "Quick ways in" section shows both as keycaps you can change, with one switch for the ring. These settings belong to Sidefolk, since the ring is a general ability. The page shows them through a Sidefolk-drawn part, which is new, because the existing `settings` button only opens a fixed pane. It must be a general part that names no extension, and it's to be checked against Noor's `settings` action.

## Two separate decisions

These are separate, so either can be taken without the other.

### D151: Send to Sidefolk, from Finder's right-click

A macOS Service, where macOS hands the selected files to Sidefolk as a drop does. It's the same grant as a drop and opens the same card. The person can give it a keyboard shortcut in System Settings. I expect it needs no permission, but I haven't tested it. **I'd take this first:** it's the smallest, and it covers "within the file".

### D152: The ring

**What has to be checked:**

- **Permission:** exactly what macOS asks for. It may turn out to need Input Monitoring or Accessibility. The test prints whether its process already has Accessibility, because a permission held by the terminal could hide this.
- **Cost:** the global mouse watcher already costs 1 to 5% of a core in bursts (`docs/STATUS.md`). The test prints its CPU use. It must be measured again in the real app, on a long drag.
- **Reading:** nothing about a drag is read until the key is held. After that, only the paths on the drag pasteboard, plus a thumbnail by the system's out-of-process service. No extension gets anything until the file is dropped on a slice. macOS may also show a pasteboard privacy prompt.
- **Drawing over other apps:** it must behave over full-screen apps and in other Spaces. Any test in a debug app uses `SIDEFOLK_QUIET_WINDOWS=1`.
- **Off by default,** turned on by the person in Settings.

The test is a small throwaway program, `ringtest`, and it needs a person to drag a real file. Sidefolk already has a global mouse monitor at `CompanionWindowController.swift:741`.

**Result (the founder, 2026-11-03): it passed.** Run from Terminal, dragging one file with ⌥ held:

- The panel appeared at the pointer, felt the drag enter, and received the drop.
- `AXIsProcessTrusted` was false, so it worked without Accessibility.
- It used 0.23 s of CPU over 9 s, 2.5% of one core, on a short drag.

**What that doesn't settle yet:**

- **Permission in the real app:** the test ran as Terminal's child, so anything Terminal already holds, such as Input Monitoring, could hide a need. Whether macOS showed a question still has to be asked. Sidefolk has to be tried itself, on a Mac and a user that haven't granted it anything.
- **Cost:** a long drag in the real app, measured with Sidefolk's own watcher.
- **Reach:** full-screen apps, other Spaces, and more than one display.
- **The drag's contents:** this panel read the file list while ⌥ was held. The rule stays that nothing is read before the key is held.

It needs an independent security review, and it's more work than the Service. The test passing removes the reason it might have been impossible, not the reason to wait: I'd still build it only if the Service feels too slow in real use, and only after the founder says go. D151 comes first.

**If it goes ahead, in this order:** a general host part that draws any extension's file offers, off by default, with those checks done in the debug app first and the review before any release.

## Order

D151 first, then D152 if the test passes. Both come after options A, B and C, because they end in the same drop card and receipt.
