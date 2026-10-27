// Drives a running debug build (build/Sidefolk-dev.app) without clicks, for agents and tests by hand.
// Debug builds listen for these distributed notifications; release builds don't (`#if DEBUG`).
//
//   swift scripts/dev.swift snap                 PNG of every visible window in $SIDEFOLK_HOME/snapshots
//   swift scripts/dev.swift "ask:remind me in 2 min to stretch"
//   swift scripts/dev.swift respond:done | dismiss | approve | approveAlways | deny | hideAsk
//   swift scripts/dev.swift home | about | settings:extensions | find:milk | drop:https://example.com
//   swift scripts/dev.swift review:<draft name>    (opens the install preview of ExtensionDrafts/local.<name>)
//   swift scripts/dev.swift companion:mochi | companion:sidefolk:coral   (as the Settings picker does)
//   swift scripts/dev.swift language:fr | language:system   (relaunches in that language)
//   swift scripts/dev.swift voice:file:/tmp/x.aiff | voice:stop   (talks with a file instead of the microphone, D34)
//   swift scripts/dev.swift swipe:-140 | swipe:end   (two fingers sideways over the newest Ask result)
//   swift scripts/dev.swift play:dance | play:catch_me | play:breathe | click   (D44; click is a click on the companion)
import Foundation

guard let argument = CommandLine.arguments.dropFirst().first else {
    print("usage: swift scripts/dev.swift snap | <command>   (see the comment at the top of this file)")
    exit(2)
}
let center = DistributedNotificationCenter.default()
if argument == "snap" {
    center.postNotificationName(.init("app.sidefolk.dev.snapshot"), object: nil, userInfo: nil, deliverImmediately: true)
} else {
    center.postNotificationName(.init("app.sidefolk.dev.command"), object: argument, userInfo: nil, deliverImmediately: true)
}
RunLoop.current.run(until: Date().addingTimeInterval(0.2))
