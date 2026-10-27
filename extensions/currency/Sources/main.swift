import SidefolkExtensionKit

// Currency, an extension that ships with Sidefolk: the internet (one public file from the ECB), nothing else.
let ext = Extension(name: "currency")

ext.tool("convert_currency", "Convert money",
         "Converts an amount between currencies with the European Central Bank's reference rates (EUR and 30 major currencies "
         + "such as USD, JPY, GBP, CNY, CHF, INR, BRL, CAD, AUD), published each working day.",
         input: Schema.object([
             "amount": Schema.number("How much (1 for the rate itself)."),
             "from": Schema.string("The currency it is in: a code like USD or a name like yen.", maxLength: 30),
             "to": Schema.array(of: Schema.string("A currency code or name.", maxLength: 30), "The currencies wanted.", maxItems: 10),
         ], required: ["amount", "from", "to"])) { args in
    guard let amount = args.double("amount") else { throw Problem("“amount” must be a number.") }
    return try await Rates.convert(amount, from: try args.required("from"), to: args.strings("to"))
}

ext.watcher("rate_crosses") { settings, state in
    try await Rates.crosses(settings, state: state)
}

await ext.serve()
