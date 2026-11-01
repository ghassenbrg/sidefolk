// Drives a running debug build (build/Sidefolk-dev.app) without clicks, for agents and tests by hand.
// Debug builds listen for these distributed notifications; release builds don't (`#if DEBUG`). Set SIDEFOLK_HOME to
// the app's home so only that app acts (otherwise every running debug app does).
//
//   swift scripts/dev.swift snap                 PNG of every visible window in $SIDEFOLK_HOME/snapshots
//   swift scripts/dev.swift "ask:remind me in 2 min to stretch"
//   swift scripts/dev.swift "type:time in Tokyo"    (typed but not sent: the hint shows what Enter would do)
//   swift scripts/dev.swift respond:done | dismiss | approve | approveAlways | deny | hideAsk
//   swift scripts/dev.swift home | about | settings:trust | find:milk | drop:https://example.com
//   swift scripts/dev.swift settings:search:quiet | settings:jump:quietHours | settings:full-access   (D84: Settings' search,
//                           a jump to a setting by its SettingKey, the Full access sheet)
//   swift scripts/dev.swift pocket   (D84: opens or closes the menu bar's Pocket)
//   swift scripts/dev.swift attention:focus:60 | attention:quiet | attention:open   (D84: Focus or Quiet, minutes or for good)
//   swift scripts/dev.swift scroll:1   (the tallest scroll view on screen to the bottom, 0…1, before a snap)
//   swift scripts/dev.swift calendar | calendar:agenda | calendar:week:2026-11-03 | calendar:month   (D66, D84)
//   swift scripts/dev.swift review:<draft name>    (opens the install preview of ExtensionDrafts/local.<name>)
//   swift scripts/dev.swift installFolder:/path/to/extension | page:dev.sidefolk.system-vitals-plus/mac   (D62)
//   swift scripts/dev.swift home:today | home:calendar | home:notebook | home:onduty | home:history[:agents] | home:you
//                           | home:trash | home:gallery   (D84: Home's places) | flip:dev.sidefolk.keep-awake/awake:off   (D67)
//   swift scripts/dev.swift palette:dev.sidefolk.clipboard/history | paletteKey:down | paletteKey:35:opt   (D63, D68: ⌥P)
//   swift scripts/dev.swift reviewFolder:/path/to/extension   (its install preview, as Settings shows it)
//   swift scripts/dev.swift companion:mochi | companion:mochi:2d | companion:sidefolk:coral   (as the Settings picker does)
//   swift scripts/dev.swift addCompanion:/path/to/folder | companion:local:<name>[:2d|3d]   (a companion from a folder, D60, D85)
//   swift scripts/dev.swift chooser:gallery | chooser:search:cat (Home's Gallery, D84) | chooser:detail:rune | chooser:get:rune
//                           | chooser:remove:local:cumulus | chooser:confirm (its Remove) | chooser:add | chooser:snapshots (Show Snapshots) | chooser:close
//                           (Settings › Companion's chooser)
//   swift scripts/dev.swift language:fr | language:system   (relaunches in that language)
//   swift scripts/dev.swift theme:harbor | themeFolder:/path/to/theme   (D58: a theme, or a folder followed as it's saved)
//   swift scripts/dev.swift voice:file:/tmp/x.aiff | voice:stop   (talks with a file instead of the microphone, D34)
//   swift scripts/dev.swift swipe:-140 | swipe:end   (two fingers sideways over the newest Ask result)
//   swift scripts/dev.swift tip:0 | tip:off | recede:on | recede:off | stack:on | stack:off | grow   (D84: an extra's tip beside
//                           the companion, the extras stepping back, the held cards fanned, a whisper grown into a card)
//   swift scripts/dev.swift play:dance | play:catch_me | play:breathe | click   (D44; click is a click on the companion)
//   swift scripts/dev.swift game:dev.sidefolk.playtime/which_cup | move:{"cell":[0,1]} | key:1 | closeGame | playMenu   (D75, D79)
//                           | cue:sulk | cue:tease | cue:accent:wave   (a game cue's move, as an open game's board plays it)
//   swift scripts/dev.swift drag:0,0,1,2   (a puzzle's plot dragged corner to corner, cell by cell, then let go)
//   swift scripts/dev.swift toss:coin[:3] | toss:dice[:2[:20]] | toss:rps:rock   (a coin, dice or a hand, through companion.toss)
//   swift scripts/dev.swift update:offer | update:notice | update:downloading | update:downloaded | update:failed
//                           | update:uptodate | update:check   (D46: the update window and bubble with a made-up version)
//   swift scripts/dev.swift update:ready | update:updated   (D70: installing by itself: the window waiting for a calm
//                           moment, and the note the new copy gives)
//   swift scripts/dev.swift connect:claude[:hooks] | connect:codex[:hooks] | connect:cli | disconnect:claude|codex|cli
//                           (D86: Connections' cards with their dialog accepted, logged; only on a SIDEFOLK_HOME, where
//                           they write the stand-ins in agent-configs/, never the person's agents)
//   swift scripts/dev.swift addons:review | addons:waiting | addons:clear   (D70: Settings › Updates and the heads-up
//                           with made-up add-on updates)
import Foundation

guard let argument = CommandLine.arguments.dropFirst().first else {
    print("usage: swift scripts/dev.swift snap | <command>   (see the comment at the top of this file)")
    exit(2)
}
// Every debug app hears these notifications. With SIDEFOLK_HOME set, only the app using that home acts on them:
// with several running side by side, one's `ask:` would otherwise reach the others (and their AI).
let home = ProcessInfo.processInfo.environment["SIDEFOLK_HOME"].map {
    URL(fileURLWithPath: $0).standardizedFileURL.resolvingSymlinksInPath().path
}
let target: [AnyHashable: Any]? = home.map { ["home": $0] }
let center = DistributedNotificationCenter.default()
if argument == "snap" {
    center.postNotificationName(.init("app.sidefolk.dev.snapshot"), object: nil, userInfo: target, deliverImmediately: true)
} else {
    center.postNotificationName(.init("app.sidefolk.dev.command"), object: argument, userInfo: target, deliverImmediately: true)
}
RunLoop.current.run(until: Date().addingTimeInterval(0.2))
