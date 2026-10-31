// Drives a running debug build (build/Sidefolk-dev.app) without clicks, for agents and tests by hand.
// Debug builds listen for these distributed notifications; release builds don't (`#if DEBUG`). Set SIDEFOLK_HOME to
// the app's home so only that app acts (otherwise every running debug app does).
//
//   swift scripts/dev.swift snap                 PNG of every visible window in $SIDEFOLK_HOME/snapshots
//   swift scripts/dev.swift "ask:remind me in 2 min to stretch"
//   swift scripts/dev.swift "type:time in Tokyo"    (typed but not sent: the hint shows what Enter would do)
//   swift scripts/dev.swift respond:done | dismiss | approve | approveAlways | deny | hideAsk
//   swift scripts/dev.swift home | about | settings:extensions | find:milk | drop:https://example.com
//   swift scripts/dev.swift review:<draft name>    (opens the install preview of ExtensionDrafts/local.<name>)
//   swift scripts/dev.swift installFolder:/path/to/extension | page:dev.sidefolk.system-vitals-plus/mac   (D62)
//   swift scripts/dev.swift home:today | page:/ (All Extensions) | flip:dev.sidefolk.keep-awake/awake:off   (D67)
//   swift scripts/dev.swift palette:dev.sidefolk.clipboard/history | paletteKey:down | paletteKey:35:opt   (D63, D68: ⌥P)
//   swift scripts/dev.swift companion:mochi | companion:mochi:2d | companion:sidefolk:coral   (as the Settings picker does)
//   swift scripts/dev.swift addCompanion:/path/to/folder | companion:local:<name>   (a 3D companion from a folder, D60)
//   swift scripts/dev.swift language:fr | language:system   (relaunches in that language)
//   swift scripts/dev.swift theme:harbor | themeFolder:/path/to/theme   (D58: a theme, or a folder followed as it's saved)
//   swift scripts/dev.swift voice:file:/tmp/x.aiff | voice:stop   (talks with a file instead of the microphone, D34)
//   swift scripts/dev.swift swipe:-140 | swipe:end   (two fingers sideways over the newest Ask result)
//   swift scripts/dev.swift play:dance | play:catch_me | play:breathe | click   (D44; click is a click on the companion)
//   swift scripts/dev.swift toss:coin[:3] | toss:dice[:2[:20]] | toss:rps:rock   (a coin, dice or a hand, through companion.toss)
//   swift scripts/dev.swift update:offer | update:notice | update:downloading | update:downloaded | update:failed
//                           | update:uptodate | update:check   (D46: the update window and bubble with a made-up version)
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
