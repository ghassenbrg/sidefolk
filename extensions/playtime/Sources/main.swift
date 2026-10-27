import SidefolkExtensionKit

// Playtime, an extension that ships with Sidefolk: small games for a break. No permissions; scores stay in its
// own folder.
let ext = Extension(name: "playtime")

ext.tool("chance", "Coin, dice and random picks",
         "Truly random: flip coins, roll dice (2d6, d20, 3d8+2), pick a number, or pick from a list of choices. Use it whenever "
         + "the user wants chance to decide.",
         input: Schema.object([
             "kind": Schema.string("What to do.", oneOf: ["coin", "dice", "number", "pick"]),
             "dice": Schema.string("For dice: like 2d6 or d20 (1d6 if not given).", maxLength: 20),
             "count": Schema.integer("For coin: how many flips; for pick: how many to pick (1 if not given).", minimum: 1, maximum: 20),
             "min": Schema.integer("For number: the lowest (1 if not given)."),
             "max": Schema.integer("For number: the highest (100 if not given)."),
             "choices": Schema.array(of: Schema.string("One choice.", maxLength: 100), "For pick: the choices.", maxItems: 50),
         ], required: ["kind"])) { args in
    switch args.string("kind") {
    case "coin": return Chance.coin(args.int("count") ?? 1)
    case "dice": return try Chance.dice(args.string("dice") ?? "1d6")
    case "number": return try Chance.number(args.int("min") ?? 1, args.int("max") ?? 100)
    default: return try Chance.pick(args.strings("choices"), count: args.int("count") ?? 1)
    }
}

ext.tool("trivia", "Trivia quiz",
         "A trivia quiz with a score that is kept between games. Call it without an answer for a question; call it with the "
         + "user's answer (A, B, C or D) to check it and get the next question. Show the question and choices as given.",
         input: Schema.object([
             "answer": Schema.string("The user's answer to the last question: A, B, C or D.", maxLength: 60),
             "category": Schema.string("For a new question: \(Trivia.categories.joined(separator: ", ")), or any.", maxLength: 20),
         ])) { args in
    try Trivia.play(answer: args.string("answer"), category: args.string("category"))
}

ext.tool("rock_paper_scissors", "Rock, paper, scissors", "Plays one round of rock, paper, scissors against the user, keeping the score.",
         input: Schema.object(["move": Schema.string("The user's move.", oneOf: Hands.moves)], required: ["move"])) { args in
    try Hands.play(try args.required("move"))
}

await ext.serve()
