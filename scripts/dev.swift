// Drives a running debug build (build/Sidefolk-dev.app) without clicks, for agents and tests by hand.
// Debug builds listen for these distributed notifications; release builds don't (`#if DEBUG`).
//
//   swift scripts/dev.swift snap                 PNG of every visible window in $SIDEFOLK_HOME/snapshots
//   swift scripts/dev.swift "ask:remind me in 2 min to stretch"
//   swift scripts/dev.swift respond:done | dismiss | approve | approveAlways | deny | hideAsk
//   swift scripts/dev.swift home | settings:extensions | find:milk | drop:https://example.com
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
