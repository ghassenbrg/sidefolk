import Foundation
import SidefolkExtensionKit

// Calculator, an extension that ships with Sidefolk: sums, units and dates worked out exactly. No permissions.
let ext = Extension(name: "calculator")

ext.tool("calculate", "Calculate",
         "Works out arithmetic exactly: + - * / ^, percentages (\"15% of 80\", \"200 + 10%\"), parentheses, sqrt, abs, round, "
         + "ln, log, sin/cos/tan (degrees), pi and e. Use it for any sum instead of working it out yourself.",
         input: Schema.object(["expression": Schema.string("The calculation, like (12.5 * 4) + 15% or sqrt(2).", maxLength: 300)],
                              required: ["expression"])) { args in
    let expression = try args.required("expression")
    return "\(expression) = \(Arithmetic.show(try Arithmetic.evaluate(expression)))"
}

ext.tool("convert_units", "Convert units",
         "Converts between units of length, weight, volume (US cups and gallons), area, speed, time, data (MB, GiB, megabits), "
         + "energy, pressure, angles and temperature.",
         input: Schema.object([
             "value": Schema.number("How many."),
             "from": Schema.string("The unit it is in, like km, °F, cups, GB.", maxLength: 40),
             "to": Schema.string("The unit wanted.", maxLength: 40),
         ], required: ["value", "from", "to"])) { args in
    guard let value = args.double("value") else { throw Problem("“value” must be a number.") }
    return try Units.convert(value, from: try args.required("from"), to: try args.required("to"))
}

ext.tool("date_math", "Date maths",
         "Days between two dates (with weeks and weekdays), a date plus or minus an amount (3 weeks, -10 days, 2 months, "
         + "5 weekdays), or what day a date falls on. Dates are YYYY-MM-DD, \"25 December 2026\", \"December 25\" or today.",
         input: Schema.object([
             "date": Schema.string("The date to start from (today if not given).", maxLength: 40),
             "to": Schema.string("A second date, to count the days between.", maxLength: 40),
             "add": Schema.string("An amount to add, like 3 weeks or -10 days.", maxLength: 40),
         ])) { args in
    let date = try Dates.parse(args.string("date"))
    if let to = args.string("to") { return Dates.between(date, try Dates.parse(to)) }
    if let amount = args.string("add") {
        let result = try Dates.add(amount, to: date)
        let worded = amount.hasPrefix("-") ? "minus " + amount.dropFirst().trimmingCharacters(in: .whitespaces)
            : "plus " + amount.trimmingCharacters(in: CharacterSet(charactersIn: "+ "))
        return "\(Dates.show(date)) \(worded) is \(Dates.show(result))."
    }
    return Dates.describe(date)
}

await ext.serve()
