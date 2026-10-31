import Foundation
import SidefolkExtensionKit

// Water Tally, a Sidefolk extension template: tools (with commands in the manifest that answer without the AI), a page
// in Home with a tile on Today, and a watcher the page shows as a heads-up switch. It needs no permission: it keeps
// one small file in its own data folder. Nothing may reach stdout but the Kit's replies; log to stderr.
let ext = Extension(name: "water-tally")
let store = TallyStore(folder: URL(fileURLWithPath: Paths.data, isDirectory: true))

// The model doesn't read third-party descriptions (D24): titles and parameter names carry the meaning, so keep them
// plain, and bound every input. Throw `Problem` for something the person or the model can fix.
ext.tool("log_water", "Log glasses of water", "Adds glasses of water drunk just now to today's tally.",
         input: Schema.object(["glasses": Schema.integer("How many glasses, 1 if missing.", minimum: 1, maximum: 10)])) { args in
    let n = args.int("glasses") ?? 1
    let now = Date()
    return store.change(now) { $0.times += Array(repeating: now, count: n) }.sentence
}
ext.tool("water_today", "Water drunk today", "How many glasses of water today, against the daily goal.") { _ in
    store.today().sentence
}
ext.tool("set_goal", "Set the daily water goal", "Sets how many glasses a day to aim for.",
         input: Schema.object(["goal": Schema.integer("Glasses a day.", minimum: 1, maximum: 30)], required: ["goal"])) { args in
    guard let goal = args.int("goal") else { throw Problem("Say how many glasses a day, from 1 to 30.") }
    return "Your water goal is \(goal) glasses a day. " + store.change { $0.goal = goal }.sentence
}
// Only the page's switch and the manifest's commands reach this one ("ai": false): the model never sees it.
ext.tool("set_option", "Water Tally setting", "Turns a choice on or off: large_glasses.",
         input: Schema.object(["option": Schema.string("Which.", oneOf: ["large_glasses"]), "on": Schema.boolean("On or off.")],
                              required: ["option", "on"])) { args in
    let on = args.bool("on") ?? true
    store.change { $0.largeGlasses = on }
    return on ? "Counting 500 ml glasses." : "Counting 250 ml glasses."
}

// `args.string("language")` is the person's language (en, fr, ar); this page is English, as extension pages are for now.
ext.page("water") { _ in WaterPage.make(store.today()) }

// Triggers on change, not on level: once a day at most, remembering the day it told in the state Sidefolk keeps.
ext.watcher("behind") { settings, state in
    let now = Date()
    let t = store.today(now)
    let toldOn = state["told_on"] as? String
    let behind = t.behind(now: now, afterHour: settings.int("after_hour") ?? 15, toldOn: toldOn)
    return Check(triggered: behind, state: ["told_on": behind ? t.day : toldOn ?? ""],
                 summary: behind ? "Time for some water: \(t.sentence)" : t.sentence)
}

await ext.serve()
